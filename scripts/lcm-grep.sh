#!/usr/bin/env bash
# lcm-grep.sh — Search session logs and memory files for a query term.
#
# Usage: lcm-grep.sh <query> [--logs-only | --memory-only] [--days N]
#
# Environment:
#   AGENT_RUNTIME_DIR  — base runtime directory (default: ~/.assistant)
#   CLAUDE_MEMORY_DIR  — memory files directory
#                        (default: ~/.claude/projects/<username>/memory/)
#
# Examples:
#   lcm-grep.sh "grocery list"
#   lcm-grep.sh "email draft" --logs-only
#   lcm-grep.sh "dentist" --days 14

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <query> [--logs-only | --memory-only] [--days N]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --logs-only    Search only session JSONL logs" >&2
  echo "  --memory-only  Search only compiled memory .md files" >&2
  echo "  --days N       Limit log search to last N days (default: 30)" >&2
  exit 1
fi

QUERY="$1"
shift

SEARCH_LOGS=true
SEARCH_MEMORY=true
DAYS=30

while [ $# -gt 0 ]; do
  case "$1" in
    --logs-only)
      SEARCH_MEMORY=false
      shift
      ;;
    --memory-only)
      SEARCH_LOGS=false
      shift
      ;;
    --days)
      DAYS="${2:?--days requires a number}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ── Environment ───────────────────────────────────────────────────────────
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$HOME/.assistant}"
DEFAULT_MEMORY_DIR="$HOME/.claude/projects/$(basename "$HOME")/memory"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$DEFAULT_MEMORY_DIR}"
LOG_DIR="$AGENT_RUNTIME_DIR/state/session-logs"
export TZ="${TZ:-UTC}"

MATCH_COUNT=0

# ── Search session logs ───────────────────────────────────────────────────
if [ "$SEARCH_LOGS" = true ] && [ -d "$LOG_DIR" ]; then
  echo ""
  echo "Session logs matching: \"$QUERY\""
  echo "$(printf '%*s' 50 '' | tr ' ' '-')"

  # Calculate cutoff date
  CUTOFF_DATE=$(date -d "$DAYS days ago" +%Y-%m-%d 2>/dev/null || \
                date -v "-${DAYS}d" +%Y-%m-%d 2>/dev/null || \
                echo "0000-00-00")

  LOG_MATCH_COUNT=0
  while IFS= read -r -d '' LOG_FILE; do
    LOG_DATE=$(basename "$LOG_FILE" .jsonl)

    # Skip files older than cutoff
    if [[ "$LOG_DATE" < "$CUTOFF_DATE" ]]; then
      continue
    fi

    while IFS= read -r line; do
      if echo "$line" | grep -qi "$QUERY" 2>/dev/null; then
        # Pretty-print the matching entry
        if command -v python3 &>/dev/null; then
          python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    ts = d.get('ts', '?')
    etype = d.get('type', '?')
    summary = d.get('summary', '?')
    print(f'  [{sys.argv[2]}] {ts}  {etype}')
    print(f'    {summary}')
except:
    print(f'  [{sys.argv[2]}] {sys.argv[1]}')
" "$line" "$LOG_DATE" 2>/dev/null || echo "  [$LOG_DATE] $line"
        else
          echo "  [$LOG_DATE] $line"
        fi
        LOG_MATCH_COUNT=$((LOG_MATCH_COUNT + 1))
        MATCH_COUNT=$((MATCH_COUNT + 1))
      fi
    done < "$LOG_FILE"
  done < <(find "$LOG_DIR" -name "*.jsonl" -print0 | sort -z)

  if [ "$LOG_MATCH_COUNT" -eq 0 ]; then
    echo "  No matches in session logs (last $DAYS days)"
  else
    echo ""
    echo "  $LOG_MATCH_COUNT match(es) in session logs"
  fi
fi

# ── Search memory files ───────────────────────────────────────────────────
if [ "$SEARCH_MEMORY" = true ] && [ -d "$CLAUDE_MEMORY_DIR" ]; then
  echo ""
  echo "Memory files matching: \"$QUERY\""
  echo "$(printf '%*s' 50 '' | tr ' ' '-')"

  MEMORY_MATCH_COUNT=0
  while IFS= read -r -d '' MEM_FILE; do
    FILENAME=$(basename "$MEM_FILE")
    MATCHES=$(grep -ni "$QUERY" "$MEM_FILE" 2>/dev/null || true)

    if [ -n "$MATCHES" ]; then
      echo ""
      echo "  File: $FILENAME"
      while IFS= read -r match_line; do
        echo "    $match_line"
      done <<< "$MATCHES"
      MEMORY_MATCH_COUNT=$((MEMORY_MATCH_COUNT + 1))
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done < <(find "$CLAUDE_MEMORY_DIR" -name "*.md" -print0 | sort -z)

  if [ "$MEMORY_MATCH_COUNT" -eq 0 ]; then
    echo "  No matches in memory files"
  else
    echo ""
    echo "  $MEMORY_MATCH_COUNT file(s) with matches in memory"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "$(printf '%*s' 50 '' | tr ' ' '-')"
if [ "$MATCH_COUNT" -eq 0 ]; then
  echo "No results for: \"$QUERY\""
else
  echo "Total matches: $MATCH_COUNT  |  Query: \"$QUERY\""
fi
echo ""
