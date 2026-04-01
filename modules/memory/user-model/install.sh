#!/usr/bin/env bash
# Module: memory/user-model
# Sets up dialectic user modeling — nightly review of existing user beliefs
# against recent conversation evidence, with active correction and retirement.
#
# This is distinct from memory/conversation-index (which appends new facts).
# This module CORRECTS and RETIRES existing beliefs that are outdated or wrong.
#
# Prerequisites:
#   - memory/conversation-index module installed (needs conversation-index/)
#   - claude CLI available and authenticated
#   - Memory directory initialized as git repo (for undo support)
#   - TELEGRAM_BOT_TOKEN in .env (for change notifications)

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_DIR="$DEPLOY_BASE/.$AGENT_NAME"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$AGENT_DIR}"
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
echo "  User Model — Dialectic Belief Updating"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Create directories ────────────────────────────────────────────
print_step "Creating directories"
for dir in "$SCRIPTS_DIR" "$LOGS_DIR" "$STATE_DIR"; do
  mkdir -p "$dir"
  print_ok "Ready: $dir"
done

# ── Step 2: Install script ────────────────────────────────────────────────
print_step "Installing user-model-update.py"

SRC="$REPO_DIR/scripts/user-model-update.py"
DEST="$SCRIPTS_DIR/user-model-update.py"
if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST"
  chmod 755 "$DEST"
  print_ok "Installed: $DEST"
else
  print_warn "Source not found: $SRC"
  exit 1
fi

# ── Step 3: Verify prerequisites ─────────────────────────────────────────
print_step "Checking prerequisites"

CONV_INDEX_DIR="$AGENT_RUNTIME_DIR/conversation-index"
if [ ! -d "$CONV_INDEX_DIR" ]; then
  print_warn "conversation-index/ not found at $CONV_INDEX_DIR"
  print_info "Install memory/conversation-index module first"
  exit 1
fi
print_ok "conversation-index/ found"

if [ ! -d "$MEMORY_DIR/.git" ]; then
  print_warn "Memory directory is not a git repo — initializing for undo support"
  git -C "$MEMORY_DIR" init && git -C "$MEMORY_DIR" add . && git -C "$MEMORY_DIR" commit -m "Initial snapshot before user-model module"
  print_ok "Memory directory initialized as git repo"
else
  print_ok "Memory directory is git-backed"
fi

if ! command -v claude &>/dev/null; then
  print_warn "claude CLI not found — user-model-update requires it"
  exit 1
fi
print_ok "claude CLI found"

# ── Step 4: Schedule cron ─────────────────────────────────────────────────
print_step "Installing cron job"

# 4:45 AM local time (after skill-scout at 4:30)
CRON_TIME="45 9"
if command -v python3 &>/dev/null; then
  UTC_TIME=$(python3 -c "
import datetime, zoneinfo
try:
    tz = zoneinfo.ZoneInfo('$USER_TZ')
    local_dt = datetime.datetime(2000, 6, 1, 4, 45, tzinfo=tz)
    utc_dt = local_dt.astimezone(zoneinfo.ZoneInfo('UTC'))
    print(f'{utc_dt.minute} {utc_dt.hour}')
except Exception:
    print('45 9')
" 2>/dev/null || echo "45 9")
  CRON_TIME="$UTC_TIME"
fi

USER_MODEL_LOG="$LOGS_DIR/user-model-update.log"
CRON_JOB="$CRON_TIME * * * NIGHTLY_MODE=1 /usr/bin/python3 $DEST >> $USER_MODEL_LOG 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -qF "$DEST"; then
  print_ok "Cron job already installed"
else
  TMPFILE=$(mktemp)
  {
    echo "$EXISTING_CRON"
    echo "# $AGENT_NAME user model nightly update"
    echo "$CRON_JOB"
  } > "$TMPFILE"
  crontab "$TMPFILE"
  rm -f "$TMPFILE"
  print_ok "Cron job installed ($CRON_TIME UTC = 4:45 AM $USER_TZ)"
fi

# ── Step 5: Dry run ───────────────────────────────────────────────────────
print_step "Running dry-run verification"
python3 "$DEST" --dry-run 2>&1 | tail -5
print_ok "Dry run complete — check output above"

# ── Step 6: Usage reference ───────────────────────────────────────────────
print_step "Usage reference"
echo ""
echo "  Dry run (no changes):"
echo "    python3 $DEST --dry-run"
echo ""
echo "  Run now:"
echo "    python3 $DEST"
echo ""
echo "  Analyze since specific date:"
echo "    python3 $DEST --since 2026-03-01"
echo ""
echo "  Undo last batch:"
echo "    git -C $MEMORY_DIR revert HEAD"
echo ""
echo "  The key difference from memory-extract:"
echo "    memory-extract: appends new facts"
echo "    user-model:     corrects/retires outdated beliefs"
echo ""

echo "========================================"
echo "  User Model module setup complete."
echo "========================================"
echo ""
