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

    # Save proposals for review
    existing_proposals = []
    if PROPOSALS_FILE.exists():
        try:
            existing_proposals = json.loads(PROPOSALS_FILE.read_text())
        except Exception:
            pass

    all_proposals = existing_proposals + all_proposals
    PROPOSALS_FILE.write_text(json.dumps(all_proposals, indent=2))

    state["last_run"] = datetime.now(timezone.utc).isoformat()
    save_state(state)

    if all_proposals:
        summary_lines = [f"Memory extraction found {len(all_proposals)} proposed additions:"]
        for p in all_proposals[-5:]:  # show last 5
            summary_lines.append(f"  [{p['type']}] {p['name']}")
        if len(all_proposals) > 5:
            summary_lines.append(f"  ...and {len(all_proposals) - 5} more")
        summary_lines.append("")
        summary_lines.append("Review with: python3 ~/.max/scripts/memory-apply.py --review")

        msg = "\n".join(summary_lines)
        print(msg)
        send_telegram(msg)
    else:
        print("No new memory proposals.")

    print(f"Done. Proposals saved to {PROPOSALS_FILE}")


if __name__ == "__main__":
    main()
