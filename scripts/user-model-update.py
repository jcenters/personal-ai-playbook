#!/usr/bin/env python3
"""
user-model-update.py — Dialectic user modeling.

Unlike memory-extract.py (which only appends new facts), this script maintains
a coherent, living model of Josh by actively reviewing and correcting existing
beliefs against recent conversation evidence.

The key distinction:
  memory-extract: "What new facts should we save?"
  user-model-update: "Is our current understanding of Josh still accurate?
                       What needs updating, correcting, or retiring?"

Flow:
  1. Read current user memory files (the existing model)
  2. Read recent conversation summaries (new evidence)
  3. Call Claude: compare model against evidence, identify contradictions and updates
  4. Apply corrections to user_*.md files
  5. Git commit with clear diff so Josh can see exactly what changed
  6. Buffer notification to nightly digest (or send immediately if run manually)

Usage:
  python3 user-model-update.py              # process recent sessions
  python3 user-model-update.py --since 2026-03-01
  python3 user-model-update.py --status
  python3 user-model-update.py --dry-run    # show proposed changes without applying
"""

import json
import os
import sys
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

MEMORY_DIR = Path.home() / ".claude/projects/-home-josh/memory"
CONV_INDEX_DIR = Path.home() / ".max/conversation-index"
STATE_FILE = Path.home() / ".max/state/user-model-state.json"
LOG_FILE = Path.home() / ".max/logs/user-model-update.log"
DIGEST_FILE = Path.home() / ".max/state/nightly-digest.txt"
TELEGRAM_CHAT_ID = "1295061383"

USER_MEMORY_FILES = [
    "user_josh.md",
    "user_life_context.md",
    "user_career.md",
    "user_contact_and_prefs.md",
]

DIALECTIC_PROMPT = """You are maintaining an accurate, up-to-date model of Josh Centers for his AI assistant Max.

Your job is NOT just to extract new facts. Your job is to review the CURRENT MODEL against RECENT EVIDENCE and:
1. Identify beliefs that are now outdated or incorrect (CORRECT them)
2. Identify beliefs that are confirmed by evidence (REINFORCE confidence)
3. Identify genuinely new facts not in the current model (ADD them)
4. Identify beliefs with no recent evidence either way (leave as-is)

This is dialectic modeling: you are actively resolving contradictions and updating beliefs, not just appending facts.

CURRENT USER MODEL:
{current_model}

RECENT CONVERSATIONS (last {days} days):
{recent_conversations}

Analyze carefully. Look for:
- Preferences that changed ("Josh used to prefer X but now does Y")
- Facts that were wrong ("We said X but it's actually Y")
- Stale status info ("We said 'applying to job X' but that concluded")
- Confirmed behaviors (Josh consistently does X despite older record suggesting otherwise)
- New context that changes how we should interpret existing facts

Return a JSON object with proposed changes:
{{
  "corrections": [
    {{
      "file": "user_josh.md",
      "old_text": "exact text to find and replace",
      "new_text": "corrected text",
      "reason": "why this is outdated/wrong"
    }}
  ],
  "additions": [
    {{
      "file": "user_life_context.md",
      "section": "## Health / Routine",
      "content": "new line or paragraph to add",
      "reason": "why this is worth adding"
    }}
  ],
  "retirements": [
    {{
      "file": "user_life_context.md",
      "old_text": "text to remove (outdated/no longer relevant)",
      "reason": "why this is no longer relevant"
    }}
  ],
  "summary": "One sentence describing what changed and why"
}}

Be conservative. Only propose changes when the evidence is clear. If you're not sure, leave it alone.
If nothing needs changing, return {{"corrections": [], "additions": [], "retirements": [], "summary": "No updates needed — model is current."}}

Only return the JSON object, no other text."""


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def send_notification(text):
    if os.environ.get("NIGHTLY_MODE"):
        DIGEST_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(DIGEST_FILE, "a") as f:
            f.write(f"\n[user-model] {text}\n")
        log("(nightly mode: buffered to digest)")
        return
    import urllib.request
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not token:
        env_file = Path.home() / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                if line.startswith("export TELEGRAM_BOT_TOKEN="):
                    token = line.split("=", 1)[1].strip().strip('"')
                    break
    if not token:
        log("No TELEGRAM_BOT_TOKEN")
        return
    payload = json.dumps({"chat_id": TELEGRAM_CHAT_ID, "text": text}).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        log(f"Telegram error: {e}")


def call_claude(prompt):
    result = subprocess.run(
        ["claude", "--print", "-p", prompt],
        capture_output=True, text=True, timeout=180
    )
    if result.returncode != 0:
        raise RuntimeError(f"Claude failed: {result.stderr[:300]}")
    return result.stdout.strip()


def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"last_run": None}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def read_current_model():
    parts = []
    for filename in USER_MEMORY_FILES:
        path = MEMORY_DIR / filename
        if path.exists():
            parts.append(f"=== {filename} ===\n{path.read_text()}")
    return "\n\n".join(parts)


def get_recent_conversations(since_date):
    sessions = []
    for f in sorted(CONV_INDEX_DIR.glob("*.md")):
        parts_name = f.stem.split("-")
        if len(parts_name) < 4:
            continue
        try:
            file_date = datetime.strptime("-".join(parts_name[:3]), "%Y-%m-%d").date()
        except ValueError:
            continue
        if file_date >= since_date:
            sessions.append(f)
    return sessions


