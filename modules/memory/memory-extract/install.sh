#!/usr/bin/env bash
# Module: memory/memory-extract
# Nightly script that analyzes recent conversation summaries and automatically
# writes new memory files (user facts, feedback, project context, references).
#
# Unlike user-model (which corrects existing beliefs), this module ADDS new
# facts that aren't in memory yet. Complementary, not competing.
#
# Prerequisites:
#   - memory/conversation-index installed (needs conversation-index/ dir)
#   - memory/lcm installed (memory dir must exist)
#   - claude CLI available and authenticated
#   - TELEGRAM_BOT_TOKEN in .env

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$DEPLOY_BASE/.$AGENT_NAME}"
CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects/$(basename "$HOME")}"
MEMORY_DIR="${MEMORY_DIR:-$CLAUDE_PROJECTS_DIR/memory}"
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
echo "  Memory Extract — Nightly Fact Addition"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Directories ───────────────────────────────────────────────────
print_step "Creating directories"
for dir in "$SCRIPTS_DIR" "$LOGS_DIR" "$STATE_DIR"; do
  mkdir -p "$dir" && print_ok "Ready: $dir"
done

# ── Step 2: Install scripts ───────────────────────────────────────────────
print_step "Installing scripts"

for script in memory-extract.py memory-apply.py; do
  SRC="$REPO_DIR/scripts/$script"
  DEST="$SCRIPTS_DIR/$script"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DEST" && chmod 755 "$DEST" && print_ok "Installed: $DEST"
  else
    print_warn "Source not found: $SRC"
    exit 1
  fi
done

# ── Step 3: Verify prerequisites ─────────────────────────────────────────
print_step "Checking prerequisites"

if [ ! -d "$AGENT_RUNTIME_DIR/conversation-index" ]; then
  print_warn "conversation-index/ not found — install memory/conversation-index first"
  exit 1
fi
print_ok "conversation-index/ found"

if ! command -v claude &>/dev/null; then
  print_warn "claude CLI not found"
  exit 1
fi
print_ok "claude CLI found"

# ── Step 4: Schedule cron ─────────────────────────────────────────────────
print_step "Installing cron job"

# NOTE: If using memory/nightly-pipeline module, skip this step — that module
# chains all memory scripts together in one cron entry.

CRON_TIME="35 9"  # 4:35 AM CT default
if command -v python3 &>/dev/null; then
  UTC_TIME=$(python3 -c "
import datetime, zoneinfo
try:
    tz = zoneinfo.ZoneInfo('$USER_TZ')
    local_dt = datetime.datetime(2000, 6, 1, 4, 35, tzinfo=tz)
    utc_dt = local_dt.astimezone(zoneinfo.ZoneInfo('UTC'))
    print(f'{utc_dt.minute} {utc_dt.hour}')
except Exception:
    print('35 9')
" 2>/dev/null || echo "35 9")
  CRON_TIME="$UTC_TIME"
fi

DEST_EXTRACT="$SCRIPTS_DIR/memory-extract.py"
EXTRACT_LOG="$LOGS_DIR/memory-extract.log"
CRON_JOB="$CRON_TIME * * * NIGHTLY_MODE=1 /usr/bin/python3 $DEST_EXTRACT >> $EXTRACT_LOG 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -qF "$DEST_EXTRACT"; then
  print_ok "Cron already installed (or handled by nightly-pipeline module)"
else
  TMPFILE=$(mktemp)
  { echo "$EXISTING_CRON"; echo "# $AGENT_NAME memory-extract"; echo "$CRON_JOB"; } > "$TMPFILE"
  crontab "$TMPFILE" && rm -f "$TMPFILE"
  print_ok "Cron installed ($CRON_TIME UTC = 4:35 AM $USER_TZ)"
  print_info "Tip: use memory/nightly-pipeline to chain all memory scripts together instead"
fi

# ── Step 5: Usage ─────────────────────────────────────────────────────────
print_step "Usage reference"
echo ""
echo "  Run manually:      python3 $SCRIPTS_DIR/memory-extract.py"
echo "  Review proposals:  python3 $SCRIPTS_DIR/memory-apply.py --review"
echo "  Apply proposals:   python3 $SCRIPTS_DIR/memory-apply.py --apply"
echo "  Undo:              git -C $MEMORY_DIR revert HEAD"
echo ""
echo "========================================"
echo "  Memory Extract module setup complete."
echo "========================================"
