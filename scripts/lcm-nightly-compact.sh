#!/usr/bin/env bash
# lcm-nightly-compact.sh — Compact yesterday's session log into a memory file.
#
# Reads yesterday's JSONL session log, uses `claude -p` to generate a
# concise bullet-point summary, and writes it as a memory file for future sessions.
#
# Environment:
#   AGENT_RUNTIME_DIR   — base runtime directory (default: ~/.assistant)
#   CLAUDE_MEMORY_DIR   — memory files directory
#                         (default: ~/.claude/projects/<username>/memory/)
#   TZ                  — timezone for date calculation (default: UTC)
#
# Skips if fewer than 3 log entries are present for the day.
# Skips if a memory file for yesterday already exists.

set -euo pipefail

# ── Environment ───────────────────────────────────────────────────────────
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$HOME/.assistant}"
DEFAULT_MEMORY_DIR="$HOME/.claude/projects/$(basename "$HOME")/memory"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$DEFAULT_MEMORY_DIR}"
export TZ="${TZ:-UTC}"

LOG_DIR="$AGENT_RUNTIME_DIR/state/session-logs"
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
LOG_FILE="$LOG_DIR/$YESTERDAY.jsonl"
MEMORY_OUTPUT="$CLAUDE_MEMORY_DIR/session-${YESTERDAY}.md"

# ── Logging ───────────────────────────────────────────────────────────────
log() {
  echo "[lcm-compact $(date -u +%H:%M:%SZ)] $*"
}

log "Starting nightly compaction for $YESTERDAY"

# ── Guard: log file must exist ────────────────────────────────────────────
if [ ! -f "$LOG_FILE" ]; then
  log "No session log found for $YESTERDAY ($LOG_FILE) — skipping"
  exit 0
fi

# ── Guard: skip if memory file already exists ─────────────────────────────
if [ -f "$MEMORY_OUTPUT" ]; then
  log "Memory file already exists: $MEMORY_OUTPUT — skipping"
  exit 0
fi

# ── Guard: require minimum entries ───────────────────────────────────────
ENTRY_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
if [ "$ENTRY_COUNT" -lt 3 ]; then
  log "Only $ENTRY_COUNT entries in log (minimum: 3) — skipping compaction"
  exit 0
fi

log "Processing $ENTRY_COUNT log entries from $YESTERDAY"

# ── Ensure memory directory exists ───────────────────────────────────────
mkdir -p "$CLAUDE_MEMORY_DIR"

# ── Build log text for Claude ─────────────────────────────────────────────
LOG_TEXT=""
if command -v python3 &>/dev/null; then
  LOG_TEXT=$(python3 - "$LOG_FILE" << 'PYEOF'
import json, sys

lines = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
            ts = d.get('ts', '')
            etype = d.get('type', 'unknown')
            summary = d.get('summary', '')
            lines.append(f"[{ts}] {etype}: {summary}")
        except json.JSONDecodeError:
            lines.append(line)

print('\n'.join(lines))
PYEOF
)
else
  LOG_TEXT=$(cat "$LOG_FILE")
fi

if [ -z "$LOG_TEXT" ]; then
  log "Log text is empty after parsing — skipping"
  exit 0
fi

# ── Check for claude CLI ──────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  log "claude CLI not found — cannot compact. Install Claude Code to enable LCM."
  exit 1
fi

# ── Generate summary via claude -p ────────────────────────────────────────
PROMPT="Below are the session log entries for $YESTERDAY from an AI assistant.

Produce a concise memory summary of approximately 200 words in bullet-point format.
The summary will be loaded as context in future sessions.

Include:
- Key topics discussed or tasks completed
- Decisions made or conclusions reached
- Important details or preferences the user expressed
- Any open loops or pending items

Do not include: timestamps, filler language, or restated instructions.
Write in third person (e.g., 'User asked about...' or 'Completed draft of...').

Session log:
$LOG_TEXT"

log "Generating summary via claude -p..."

SUMMARY=$(echo "$PROMPT" | claude -p 2>/dev/null)

if [ -z "$SUMMARY" ]; then
  log "claude -p returned empty output — skipping"
  exit 1
fi

# ── Write memory file ─────────────────────────────────────────────────────
cat > "$MEMORY_OUTPUT" << EOF
# Session Memory: $YESTERDAY

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source: $LOG_FILE ($ENTRY_COUNT events)

$SUMMARY
EOF

log "Memory file written: $MEMORY_OUTPUT"

# ── Rotate old memory files (keep last 30 days) ───────────────────────────
MEMORY_FILE_COUNT=$(find "$CLAUDE_MEMORY_DIR" -name "session-*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$MEMORY_FILE_COUNT" -gt 30 ]; then
  log "Rotating old session memory files (keeping 30 most recent)"
  find "$CLAUDE_MEMORY_DIR" -name "session-*.md" | sort | head -n -30 | while read -r old_file; do
    rm -f "$old_file"
    log "Removed old memory file: $old_file"
  done
fi

log "Compaction complete"
