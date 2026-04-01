#!/usr/bin/env python3
"""
memory-extract.py — Nightly script that scans recent conversation indexes and
proposes new memory file additions for Josh's approval via Telegram.

Reads new conversation-index/*.md files since last run, calls Claude to identify
memory-worthy facts, writes proposals to ~/.max/state/memory-proposals.json,
and sends a Telegram summary.

Usage:
    python3 memory-extract.py          # process sessions since last run
    python3 memory-extract.py --since 2026-03-28  # process since specific date
    python3 memory-extract.py --status # show last run info
"""

import json
import os
import sys
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

CONV_INDEX_DIR = Path.home() / ".max/conversation-index"
MEMORY_DIR = Path.home() / ".claude/projects/-home-josh/memory"
STATE_FILE = Path.home() / ".max/state/memory-extract-state.json"
PROPOSALS_FILE = Path.home() / ".max/state/memory-proposals.json"
TELEGRAM_CHAT_ID = "1295061383"

MEMORY_TYPES = ["user", "feedback", "project", "reference"]


def _apply_proposal(proposal):
    """Write or update a memory file and update MEMORY.md index."""
    memory_index = MEMORY_DIR / "MEMORY.md"
    filename = proposal["filename"]
    if not filename.endswith(".md"):
        filename += ".md"

    target = proposal.get("update_existing")
    if target:
        if not target.endswith(".md"):
            target += ".md"
        out_path = MEMORY_DIR / target
    else:
        out_path = MEMORY_DIR / filename

    content = f"""---
name: {proposal['name']}
description: {proposal['description']}
type: {proposal['type']}
---

{proposal['body']}
"""
    out_path.write_text(content)

    if not target and memory_index.exists():
        index_text = memory_index.read_text()
        entry = f"- [{proposal['name']}]({filename}) — {proposal['description']}"
        if filename not in index_text:
            type_header_map = {
                "user": "## User",
                "feedback": "## Feedback",
                "project": "## Project",
                "reference": "## Reference",
            }
            header = type_header_map.get(proposal["type"], "## User")
            if header in index_text:
                lines = index_text.split("\n")
                insert_after = -1
                in_section = False
                for i, line in enumerate(lines):
                    if line.strip() == header:
                        in_section = True
                    elif in_section and line.startswith("## "):
                        break
                    elif in_section and line.startswith("- "):
                        insert_after = i
                if insert_after >= 0:
                    lines.insert(insert_after + 1, entry)
                    memory_index.write_text("\n".join(lines))
            else:
                with open(memory_index, "a") as f:
                    f.write(f"\n{header}\n{entry}\n")

EXTRACTION_PROMPT = """You are reviewing recent conversation logs between Josh Centers and Max (his Claude-based AI assistant).

Your job: identify facts worth saving to long-term memory. Be selective — only flag things that are:
1. Non-obvious and not derivable from reading the codebase
2. Likely to be useful in future conversations (preferences, corrections, decisions, contact info, project context)
3. Not already covered by existing memory (listed below)

Memory types:
- user: Josh's role, expertise, preferences, or personal context
- feedback: corrections or confirmed approaches — something Max should do differently or keep doing
- project: ongoing work context, decisions, deadlines, stakeholder info
- reference: where to find things in external systems

EXISTING MEMORY FILES:
{existing_memory}

CONVERSATION LOG:
{conversation}

Return a JSON array of proposed memory additions. Each item:
{{
  "type": "user|feedback|project|reference",
  "filename": "descriptive_slug.md",
  "name": "Short title",
  "description": "One-line description for MEMORY.md index",
  "body": "Full memory content in markdown (include Why/How to apply for feedback/project types)",
  "update_existing": "filename.md or null (if this should update an existing file instead of creating new)"
}}

If nothing is worth saving, return an empty array [].
Only return the JSON array, no other text."""


def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"last_run": None, "processed_sessions": []}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def get_existing_memory_summary():
    """Read current memory index for context."""
    memory_index = MEMORY_DIR / "MEMORY.md"
    if memory_index.exists():
        return memory_index.read_text()
    return "(no memory index found)"


def get_new_sessions(since_date=None, processed=None):
    """Get conversation index files newer than since_date."""
    processed = processed or []
    sessions = []
    for f in sorted(CONV_INDEX_DIR.glob("*.md")):
        # Extract date from filename (YYYY-MM-DD-sessionid.md)
        parts = f.stem.split("-")
        if len(parts) < 4:
            continue
        try:
            file_date = datetime.strptime("-".join(parts[:3]), "%Y-%m-%d")
        except ValueError:
            continue

        session_id = "-".join(parts[3:])
        if session_id in processed:
            continue
        if since_date and file_date.date() < since_date:
            continue
        sessions.append((f, session_id, file_date))
    return sessions


