#!/usr/bin/env python3
"""
skill-scout.py — Nightly autonomous skill generation pipeline.

Scans recent conversation indexes for recurring task patterns, compares against
existing skills, and proposes new skill files for Josh's approval via Telegram.

Flow:
  1. Read recent conversation-index/*.md files since last run
  2. Call Claude to identify recurring patterns (2+ similar tasks)
  3. Compare against existing skills in ~/.claude/skills/
  4. Draft proposed SKILL.md files for genuinely new skills
  5. Save proposals to ~/.max/state/skill-proposals.json
  6. Send Telegram notification with summary

Usage:
  python3 skill-scout.py              # analyze since last run
  python3 skill-scout.py --since 2026-03-28
  python3 skill-scout.py --status     # show last run + pending proposals
  python3 skill-scout.py --apply      # apply pending proposals
  python3 skill-scout.py --reject     # discard pending proposals
"""

import json
import os
import sys
import subprocess
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

CONV_INDEX_DIR = Path.home() / ".max/conversation-index"
SKILLS_DIR = Path.home() / ".claude/skills"
STATE_FILE = Path.home() / ".max/state/skill-scout-state.json"
PROPOSALS_FILE = Path.home() / ".max/state/skill-proposals.json"
LOG_FILE = Path.home() / ".max/logs/skill-scout.log"
TELEGRAM_CHAT_ID = "1295061383"

SCOUT_PROMPT = """You are analyzing conversation logs between Josh Centers and Max, his Claude-based AI assistant.

Your job: identify recurring task patterns that would benefit from a formal skill file.

A skill file is a markdown document that tells Max exactly how to perform a specific task — step-by-step instructions, format rules, output paths, API calls, etc. Skills are stored in ~/.claude/skills/{{skill-name}}/SKILL.md.

EXISTING SKILLS (do NOT propose these — they already exist):
{existing_skills}

RECENT CONVERSATIONS (last {days} days):
{conversations}

Look for:
1. Tasks Max performed 2+ times in similar ways
2. Tasks with clear, repeatable steps that aren't already a skill
3. Tasks where Max had to figure out the same thing from scratch each time
4. Workflows that involved multiple tools in a specific sequence

Do NOT propose skills for:
- One-off tasks with no clear recurrence pattern
- Tasks already covered by existing skills
- Simple lookups or single-tool operations
- Highly personalized tasks that can't generalize

For each identified pattern, draft a complete SKILL.md file. Be specific — the skill should tell Max exactly what to do, not just describe what the task is.

Return a JSON array of proposed skills. Each item:
{{
  "skill_name": "kebab-case-name",
  "description": "One-line description of what this skill does",
  "evidence": "Brief description of the pattern you saw (how many times, what context)",
  "skill_content": "Full SKILL.md content as a string"
}}

If no patterns are strong enough to warrant a new skill, return an empty array [].
Only return the JSON array, no other text."""


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


DIGEST_FILE = Path.home() / ".max/state/nightly-digest.txt"


def send_telegram(text):
    # If NIGHTLY_MODE is set, write to digest file instead of sending immediately.
    # Morning briefing picks this up and includes it in the 7 AM summary.
    if os.environ.get("NIGHTLY_MODE"):
        DIGEST_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(DIGEST_FILE, "a") as f:
            f.write(f"\n[skill-scout] {text}\n")
        log("(nightly mode: buffered to digest)")
        return

    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not token:
        env_file = Path.home() / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                if line.startswith("export TELEGRAM_BOT_TOKEN="):
                    token = line.split("=", 1)[1].strip().strip('"')
                    break
    if not token:
        log("WARNING: No TELEGRAM_BOT_TOKEN — skipping Telegram")
        return
    payload = json.dumps({
        "chat_id": TELEGRAM_CHAT_ID,
        "text": text,
    }).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
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


def load_proposals():
    if PROPOSALS_FILE.exists():
        return json.loads(PROPOSALS_FILE.read_text())
    return []


def save_proposals(proposals):
    PROPOSALS_FILE.parent.mkdir(parents=True, exist_ok=True)
    PROPOSALS_FILE.write_text(json.dumps(proposals, indent=2))


def get_existing_skills():
    if not SKILLS_DIR.exists():
        return []
    return sorted([d.name for d in SKILLS_DIR.iterdir() if d.is_dir()])


def get_recent_conversations(since_date):
    sessions = []
    for f in sorted(CONV_INDEX_DIR.glob("*.md")):
        parts = f.stem.split("-")
        if len(parts) < 4:
            continue
        try:
            file_date = datetime.strptime("-".join(parts[:3]), "%Y-%m-%d").date()
        except ValueError:
            continue
        if file_date < since_date:
            continue
        sessions.append(f)
    return sessions


