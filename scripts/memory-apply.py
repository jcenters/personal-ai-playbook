#!/usr/bin/env python3
"""
memory-apply.py — Review and apply proposed memory additions.

Usage:
    python3 memory-apply.py --review     # print all pending proposals
    python3 memory-apply.py --apply      # apply all proposals to memory files
    python3 memory-apply.py --clear      # discard all proposals
    python3 memory-apply.py --apply N    # apply proposal number N only
"""

import json
import sys
from pathlib import Path
from datetime import datetime

MEMORY_DIR = Path.home() / ".claude/projects/-home-josh/memory"
PROPOSALS_FILE = Path.home() / ".max/state/memory-proposals.json"


def load_proposals():
    if not PROPOSALS_FILE.exists():
        return []
    return json.loads(PROPOSALS_FILE.read_text())


def save_proposals(proposals):
    PROPOSALS_FILE.write_text(json.dumps(proposals, indent=2))


def apply_proposal(proposal):
    """Write or update a memory file and update MEMORY.md index."""
    memory_dir = MEMORY_DIR
    memory_index = memory_dir / "MEMORY.md"

    filename = proposal["filename"]
    if not filename.endswith(".md"):
        filename += ".md"

    target = proposal.get("update_existing")
    if target:
        if not target.endswith(".md"):
            target += ".md"
        out_path = memory_dir / target
    else:
        out_path = memory_dir / filename

    # Write memory file
    content = f"""---
name: {proposal['name']}
description: {proposal['description']}
type: {proposal['type']}
---

{proposal['body']}
"""
    out_path.write_text(content)
    print(f"  Written: {out_path.name}")

    # Update MEMORY.md if this is a new file (not an update)
    if not target and memory_index.exists():
        index_text = memory_index.read_text()
        entry = f"- [{proposal['name']}]({filename}) — {proposal['description']}"

        # Check if already in index
        if filename not in index_text:
            # Append under appropriate section header
            type_header_map = {
                "user": "## User",
                "feedback": "## Feedback",
                "project": "## Project",
                "reference": "## Reference",
            }
            header = type_header_map.get(proposal["type"], "## User")
            if header in index_text:
                # Insert after the header and any existing entries in that section
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
                    print(f"  Added to MEMORY.md under {header}")
            else:
                # Append section and entry
                with open(memory_index, "a") as f:
                    f.write(f"\n{header}\n{entry}\n")
                print(f"  Added new section {header} to MEMORY.md")


def main():
    proposals = load_proposals()

    if "--clear" in sys.argv:
        save_proposals([])
        print(f"Cleared {len(proposals)} proposals.")
        return

    if "--review" in sys.argv or len(sys.argv) == 1:
        if not proposals:
            print("No pending proposals.")
            return
        for i, p in enumerate(proposals):
            print(f"\n{'='*60}")
            print(f"[{i}] {p['type'].upper()} — {p['name']}")
            print(f"File: {p.get('update_existing') or p['filename']}")
            print(f"Source: {p.get('source_date', '?')} {p.get('source_session', '?')[:8]}")
            print(f"Description: {p['description']}")
            print(f"\nBody preview:\n{p['body'][:400]}")
        print(f"\n{len(proposals)} total proposals.")
        print("Apply with: python3 memory-apply.py --apply")
        return

    if "--apply" in sys.argv:
        idx = sys.argv.index("--apply")
        apply_specific = None
        if idx + 1 < len(sys.argv):
            try:
                apply_specific = int(sys.argv[idx + 1])
            except ValueError:
                pass

        if not proposals:
            print("No pending proposals.")
            return

        if apply_specific is not None:
            if apply_specific >= len(proposals):
                print(f"Invalid proposal number {apply_specific}")
                return
            apply_proposal(proposals[apply_specific])
            proposals.pop(apply_specific)
            save_proposals(proposals)
            print("Applied.")
        else:
            applied = 0
            for p in proposals:
                try:
                    apply_proposal(p)
                    applied += 1
                except Exception as e:
                    print(f"  Error applying '{p['name']}': {e}")
            save_proposals([])
            print(f"\nApplied {applied} proposals. Memory updated.")


if __name__ == "__main__":
    main()
