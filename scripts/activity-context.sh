#!/usr/bin/env bash
# activity-context.sh — Generate a compact recent-activity summary for session startup.
#
# Reads the last N hours of session logs and emits a plain-text block
# suitable for injection into --append-system-prompt at startup.
#
# Usage: activity-context.sh [hours]   (default: 48)
# Output: plain text to stdout; empty if no recent entries.

set -euo pipefail

HOURS="${1:-48}"
LOG_DIR="/home/josh/.max/state/session-logs"
CUTOFF=$(TZ=America/Chicago date -d "${HOURS} hours ago" +%s 2>/dev/null || date -v-${HOURS}H +%s)

# Collect entries from today + yesterday (covers any 48h window)
TODAY=$(TZ=America/Chicago date +%Y-%m-%d)
YESTERDAY=$(TZ=America/Chicago date -d yesterday +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

ENTRIES=""
for f in "${LOG_DIR}/${YESTERDAY}.jsonl" "${LOG_DIR}/${TODAY}.jsonl"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        ts=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('ts',0))" 2>/dev/null || echo 0)
        if [ "$ts" -ge "$CUTOFF" ] 2>/dev/null; then
            ENTRIES="${ENTRIES}${line}
"
        fi
    done < "$f"
done

[ -z "$ENTRIES" ] && exit 0

echo "=== RECENT ACTIVITY (last ${HOURS}h) ==="
echo "$ENTRIES" | python3 -c "
import sys, json
lines = [l for l in sys.stdin.read().strip().split('\n') if l.strip()]
for line in lines:
    try:
        e = json.loads(line)
        ts_h = e.get('ts_human', '')
        typ  = e.get('type', '')
        summ = e.get('summary', '')
        print(f'[{ts_h}] {typ}: {summ}')
    except:
        pass
"
echo "=== END RECENT ACTIVITY ==="
