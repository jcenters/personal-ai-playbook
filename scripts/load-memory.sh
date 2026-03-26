#!/usr/bin/env bash
# load-memory.sh — Output all memory files for use with --append-system-prompt.
#
# Usage: claude --append-system-prompt "$(load-memory.sh)" ...
#
# Environment:
#   CLAUDE_MEMORY_DIR  — directory containing .md memory files
#                        (default: ~/.claude/projects/<username>/memory/)
#
# Outputs: concatenated content of all .md files in CLAUDE_MEMORY_DIR,
# with section headers identifying each file.

set -euo pipefail

# ── Resolve memory directory ──────────────────────────────────────────────
DEFAULT_MEMORY_DIR="$HOME/.claude/projects/$(basename "$HOME")/memory"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$DEFAULT_MEMORY_DIR}"

# ── Check if directory exists ─────────────────────────────────────────────
if [ ! -d "$CLAUDE_MEMORY_DIR" ]; then
  # Silently exit — no memory to load is a valid state
  exit 0
fi

# ── Collect memory files ──────────────────────────────────────────────────
# Sort by name for deterministic ordering
mapfile -t MEMORY_FILES < <(find "$CLAUDE_MEMORY_DIR" -maxdepth 1 -name "*.md" | sort)

if [ ${#MEMORY_FILES[@]} -eq 0 ]; then
  exit 0
fi

# ── Output memory contents ────────────────────────────────────────────────
echo "# Assistant Memory"
echo ""
echo "The following is your memory from prior sessions. Use it to maintain"
echo "continuity without asking the user to re-explain past context."
echo ""
echo "---"

for FILE in "${MEMORY_FILES[@]}"; do
  if [ -f "$FILE" ] && [ -s "$FILE" ]; then
    FILENAME=$(basename "$FILE")
    echo ""
    echo "## Memory file: $FILENAME"
    echo ""
    cat "$FILE"
    echo ""
    echo "---"
  fi
done

# ── Append today's session log if it exists ───────────────────────────────
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$HOME/.assistant}"
LOG_DIR="$AGENT_RUNTIME_DIR/state/session-logs"
TODAY=$(date +%Y-%m-%d)
TODAY_LOG="$LOG_DIR/$TODAY.jsonl"

if [ -f "$TODAY_LOG" ] && [ -s "$TODAY_LOG" ]; then
  LINE_COUNT=$(wc -l < "$TODAY_LOG" | tr -d ' ')
  echo ""
  echo "## Today's session log ($TODAY — $LINE_COUNT events)"
  echo ""
  # Pretty-print each JSON line if python3 is available, otherwise raw
  if command -v python3 &>/dev/null; then
    while IFS= read -r line; do
      python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(f\"  [{d.get('ts','?')}] {d.get('type','?')}: {d.get('summary','?')}\")
except:
    print(f'  {sys.argv[1]}')
" "$line" 2>/dev/null || echo "  $line"
    done < "$TODAY_LOG"
  else
    # Raw output if no python3
    while IFS= read -r line; do
      echo "  $line"
    done < "$TODAY_LOG"
  fi
  echo ""
  echo "---"
fi
