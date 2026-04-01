#!/usr/bin/env bash
# Module: memory/conversation-index
# Sets up the conversation history indexing and nightly memory extraction pipeline.
#
# What this does:
#   1. Installs conversation-index.py — converts Claude JSONL sessions to
#      searchable markdown in {agent_dir}/conversation-index/
#   2. Installs memory-extract.py — nightly Claude-powered analysis that
#      proposes new memory file additions
#   3. Installs memory-apply.py — review and apply pending proposals
#   4. Adds a qmd "conversations" collection for semantic search
#   5. Schedules nightly indexing + extraction (runs after LCM compaction)
#
# Prerequisites:
#   - qmd installed (https://github.com/qmd-app/qmd or via brew)
#   - claude CLI available and authenticated
#   - LCM module already installed (for session log location)

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_DIR="$DEPLOY_BASE/.$AGENT_NAME"
AGENT_RUNTIME_DIR="${AGENT_RUNTIME_DIR:-$AGENT_DIR}"
CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects/$(basename "$HOME")}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
USER_TZ="${USER_TZ:-UTC}"

CONV_INDEX_DIR="$AGENT_RUNTIME_DIR/conversation-index"
SCRIPTS_DIR="$AGENT_RUNTIME_DIR/scripts"
LOGS_DIR="$AGENT_RUNTIME_DIR/logs"
STATE_DIR="$AGENT_RUNTIME_DIR/state"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  Conversation Index + Memory Extraction"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Create directories ────────────────────────────────────────────
print_step "Creating directories"

for dir in "$CONV_INDEX_DIR" "$SCRIPTS_DIR" "$LOGS_DIR" "$STATE_DIR"; do
  if [ -d "$dir" ]; then
    print_ok "Exists: $dir"
  else
    mkdir -p "$dir"
    print_ok "Created: $dir"
  fi
done

# ── Step 2: Install scripts ───────────────────────────────────────────────
print_step "Installing scripts"

SCRIPTS_SOURCE="$REPO_DIR/scripts"
INSTALL_SCRIPTS=("conversation-index.py" "memory-extract.py" "memory-apply.py")

for script in "${INSTALL_SCRIPTS[@]}"; do
  SRC="$SCRIPTS_SOURCE/$script"
  DEST="$SCRIPTS_DIR/$script"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DEST"
    chmod 755 "$DEST"
    print_ok "Installed: $DEST"
  else
    print_warn "Source not found: $SRC"
  fi
done

# ── Step 3: Run initial index ─────────────────────────────────────────────
print_step "Running initial conversation index"

JSONL_DIR="$CLAUDE_PROJECTS_DIR"
if [ -d "$JSONL_DIR" ] && ls "$JSONL_DIR"/*.jsonl >/dev/null 2>&1; then
  CONV_INDEX_DIR="$CONV_INDEX_DIR" \
  JSONL_DIR="$JSONL_DIR" \
  python3 "$SCRIPTS_DIR/conversation-index.py" 2>&1 | tail -5
  print_ok "Initial index complete"
else
  print_warn "No JSONL sessions found at $JSONL_DIR — skipping initial index"
fi

# ── Step 4: Add qmd collection ────────────────────────────────────────────
print_step "Setting up qmd collection"

if command -v qmd &>/dev/null; then
  if qmd collection list 2>/dev/null | grep -q "conversations"; then
    print_ok "qmd 'conversations' collection already exists"
  else
    qmd collection add "$CONV_INDEX_DIR" --name conversations --mask "**/*.md" 2>&1
    print_ok "Added qmd 'conversations' collection"
  fi
  qmd update >/dev/null 2>&1 && print_ok "qmd index updated"
  print_info "Run 'qmd embed' to enable vector search (may take a few minutes)"
else
  print_warn "qmd not found — skipping collection setup"
  print_info "Install qmd, then run: qmd collection add $CONV_INDEX_DIR --name conversations --mask '**/*.md'"
fi

# ── Step 5: Schedule cron jobs ────────────────────────────────────────────
print_step "Installing cron jobs"

# 4:30 AM local time = 9:30 UTC during CDT, 10:30 UTC during CST
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

CONV_INDEX_SCRIPT="$SCRIPTS_DIR/conversation-index.py"
MEMORY_EXTRACT_SCRIPT="$SCRIPTS_DIR/memory-extract.py"
CONV_INDEX_LOG="$LOGS_DIR/conv-index.log"
MEMORY_EXTRACT_LOG="$LOGS_DIR/memory-extract.log"

CRON_JOB="$CRON_TIME * * * /usr/bin/python3 $CONV_INDEX_SCRIPT >> $CONV_INDEX_LOG 2>&1 && /usr/bin/python3 $MEMORY_EXTRACT_SCRIPT >> $MEMORY_EXTRACT_LOG 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -qF "$CONV_INDEX_SCRIPT"; then
  print_ok "Cron job already installed"
else
  TMPFILE=$(mktemp)
  {
    echo "$EXISTING_CRON"
    echo "# $AGENT_NAME conversation index + memory extraction"
    echo "$CRON_JOB"
  } > "$TMPFILE"
  crontab "$TMPFILE"
  rm -f "$TMPFILE"
  print_ok "Cron job installed ($CRON_TIME UTC = 4:30 AM $USER_TZ)"
fi

# ── Step 6: Usage reference ───────────────────────────────────────────────
print_step "Usage reference"
echo ""
echo "  Search past conversations:"
echo "    qmd query \"what did we do with the cron setup\""
echo "    qmd search \"fitness log format\""
echo ""
echo "  Review pending memory proposals:"
echo "    python3 $SCRIPTS_DIR/memory-apply.py --review"
echo ""
echo "  Apply all proposals:"
echo "    python3 $SCRIPTS_DIR/memory-apply.py --apply"
echo ""
echo "  Reindex all sessions:"
echo "    python3 $SCRIPTS_DIR/conversation-index.py --all"
echo ""
echo "  Manually run extraction:"
echo "    python3 $SCRIPTS_DIR/memory-extract.py"
echo ""
echo "  Conversation index location:"
echo "    $CONV_INDEX_DIR/"
echo ""

echo "========================================"
echo "  Conversation Index module setup complete."
echo "========================================"
echo ""
