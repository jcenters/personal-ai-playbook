#!/usr/bin/env bash
# Module: memory/lcm
# Sets up the Lightweight Conversation Memory (LCM) system.
# Creates session log directories, installs LCM scripts, and schedules nightly compaction.

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_DIR="$DEPLOY_BASE/.$AGENT_NAME"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$AGENT_DIR}"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/projects/$(basename "$HOME")/memory}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
USER_TZ="${USER_TZ:-UTC}"
ENV_FILE="${DEPLOY_BASE:-$HOME}/.env"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  LCM (Lightweight Conversation Memory)"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Create directory structure ────────────────────────────────────
print_step "Creating LCM directory structure"

SESSION_LOG_DIR="$AGENT_RUNTIME_DIR/state/session-logs"
SCRIPTS_DIR="$AGENT_RUNTIME_DIR/scripts"
MEMORY_DIR="$CLAUDE_MEMORY_DIR"

for dir in "$SESSION_LOG_DIR" "$SCRIPTS_DIR" "$MEMORY_DIR"; do
  if [ -d "$dir" ]; then
    print_ok "Exists: $dir"
  else
    mkdir -p "$dir"
    print_ok "Created: $dir"
  fi
done

# ── Step 2: Copy LCM scripts ───────────────────────────────────────────────
print_step "Installing LCM scripts"

SCRIPTS_SOURCE="$REPO_DIR/scripts"

if [ ! -d "$SCRIPTS_SOURCE" ]; then
  print_warn "Scripts source directory not found: $SCRIPTS_SOURCE"
  echo "  Expected to find scripts at: $SCRIPTS_SOURCE"
  echo "  Make sure REPO_DIR is set correctly and the repo is intact."
  echo "  REPO_DIR=$REPO_DIR"
  exit 1
fi

LCM_SCRIPTS=("lcm-log.sh" "load-memory.sh" "lcm-nightly-compact.sh" "lcm-grep.sh")

for script in "${LCM_SCRIPTS[@]}"; do
  SRC="$SCRIPTS_SOURCE/$script"
  DEST="$SCRIPTS_DIR/$script"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DEST"
    chmod 755 "$DEST"
    print_ok "Installed: $DEST"
  else
    print_warn "Source script not found: $SRC"
  fi
done

# ── Step 3: Write .env additions ───────────────────────────────────────────
print_step "Updating environment variables"

add_env_var() {
  local key="$1"
  local value="$2"
  local comment="$3"
  if grep -q "^export $key=" "$ENV_FILE" 2>/dev/null; then
    print_ok "$key already set in $ENV_FILE"
  else
    echo "" >> "$ENV_FILE"
    [ -n "$comment" ] && echo "# $comment" >> "$ENV_FILE"
    echo "export $key=\"$value\"" >> "$ENV_FILE"
    print_ok "Added $key to $ENV_FILE"
  fi
}

add_env_var "AGENT_RUNTIME_DIR" "$AGENT_RUNTIME_DIR" "LCM: runtime directory for $AGENT_NAME"
add_env_var "CLAUDE_MEMORY_DIR" "$CLAUDE_MEMORY_DIR" "LCM: memory files directory"

chmod 600 "$ENV_FILE"

# ── Step 4: Set up cron jobs ───────────────────────────────────────────────
print_step "Installing cron jobs"
echo ""

NIGHTLY_COMPACT_SCRIPT="$SCRIPTS_DIR/lcm-nightly-compact.sh"
CRON_LOG="$AGENT_RUNTIME_DIR/state/lcm-cron.log"

# Determine cron hour/minute for 12:30 AM in the user's timezone
# We convert 00:30 local time to UTC for the cron job
CRON_TIME="30 0"  # Default: 12:30 AM UTC
if command -v python3 &>/dev/null; then
  UTC_TIME=$(python3 -c "
import datetime, zoneinfo, sys
try:
    tz = zoneinfo.ZoneInfo('$USER_TZ')
    local_dt = datetime.datetime(2000, 1, 1, 0, 30, tzinfo=tz)
    utc_dt = local_dt.astimezone(zoneinfo.ZoneInfo('UTC'))
    print(f'{utc_dt.minute} {utc_dt.hour}')
except Exception as e:
    print('30 0')
" 2>/dev/null || echo "30 0")
  CRON_TIME="$UTC_TIME"
  print_info "Nightly compaction scheduled at 12:30 AM $USER_TZ ($CRON_TIME UTC in cron)"
else
  print_info "python3 not available — defaulting to 12:30 AM UTC"
fi

CRON_JOB="$CRON_TIME * * * AGENT_RUNTIME_DIR=\"$AGENT_RUNTIME_DIR\" CLAUDE_MEMORY_DIR=\"$CLAUDE_MEMORY_DIR\" $NIGHTLY_COMPACT_SCRIPT >> $CRON_LOG 2>&1"

# Check if cron job already exists
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -qF "$NIGHTLY_COMPACT_SCRIPT"; then
  print_ok "Nightly compaction cron job already installed"
else
  TMPFILE=$(mktemp)
  {
    echo "$EXISTING_CRON"
    echo "# $AGENT_NAME LCM nightly memory compaction"
    echo "$CRON_JOB"
  } > "$TMPFILE"
  crontab "$TMPFILE"
  rm -f "$TMPFILE"
  print_ok "Nightly compaction cron job installed"
  echo "  Schedule: $CRON_TIME (UTC) = 12:30 AM $USER_TZ"
  echo "  Script:   $NIGHTLY_COMPACT_SCRIPT"
  echo "  Log:      $CRON_LOG"
fi

# ── Step 5: Verify cron ────────────────────────────────────────────────────
echo ""
echo "  Current crontab (LCM entries):"
crontab -l 2>/dev/null | grep -E "lcm|LCM|$AGENT_NAME" | sed 's/^/    /' || echo "    (none found)"
echo ""

# ── Step 6: Quick-use reference ───────────────────────────────────────────
print_step "LCM usage reference"
echo ""
echo "  Log a session event:"
echo "    $SCRIPTS_DIR/lcm-log.sh conversation \"Helped user plan weekly schedule\""
echo "    $SCRIPTS_DIR/lcm-log.sh task_complete \"Drafted 3 emails\""
echo ""
echo "  Load memory into a Claude session:"
echo "    claude --append-system-prompt \"\$($SCRIPTS_DIR/load-memory.sh)\" ..."
echo ""
echo "  Search session history:"
echo "    $SCRIPTS_DIR/lcm-grep.sh \"email drafts\""
echo "    $SCRIPTS_DIR/lcm-grep.sh \"grocery list\""
echo ""
echo "  Manually run nightly compaction:"
echo "    $SCRIPTS_DIR/lcm-nightly-compact.sh"
echo ""
echo "  Session logs location:"
echo "    $SESSION_LOG_DIR/"
echo ""
echo "  Memory files location:"
echo "    $MEMORY_DIR/"
echo ""

echo "========================================"
echo "  LCM module setup complete."
echo "========================================"
echo ""
