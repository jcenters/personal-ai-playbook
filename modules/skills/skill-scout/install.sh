#!/usr/bin/env bash
# Module: skills/skill-scout
# Sets up the autonomous skill generation pipeline.
#
# What this does:
#   1. Installs skill-scout.py — nightly Claude-powered analysis that identifies
#      recurring task patterns in conversation history and proposes new skill files
#   2. Schedules it to run nightly after conversation indexing
#   3. Approval flow: "approve skills" / "reject skills" via Telegram
#
# Prerequisites:
#   - memory/conversation-index module installed (needs conversation-index/)
#   - claude CLI available and authenticated
#   - TELEGRAM_BOT_TOKEN in .env (for proposal notifications)
#   - Skills repo at ~/.claude/skills/ (git-backed)

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_DIR="$DEPLOY_BASE/.$AGENT_NAME"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$AGENT_DIR}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
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
echo "  Skill Scout — Autonomous Skill Generation"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Create directories ────────────────────────────────────────────
print_step "Creating directories"

for dir in "$SCRIPTS_DIR" "$LOGS_DIR" "$STATE_DIR"; do
  mkdir -p "$dir"
  print_ok "Ready: $dir"
done

# ── Step 2: Install script ────────────────────────────────────────────────
print_step "Installing skill-scout.py"

SRC="$REPO_DIR/scripts/skill-scout.py"
DEST="$SCRIPTS_DIR/skill-scout.py"
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

if ! command -v claude &>/dev/null; then
  print_warn "claude CLI not found — skill-scout requires it"
  exit 1
fi
print_ok "claude CLI found"

# ── Step 4: Schedule cron ─────────────────────────────────────────────────
print_step "Installing cron job"

# 4:30 AM local time
CRON_TIME="30 9"
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

SKILL_SCOUT_LOG="$LOGS_DIR/skill-scout.log"
CRON_JOB="$CRON_TIME * * * /usr/bin/python3 $DEST >> $SKILL_SCOUT_LOG 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -qF "$DEST"; then
  print_ok "Cron job already installed"
else
  TMPFILE=$(mktemp)
  {
    echo "$EXISTING_CRON"
    echo "# $AGENT_NAME skill-scout nightly"
    echo "$CRON_JOB"
  } > "$TMPFILE"
  crontab "$TMPFILE"
  rm -f "$TMPFILE"
  print_ok "Cron job installed ($CRON_TIME UTC = 4:30 AM $USER_TZ)"
fi

# ── Step 5: Add CLAUDE.md commands ───────────────────────────────────────
print_step "Usage: add these commands to your CLAUDE.md"
echo ""
echo '  ## Skill Scout Commands'
echo '  When Josh sends "approve skills" or "reject skills" via Telegram:'
echo '  ```bash'
echo "  python3 $DEST --apply   # write proposed skills and commit"
echo "  python3 $DEST --reject  # discard proposals"
echo '  ```'
echo ""

# ── Step 6: Reference ─────────────────────────────────────────────────────
print_step "Usage reference"
echo ""
echo "  Check pending proposals:"
echo "    python3 $DEST --status"
echo ""
echo "  Manually run analysis:"
echo "    python3 $DEST"
echo ""
echo "  Apply pending proposals:"
echo "    python3 $DEST --apply"
echo ""
echo "  Proposals file:"
echo "    $STATE_DIR/skill-proposals.json"
echo ""

echo "========================================"
echo "  Skill Scout setup complete."
echo "========================================"
echo ""
