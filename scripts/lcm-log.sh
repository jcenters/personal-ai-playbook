#!/usr/bin/env bash
# lcm-log.sh — Append a JSON event to the daily session log.
#
# Usage: lcm-log.sh <event_type> <summary>
#
# Environment:
#   AGENT_RUNTIME_DIR  — base runtime directory (default: ~/.assistant)
#   TZ                 — timezone for date calculation (default: UTC)
#
# Output: appends one JSON line to:
#   $AGENT_RUNTIME_DIR/state/session-logs/YYYY-MM-DD.jsonl

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────
if [ $# -lt 2 ]; then
  echo "Usage: $(basename "$0") <event_type> <summary>" >&2
  echo "  Example: $(basename "$0") conversation \"Helped draft three emails\"" >&2
  echo "  Example: $(basename "$0") task_complete \"Grocery list created\"" >&2
  exit 1
fi

EVENT_TYPE="$1"
SUMMARY="$2"

# ── Environment ───────────────────────────────────────────────────────────
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$HOME/.assistant}"
LOG_DIR="$AGENT_RUNTIME_DIR/state/session-logs"

# Use TZ from environment, fall back to UTC
export TZ="${TZ:-UTC}"

# ── Ensure log directory exists ───────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── Build the log entry ───────────────────────────────────────────────────
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_FILE="$LOG_DIR/$DATE.jsonl"

# Escape the summary string for JSON
# Handles: backslashes, double quotes, newlines, tabs
escape_json() {
  local str="$1"
  # Replace backslash first, then other characters
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  str="${str//$'\n'/\\n}"
  str="${str//$'\t'/\\t}"
  str="${str//$'\r'/\\r}"
  echo "$str"
}

ESCAPED_SUMMARY=$(escape_json "$SUMMARY")
ESCAPED_EVENT_TYPE=$(escape_json "$EVENT_TYPE")

# Build JSON entry
JSON_ENTRY="{\"ts\":\"$TIMESTAMP\",\"type\":\"$ESCAPED_EVENT_TYPE\",\"summary\":\"$ESCAPED_SUMMARY\"}"

# ── Append to log file ────────────────────────────────────────────────────
echo "$JSON_ENTRY" >> "$LOG_FILE"

# ── Optional: print confirmation to stderr for debugging ─────────────────
if [ "${LCM_VERBOSE:-0}" = "1" ]; then
  echo "[lcm-log] Logged to $LOG_FILE: $JSON_ENTRY" >&2
fi