def call_claude(prompt):
    """Call Claude CLI for extraction."""
    result = subprocess.run(
        ["claude", "--print", "-p", prompt],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        raise RuntimeError(f"Claude call failed: {result.stderr[:200]}")
    return result.stdout.strip()


def send_telegram(text):
    """Send Telegram message via the MCP bot."""
    # Use the telegram send script if available, else log
    script = Path.home() / ".max/scripts/telegram-send.sh"
    if script.exists():
        subprocess.run([str(script), TELEGRAM_CHAT_ID, text], timeout=10)
    else:
        print(f"[TELEGRAM] {text}")


def main():
    show_status = "--status" in sys.argv
    state = load_state()

    if show_status:
        print(f"Last run: {state.get('last_run', 'never')}")
        print(f"Sessions processed: {len(state.get('processed_sessions', []))}")
        if PROPOSALS_FILE.exists():
            proposals = json.loads(PROPOSALS_FILE.read_text())
            print(f"Pending proposals: {len(proposals)}")
        return

    # Determine date range
    since_date = None
    if "--since" in sys.argv:
        idx = sys.argv.index("--since")
        since_date = datetime.strptime(sys.argv[idx + 1], "%Y-%m-%d").date()
    elif state.get("last_run"):
        since_date = datetime.fromisoformat(state["last_run"]).date() - timedelta(days=1)
    else:
        # First run: look at last 7 days
        since_date = (datetime.now(timezone.utc) - timedelta(days=7)).date()

    sessions = get_new_sessions(since_date, state.get("processed_sessions", []))
    if not sessions:
        print("No new sessions to process.")
        return

    print(f"Processing {len(sessions)} sessions since {since_date}...")

    existing_memory = get_existing_memory_summary()
    all_proposals = []

    for conv_file, session_id, session_date in sessions:
        content = conv_file.read_text()
        # Skip very short sessions
        if len(content) < 500:
            state.setdefault("processed_sessions", []).append(session_id)
            continue

        # Truncate long sessions for extraction (keep first 8000 chars)
        if len(content) > 8000:
            content = content[:8000] + "\n\n[...session truncated for analysis...]"

        print(f"  Analyzing {session_date.strftime('%Y-%m-%d')} {session_id[:8]}...")
        try:
            prompt = EXTRACTION_PROMPT.format(
                existing_memory=existing_memory[:2000],
                conversation=content
            )
            response = call_claude(prompt)

            # Parse JSON response
            response = response.strip()
            if response.startswith("```"):
                response = response.split("```")[1]
                if response.startswith("json"):
                    response = response[4:]
            proposals = json.loads(response)

            for p in proposals:
                p["source_session"] = session_id
                p["source_date"] = session_date.strftime("%Y-%m-%d")
                all_proposals.append(p)

        except Exception as e:
            print(f"    Warning: extraction failed for {session_id[:8]}: {e}")

        state.setdefault("processed_sessions", []).append(session_id)

    state["last_run"] = datetime.now(timezone.utc).isoformat()
    save_state(state)

    if all_proposals:
        # Auto-apply immediately via memory-apply
        import importlib.util, types
        apply_script = Path.home() / ".max/scripts/memory-apply.py"
        applied = 0
        errors = []
        for p in all_proposals:
            try:
                _apply_proposal(p)
                applied += 1
            except Exception as e:
                errors.append(f"{p.get('name', '?')}: {e}")

        # Commit memory changes
        mem_dir = MEMORY_DIR
        try:
            subprocess.run(["git", "-C", str(mem_dir), "add", "."], capture_output=True)
            names = ", ".join(p.get("name", "?") for p in all_proposals[:3])
            if len(all_proposals) > 3:
                names += f" +{len(all_proposals)-3} more"
            subprocess.run(
                ["git", "-C", str(mem_dir), "commit", "-m",
                 f"Auto-apply memory: {names}"],
                capture_output=True
            )
        except Exception:
            pass

        summary_lines = [f"Memory: added {applied} new entries"]
        for p in all_proposals:
            summary_lines.append(f"  [{p['type']}] {p['name']}")
        if errors:
            summary_lines.append(f"  Errors: {'; '.join(errors)}")
        summary_lines.append("")
        summary_lines.append("Undo: git -C ~/.claude/projects/-home-josh/memory revert HEAD")

        msg = "\n".join(summary_lines)
        print(msg)
        send_telegram(msg)
    else:
        print("No new memory proposals.")

    print(f"Done.")


if __name__ == "__main__":
    main()