def apply_changes(changes, dry_run=False):
    applied = []
    errors = []

    for correction in changes.get("corrections", []):
        path = MEMORY_DIR / correction["file"]
        if not path.exists():
            errors.append(f"File not found: {correction['file']}")
            continue
        content = path.read_text()
        old = correction["old_text"]
        new = correction["new_text"]
        if old not in content:
            errors.append(f"Text not found in {correction['file']}: {old[:60]}...")
            continue
        if not dry_run:
            path.write_text(content.replace(old, new, 1))
        applied.append(f"CORRECTED in {correction['file']}: {correction['reason']}")

    for retirement in changes.get("retirements", []):
        path = MEMORY_DIR / retirement["file"]
        if not path.exists():
            errors.append(f"File not found: {retirement['file']}")
            continue
        content = path.read_text()
        old = retirement["old_text"]
        if old not in content:
            errors.append(f"Text not found in {retirement['file']}: {old[:60]}...")
            continue
        if not dry_run:
            path.write_text(content.replace(old, "", 1))
        applied.append(f"RETIRED from {retirement['file']}: {retirement['reason']}")

    for addition in changes.get("additions", []):
        path = MEMORY_DIR / addition["file"]
        if not path.exists():
            errors.append(f"File not found: {addition['file']}")
            continue
        content = path.read_text()
        section = addition.get("section", "")
        new_content = addition["content"]
        if section and section in content:
            insert_after = content.index(section) + len(section)
            # Find end of section header line
            newline_pos = content.find("\n", insert_after)
            if newline_pos >= 0:
                if not dry_run:
                    path.write_text(
                        content[:newline_pos + 1] + "\n" + new_content + "\n" + content[newline_pos + 1:]
                    )
            else:
                if not dry_run:
                    path.write_text(content + "\n" + new_content)
        else:
            if not dry_run:
                with open(path, "a") as f:
                    f.write(f"\n{new_content}\n")
        applied.append(f"ADDED to {addition['file']}: {addition['reason']}")

    return applied, errors


def main():
    dry_run = "--dry-run" in sys.argv
    show_status = "--status" in sys.argv
    state = load_state()

    if show_status:
        print(f"Last run: {state.get('last_run', 'never')}")
        return

    since_date = None
    if "--since" in sys.argv:
        idx = sys.argv.index("--since")
        since_date = datetime.strptime(sys.argv[idx + 1], "%Y-%m-%d").date()
    elif state.get("last_run"):
        since_date = datetime.fromisoformat(state["last_run"]).date() - timedelta(days=2)
    else:
        since_date = (datetime.now(timezone.utc) - timedelta(days=14)).date()

    sessions = get_recent_conversations(since_date)
    if not sessions:
        log("No recent sessions to analyze.")
        return

    log(f"Analyzing {len(sessions)} sessions since {since_date}...")

    # Build conversation digest (cap at 10000 chars)
    conv_text = ""
    for f in sessions:
        content = f.read_text()
        header = f"\n\n### {f.stem}\n"
        if len(content) > 2000:
            content = content[:2000] + "\n[...truncated]"
        if len(conv_text) + len(header) + len(content) > 10000:
            break
        conv_text += header + content

    current_model = read_current_model()
    days = (datetime.now().date() - since_date).days

    prompt = DIALECTIC_PROMPT.format(
        current_model=current_model,
        recent_conversations=conv_text,
        days=days,
    )

    log("Calling Claude for dialectic analysis...")
    try:
        response = call_claude(prompt)
        response = response.strip()
        if response.startswith("```"):
            response = response.split("```")[1]
            if response.startswith("json"):
                response = response[4:]
        changes = json.loads(response.strip())
    except Exception as e:
        log(f"Analysis failed: {e}")
        return

    total_changes = (
        len(changes.get("corrections", [])) +
        len(changes.get("additions", [])) +
        len(changes.get("retirements", []))
    )

    if total_changes == 0:
        log(f"No updates needed: {changes.get('summary', '')}")
        state["last_run"] = datetime.now(timezone.utc).isoformat()
        save_state(state)
        return

    log(f"Found {total_changes} proposed changes. {'(dry run)' if dry_run else 'Applying...'}")

    applied, errors = apply_changes(changes, dry_run=dry_run)

    if not dry_run:
        # Commit changes
        try:
            subprocess.run(["git", "-C", str(MEMORY_DIR), "add", "."], capture_output=True)
            summary = changes.get("summary", f"{total_changes} user model updates")
            subprocess.run(
                ["git", "-C", str(MEMORY_DIR), "commit", "-m",
                 f"User model update: {summary}"],
                capture_output=True
            )
        except Exception as e:
            log(f"Git commit failed: {e}")

    for item in applied:
        log(f"  {item}")
    for err in errors:
        log(f"  ERROR: {err}")

    if not dry_run:
        state["last_run"] = datetime.now(timezone.utc).isoformat()
        save_state(state)

    if applied:
        lines = [f"User model updated ({len(applied)} changes):"]
        for item in applied[:5]:
            lines.append(f"  {item}")
        if len(applied) > 5:
            lines.append(f"  ...and {len(applied) - 5} more")
        lines.append("")
        lines.append(f"Summary: {changes.get('summary', '')}")
        lines.append("Undo: git -C ~/.claude/projects/-home-josh/memory revert HEAD")
        msg = "\n".join(lines)

        if dry_run:
            print("\n--- DRY RUN RESULTS ---")
            print(msg)
        else:
            send_notification(msg)

    log("Done.")


if __name__ == "__main__":
    main()
