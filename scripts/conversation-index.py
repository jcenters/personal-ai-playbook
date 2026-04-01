#!/usr/bin/env python3
"""
conversation-index.py — Extract readable conversation summaries from Claude JSONL sessions.

Reads ~/.claude/projects/-home-josh/*.jsonl and writes markdown files to
~/.max/conversation-index/ for qmd indexing and memory extraction.

Only processes sessions not yet indexed (tracks state in ~/.max/state/conv-index.json).
Safe to run repeatedly — idempotent.

Usage:
    python3 conversation-index.py          # index new sessions only
    python3 conversation-index.py --all    # reindex everything
    python3 conversation-index.py --status # show index state
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

JSONL_DIR = Path.home() / ".claude/projects/-home-josh"
INDEX_DIR = Path.home() / ".max/conversation-index"
STATE_FILE = Path.home() / ".max/state/conv-index.json"
MIN_MESSAGES = 3  # skip trivial sessions


def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"indexed": {}}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def extract_messages(jsonl_path):
    """Extract user text and assistant text turns from a JSONL session."""
    turns = []
    try:
        with open(jsonl_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                msg_type = obj.get("type")
                if msg_type not in ("user", "assistant"):
                    continue
                if obj.get("isMeta"):
                    continue

                message = obj.get("message", {})
                if not isinstance(message, dict):
                    continue

                role = message.get("role", msg_type)
                content = message.get("content", [])
                timestamp = obj.get("timestamp", "")

                text_parts = []
                if isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        btype = block.get("type", "")
                        if btype == "text":
                            t = block.get("text", "").strip()
                            if t:
                                text_parts.append(t)
                        elif btype == "tool_use":
                            name = block.get("name", "")
                            inp = block.get("input", {})
                            if name and inp:
                                summary = f"[tool: {name}]"
                                if isinstance(inp, dict):
                                    for k in ("command", "file_path", "pattern", "url", "text", "query"):
                                        if k in inp:
                                            val = str(inp[k])[:120]
                                            summary = f"[tool: {name} {k}={val}]"
                                            break
                                text_parts.append(summary)
                        elif btype == "tool_result":
                            pass  # skip tool results — noise
                elif isinstance(content, str):
                    if content.strip():
                        text_parts.append(content.strip())

                text = "\n".join(text_parts).strip()
                if text:
                    turns.append((timestamp, role, text))
    except Exception as e:
        pass

    return turns


def session_date(jsonl_path):
    """Get the date of the first message in the session."""
    try:
        with open(jsonl_path) as f:
            for line in f:
                obj = json.loads(line.strip())
                ts = obj.get("timestamp", "")
                if ts:
                    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    return dt.strftime("%Y-%m-%d"), dt
    except Exception:
        pass
    mtime = os.path.getmtime(jsonl_path)
    dt = datetime.fromtimestamp(mtime, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d"), dt


def write_index(session_id, date_str, turns, jsonl_path):
    """Write a markdown summary of the session."""
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    out_path = INDEX_DIR / f"{date_str}-{session_id[:8]}.md"

    lines = [
        f"---",
        f"session_id: {session_id}",
        f"date: {date_str}",
        f"turns: {len(turns)}",
        f"source: {jsonl_path.name}",
        f"---",
        f"",
        f"# Conversation — {date_str} ({session_id[:8]})",
        f"",
    ]

    for ts, role, text in turns:
        label = "Josh" if role == "user" else "Max"
        # Truncate very long turns (tool outputs, etc.)
        if len(text) > 2000:
            text = text[:2000] + "\n[...truncated]"
        lines.append(f"## {label}")
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                lines.append(f"*{dt.strftime('%H:%M')}*")
            except Exception:
                pass
        lines.append("")
        lines.append(text)
        lines.append("")

    out_path.write_text("\n".join(lines))
    return out_path


def main():
    reindex_all = "--all" in sys.argv
    show_status = "--status" in sys.argv

    state = load_state()

    jsonl_files = sorted(JSONL_DIR.glob("*.jsonl"))
    if show_status:
        print(f"JSONL sessions: {len(jsonl_files)}")
        print(f"Indexed: {len(state['indexed'])}")
        print(f"Pending: {len(jsonl_files) - len(state['indexed'])}")
        return

    new_count = 0
    skip_count = 0

    for jsonl_path in jsonl_files:
        session_id = jsonl_path.stem
        file_mtime = str(int(os.path.getmtime(jsonl_path)))

        # Skip if already indexed and file hasn't changed
        if not reindex_all and session_id in state["indexed"]:
            if state["indexed"][session_id].get("mtime") == file_mtime:
                skip_count += 1
                continue

        turns = extract_messages(jsonl_path)
        if len(turns) < MIN_MESSAGES:
            skip_count += 1
            continue

        date_str, _ = session_date(jsonl_path)
        out_path = write_index(session_id, date_str, turns, jsonl_path)

        state["indexed"][session_id] = {
            "mtime": file_mtime,
            "date": date_str,
            "turns": len(turns),
            "output": str(out_path),
        }
        new_count += 1
        print(f"Indexed: {date_str} {session_id[:8]} ({len(turns)} turns)")

    save_state(state)
    print(f"\nDone: {new_count} new, {skip_count} skipped.")
    print(f"Output: {INDEX_DIR}")


if __name__ == "__main__":
    main()
