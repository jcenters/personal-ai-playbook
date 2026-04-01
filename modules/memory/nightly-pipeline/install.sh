#!/usr/bin/env bash
# Module: memory/nightly-pipeline
# Wires all four memory pipeline scripts into a single sequenced cron entry.
# Run this INSTEAD OF installing individual cron jobs from each memory module.
#
# Pipeline order (all at 4:30 AM local time):
#   1. conversation-index  — convert JSONL sessions to searchable markdown
#   2. memory-extract      — add new facts from conversations
#   3. skill-scout         — generate new skill files from recurring patterns
#   4. user-model-update   — correct/retire outdated beliefs
#
# All scripts run with NIGHTLY_MODE=1 so they buffer Telegram notifications
# to ~/.{agent}/state/nightly-digest.txt instead of pinging at 4 AM.
# The morning briefing reads and clears this file.
#
# Prerequisites:
#   All four memory modules must be installed first:
#     memory/lcm
#     memory/conversation-index
#     memory/memory-extract
#     memory/user-model
#     skills/skill-scout

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$DEPLOY_BASE/.$AGENT_NAME}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
USER_TZ="${USER_TZ:-UTC}"

SCRIPTS_DIR="$AGENT_RUNTIME_DIR/scripts"
LOGS_DIR="$AGENT_RUNTIME_DIR/logs"
STATE_DIR="$AGENT_RUNTIME_DIR/state"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  Nightly Pipeline — Memory + Skills"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Verify all scripts exist ─────────────────────────────────────
print_step "Verifying pipeline scripts"

REQUIRED_SCRIPTS=(
  "conversation-index.py"
  "memory-extract.py"
  "skill-scout.py"
  "user-model-update.py"
)

ALL_FOUND=true
for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [ -f "$SCRIPTS_DIR/$script" ]; then
    print_ok "$script"
  else
    print_warn "Missing: $SCRIPTS_DIR/$script"
    print_info "Install the corresponding module first"
    ALL_FOUND=false
  fi
done

if [ "$ALL_FOUND" = false ]; then
  echo ""
  echo "Install missing modules first, then re-run this installer."
  echo "Required modules:"
  echo "  memory/conversation-index"
  echo "  memory/memory-extract"
  echo "  skills/skill-scout"
  echo "  memory/user-model"
  exit 1
fi

# ── Step 2: Remove any individual cron entries for these scripts ──────────
print_step "Cleaning up individual cron entries"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
CLEANED_CRON=$(echo "$EXISTING_CRON" | grep -v "conversation-index.py\|memory-extract.py\|skill-scout.py\|user-model-update.py" || true)

if [ "$EXISTING_CRON" != "$CLEANED_CRON" ]; then
  TMPFILE=$(mktemp)
  echo "$CLEANED_CRON" > "$TMPFILE"
  crontab "$TMPFILE"
  rm -f "$TMPFILE"
  print_ok "Removed individual cron entries for pipeline scripts"
else
  print_ok "No individual entries to clean up"
fi

# ── Step 3: Calculate cron time ───────────────────────────────────────────
CRON_TIME="30 9"  # 4:30 AM CT (CDT, UTC-5) default
if command -v python3 &>/dev/null; then
  UTC_TIME=$(python3 -c "
import datetime, zoneinfo
try:
    tz = zoneinfo.ZoneInfo('$USER_TZ')
    local_dt = datetime.datetime(2000, 6, 1, 4, 30, tzinfo=tz)
    utc_dt = local_dt.astimezone(zoneinfo.ZoneInfo('UTC'))
    print(f'{utc_dt.minute} {utc_dt.hour}')
except Exception:
    print('30 9')
" 2>/dev/null || echo "30 9")
  CRON_TIME="$UTC_TIME"
fi

# ── Step 4: Install single chained cron entry ────────────────────────────
print_step "Installing pipeline cron job"

CONV_INDEX="$SCRIPTS_DIR/conversation-index.py"
MEM_EXTRACT="$SCRIPTS_DIR/memory-extract.py"
SKILL_SCOUT="$SCRIPTS_DIR/skill-scout.py"
USER_MODEL="$SCRIPTS_DIR/user-model-update.py"

CONV_LOG="$LOGS_DIR/conv-index.log"
MEM_LOG="$LOGS_DIR/memory-extract.log"
SKILL_LOG="$LOGS_DIR/skill-scout.log"
USER_LOG="$LOGS_DIR/user-model-update.log"

CRON_JOB="$CRON_TIME * * * NIGHTLY_MODE=1 /usr/bin/python3 $CONV_INDEX >> $CONV_LOG 2>&1 && NIGHTLY_MODE=1 /usr/bin/python3 $MEM_EXTRACT >> $MEM_LOG 2>&1 && NIGHTLY_MODE=1 /usr/bin/python3 $SKILL_SCOUT >> $SKILL_LOG 2>&1 && NIGHTLY_MODE=1 /usr/bin/python3 $USER_MODEL >> $USER_LOG 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
TMPFILE=$(mktemp)
{
  echo "$EXISTING_CRON"
  echo "# $AGENT_NAME nightly memory + skills pipeline (4:30 AM $USER_TZ)"
  echo "$CRON_JOB"
} > "$TMPFILE"
crontab "$TMPFILE"
rm -f "$TMPFILE"
print_ok "Pipeline cron installed ($CRON_TIME UTC = 4:30 AM $USER_TZ)"

# ── Step 5: Create digest file ────────────────────────────────────────────
print_step "Setting up nightly digest buffer"

DIGEST_FILE="$STATE_DIR/nightly-digest.txt"
touch "$DIGEST_FILE"
print_ok "Digest file: $DIGEST_FILE"
print_info "Morning briefing should read and clear this file at startup"
print_info "Add to briefing script: NIGHTLY_DIGEST=\$(cat $DIGEST_FILE); > $DIGEST_FILE"

# ── Step 6: Usage ─────────────────────────────────────────────────────────
print_step "Usage reference"
echo ""
echo "  The full pipeline runs nightly at 4:30 AM $USER_TZ."
echo "  Results are buffered — no Telegram pings until morning briefing."
echo ""
echo "  Run pipeline manually:"
echo "    NIGHTLY_MODE=1 python3 $CONV_INDEX && \\"
echo "    NIGHTLY_MODE=1 python3 $MEM_EXTRACT && \\"
echo "    NIGHTLY_MODE=1 python3 $SKILL_SCOUT && \\"
echo "    NIGHTLY_MODE=1 python3 $USER_MODEL"
echo ""
echo "  Check digest (pending morning notifications):"
echo "    cat $DIGEST_FILE"
echo ""
echo "  Undo any nightly changes:"
echo "    git -C ~/.claude/skills revert HEAD                  # skills"
echo "    git -C \$MEMORY_DIR revert HEAD                       # memory"
echo ""
echo "========================================"
echo "  Nightly Pipeline setup complete."
echo "========================================"