def apply_proposals(proposals):
    if not proposals:
        print("No pending proposals.")
        return

    git_dirs = []
    for p in proposals:
        skill_dir = SKILLS_DIR / p["skill_name"]
        skill_dir.mkdir(parents=True, exist_ok=True)
        skill_file = skill_dir / "SKILL.md"
        skill_file.write_text(p["skill_content"])
        print(f"  Written: {skill_file}")
        git_dirs.append(str(SKILLS_DIR))

    # Commit to skills git repo
    try:
        result = subprocess.run(
            ["git", "-C", str(SKILLS_DIR), "add", "."],
            capture_output=True, text=True
        )
        names = ", ".join(p["skill_name"] for p in proposals)
        subprocess.run(
            ["git", "-C", str(SKILLS_DIR), "commit", "-m",
             f"Add auto-generated skills: {names}\n\nGenerated by skill-scout.py from conversation pattern analysis."],
            capture_output=True, text=True
        )
        print(f"  Committed to skills repo.")
    except Exception as e:
        print(f"  Git commit failed: {e}")

    save_proposals([])
    log(f"Applied {len(proposals)} skill proposals.")


def main():
    show_status = "--status" in sys.argv
    do_apply = "--apply" in sys.argv
    do_reject = "--reject" in sys.argv

    state = load_state()
    proposals = load_proposals()

    if show_status:
        print(f"Last run: {state.get('last_run', 'never')}")
        print(f"Pending proposals: {len(proposals)}")
        for p in proposals:
            print(f"  [{p['skill_name']}] {p['description']}")
        return

    if do_reject:
        count = len(proposals)
        save_proposals([])
        print(f"Discarded {count} proposals.")
        return

    if do_apply:
        apply_proposals(proposals)
        return

    # Determine date range
    since_date = None
    if "--since" in sys.argv:
        idx = sys.argv.index("--since")
        since_date = datetime.strptime(sys.argv[idx + 1], "%Y-%m-%d").date()
    elif state.get("last_run"):
        since_date = datetime.fromisoformat(state["last_run"]).date() - timedelta(days=1)
    else:
        since_date = (datetime.now(timezone.utc) - timedelta(days=14)).date()

    sessions = get_recent_conversations(since_date)
    if not sessions:
        log("No recent sessions to analyze.")
        return

    log(f"Analyzing {len(sessions)} sessions since {since_date}...")

    # Build conversation digest (cap at 12000 chars total)
    conv_text = ""
    for f in sessions:
        content = f.read_text()
        header = f"\n\n### {f.stem}\n"
        # Trim individual sessions to avoid overwhelming context
        if len(content) > 1500:
            content = content[:1500] + "\n[...truncated]"
        if len(conv_text) + len(header) + len(content) > 12000:
            break
        conv_text += header + content

    existing_skills = get_existing_skills()
    days = (datetime.now().date() - since_date).days

    prompt = SCOUT_PROMPT.format(
        existing_skills="\n".join(f"- {s}" for s in existing_skills),
        conversations=conv_text,
        days=days,
    )

    log("Calling Claude for pattern analysis...")
    try:
        response = call_claude(prompt)
        # Strip markdown fences if present
        response = response.strip()
        if response.startswith("```"):
            response = response.split("```")[1]
            if response.startswith("json"):
                response = response[4:]
        new_proposals = json.loads(response)
    except Exception as e:
        log(f"Analysis failed: {e}")
        return

    if not new_proposals:
        log("No new skill patterns identified.")
        state["last_run"] = datetime.now(timezone.utc).isoformat()
        save_state(state)
        return

    # Merge with existing proposals (deduplicate by skill_name)
    existing_names = {p["skill_name"] for p in proposals}
    added = []
    for p in new_proposals:
        if p["skill_name"] not in existing_names:
            proposals.append(p)
            added.append(p)

    save_proposals(proposals)
    state["last_run"] = datetime.now(timezone.utc).isoformat()
    save_state(state)

    if added:
        # Auto-apply immediately
        apply_proposals(added)
        save_proposals([])  # clear after applying

        lines = [f"Skill Scout added {len(added)} new skill(s):"]
        for p in added:
            lines.append(f"  [{p['skill_name']}] {p['description']}")
        lines.append("")
        lines.append("Undo: git -C ~/.claude/skills revert HEAD")
        msg = "\n".join(lines)
        log(msg)
        send_telegram(msg)
    else:
        log("No new proposals after deduplication.")


if __name__ == "__main__":
    main()
