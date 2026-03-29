#!/usr/bin/env bash
# personal-ai-playbook setup wizard
# https://github.com/your-org/personal-ai-playbook
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()     { echo -e "${GREEN}  [ok]${RESET} $*"; }
info()   { echo -e "${CYAN}  [--]${RESET} $*"; }
prompt() { echo -e "${YELLOW}  [??]${RESET} $*"; }
err()    { echo -e "${RED}  [!!]${RESET} $*" >&2; }
die()    { err "$*"; exit 1; }

section() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━  $*  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

ask() {
  # ask VAR "Prompt text" "default"
  local varname="$1"
  local question="$2"
  local default="${3:-}"
  local display_default=""
  [[ -n "$default" ]] && display_default=" ${CYAN}[${default}]${RESET}"
  prompt "${question}${display_default}: "
  read -r "$varname" </dev/tty || true
  # Apply default if empty
  if [[ -z "${!varname}" && -n "$default" ]]; then
    printf -v "$varname" '%s' "$default"
  fi
}

ask_yn() {
  # ask_yn "Question" "y|n" — returns 0 for yes, 1 for no
  local question="$1"
  local default="${2:-n}"
  local yn_display
  if [[ "$default" == "y" ]]; then
    yn_display="${GREEN}Y${RESET}/n"
  else
    yn_display="y/${GREEN}N${RESET}"
  fi
  prompt "${question} [${yn_display}]: "
  local ans
  read -r ans </dev/tty || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

# ─── Banner ───────────────────────────────────────────────────────────────────

clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
 ____  _____ ____  ____  ___  _   _    _    _
|  _ \| ____|  _ \/ ___|/ _ \| \ | |  / \  | |
| |_) |  _| | |_) \___ \ | | |  \| | / _ \ | |
|  __/| |___|  _ < ___) | |_| | |\  |/ ___ \| |___
|_|  _|_____|_| \_\____/ \___/|_| \_/_/   \_\_____|
    / \  |_ _|  _ \| |    / \\ \ / / __ )  / _ \ / _ \| |/
   / _ \  | || |_) | |   / _ \\ V /|  _ \ | | | | | | | ' /
  / ___ \ | ||  __/| |__/ ___ \| | | |_) || |_| | |_| | . \
 /_/   \_\___|_|   |_____/_/   \_\_| |____/  \___/ \___/|_|\_\

BANNER
echo -e "${RESET}"
echo -e "${BOLD}  personal-ai-playbook setup wizard${RESET}"
echo -e "  Deploy a personal AI assistant using Claude Code."
echo -e "  No API keys required — just your claude.ai subscription."
echo ""

# ─── Prerequisite Checks ──────────────────────────────────────────────────────

section "Checking Prerequisites"

# claude CLI
if command -v claude &>/dev/null; then
  CLAUDE_VERSION="$(claude --version 2>&1 | head -1)"
  ok "claude CLI found: ${CLAUDE_VERSION}"
else
  die "claude CLI not found. Install from https://claude.ai/download or: npm install -g @anthropic-ai/claude-code"
fi

# git
if command -v git &>/dev/null; then
  GIT_VERSION="$(git --version)"
  ok "${GIT_VERSION}"
else
  die "git not found. Install git and re-run setup."
fi

# Node or Bun
if command -v bun &>/dev/null; then
  BUN_VERSION="$(bun --version)"
  ok "bun ${BUN_VERSION} found"
  JS_RUNTIME="bun"
elif command -v node &>/dev/null; then
  NODE_VERSION="$(node --version)"
  ok "node ${NODE_VERSION} found"
  JS_RUNTIME="node"
else
  err "Neither node nor bun found. Some channel plugins require one."
  info "Install Node.js v18+ from https://nodejs.org or Bun from https://bun.sh"
  JS_RUNTIME="none"
fi

# tmux
if command -v tmux &>/dev/null; then
  TMUX_VERSION="$(tmux -V)"
  ok "${TMUX_VERSION}"
else
  die "tmux not found. Install tmux (e.g., apt install tmux) and re-run setup."
fi

# ─── Basic Configuration ──────────────────────────────────────────────────────

section "Basic Configuration"

ask AGENT_NAME "Assistant name (used for directory and session names)" "assistant"
# Sanitize: lowercase, alphanumeric and hyphens only
AGENT_NAME="$(echo "$AGENT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')"
ok "Agent name: ${AGENT_NAME}"

ask USER_NAME "Your full name" ""
[[ -n "$USER_NAME" ]] || die "User name is required."
ok "User name: ${USER_NAME}"

# Timezone selection
echo ""
info "Select your timezone:"
TIMEZONES=(
  "US/Eastern"
  "US/Central"
  "US/Mountain"
  "US/Pacific"
  "Europe/London"
  "Europe/Berlin"
  "Asia/Tokyo"
  "Australia/Sydney"
  "Other (enter manually)"
)
for i in "${!TIMEZONES[@]}"; do
  echo -e "    ${CYAN}$((i+1))${RESET}) ${TIMEZONES[$i]}"
done
echo ""
ask TZ_CHOICE "Timezone number" "2"
TZ_INDEX=$((TZ_CHOICE - 1))
if [[ $TZ_INDEX -ge 0 && $TZ_INDEX -lt $((${#TIMEZONES[@]} - 1)) ]]; then
  USER_TIMEZONE="${TIMEZONES[$TZ_INDEX]}"
elif [[ $TZ_INDEX -eq $((${#TIMEZONES[@]} - 1)) ]]; then
  ask USER_TIMEZONE "Enter timezone (e.g., America/Chicago)" "America/Chicago"
else
  err "Invalid choice, defaulting to US/Central"
  USER_TIMEZONE="US/Central"
fi
ok "Timezone: ${USER_TIMEZONE}"

ask DEPLOY_BASE "Deploy base path" "$HOME"
DEPLOY_BASE="${DEPLOY_BASE%/}"   # strip trailing slash
[[ -d "$DEPLOY_BASE" ]] || die "Directory does not exist: ${DEPLOY_BASE}"
ok "Deploy base: ${DEPLOY_BASE}"

RUNTIME_DIR="${DEPLOY_BASE}/.${AGENT_NAME}"
CONFIG_REPO="${DEPLOY_BASE}/${AGENT_NAME}-config"
info "Runtime dir will be: ${RUNTIME_DIR}"
info "Config repo will be: ${CONFIG_REPO}"

# ─── Messaging Channel ────────────────────────────────────────────────────────

section "Messaging Channel"

echo -e "  Choose how you will send messages to your assistant:"
echo ""
echo -e "    ${CYAN}1${RESET}) Telegram  ${GREEN}(recommended)${RESET}"
echo -e "    ${CYAN}2${RESET}) Discord"
echo -e "    ${CYAN}3${RESET}) iMessage  ${YELLOW}(macOS only)${RESET}"
echo -e "    ${CYAN}4${RESET}) None / set up later"
echo ""
ask CHANNEL_CHOICE "Channel number" "1"

case "$CHANNEL_CHOICE" in
  1) CHANNEL="telegram";  CHANNEL_FLAG="--input-format stream-json" ;;
  2) CHANNEL="discord";   CHANNEL_FLAG="--input-format stream-json" ;;
  3) CHANNEL="imessage";  CHANNEL_FLAG="" ;;
  4) CHANNEL="none";      CHANNEL_FLAG="" ;;
  *) err "Invalid choice, defaulting to none"; CHANNEL="none"; CHANNEL_FLAG="" ;;
esac
ok "Channel: ${CHANNEL}"

if [[ "$CHANNEL" == "imessage" ]] && [[ "$(uname)" != "Darwin" ]]; then
  err "iMessage is only available on macOS. Switching to 'none'."
  CHANNEL="none"
  CHANNEL_FLAG=""
fi

# ─── Persona Selection ────────────────────────────────────────────────────────

section "Persona"

echo -e "  Choose a persona for your assistant:"
echo ""
echo -e "    ${CYAN}1${RESET}) Executive PA     — scheduling, tasks, professional communication"
echo -e "    ${CYAN}2${RESET}) Creative Partner — writing, brainstorming, editorial feedback"
echo -e "    ${CYAN}3${RESET}) Coach            — goals, habits, accountability, fitness"
echo -e "    ${CYAN}4${RESET}) Researcher       — deep research, synthesis, fact-checking"
echo -e "    ${CYAN}5${RESET}) Family Hub       — household coordination, reminders, logistics"
echo -e "    ${CYAN}6${RESET}) Custom           — write your own"
echo ""
ask PERSONA_CHOICE "Persona number" "1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$PERSONA_CHOICE" in
  1) PERSONA_FILE="${SCRIPT_DIR}/personas/executive-pa.md" ;;
  2) PERSONA_FILE="${SCRIPT_DIR}/personas/creative-partner.md" ;;
  3) PERSONA_FILE="${SCRIPT_DIR}/personas/coach.md" ;;
  4) PERSONA_FILE="${SCRIPT_DIR}/personas/researcher.md" ;;
  5) PERSONA_FILE="${SCRIPT_DIR}/personas/family-hub.md" ;;
  6) PERSONA_FILE="" ;;
  *) err "Invalid choice, defaulting to Executive PA"; PERSONA_FILE="${SCRIPT_DIR}/personas/executive-pa.md" ;;
esac

if [[ "$PERSONA_CHOICE" == "6" ]]; then
  info "Custom persona selected."
  CUSTOM_PERSONA_FILE="$(mktemp /tmp/persona.XXXXXX.md)"
  if [[ -n "${EDITOR:-}" ]]; then
    info "Opening \$EDITOR (${EDITOR})..."
    "${EDITOR}" "$CUSTOM_PERSONA_FILE" </dev/tty >/dev/tty
  else
    echo -e "  Enter your persona description. Type ${CYAN}END${RESET} on its own line when done:"
    PERSONA_LINES=()
    while IFS= read -r line </dev/tty; do
      [[ "$line" == "END" ]] && break
      PERSONA_LINES+=("$line")
    done
    printf '%s\n' "${PERSONA_LINES[@]}" > "$CUSTOM_PERSONA_FILE"
  fi
  PERSONA_CONTENT="$(cat "$CUSTOM_PERSONA_FILE")"
  rm -f "$CUSTOM_PERSONA_FILE"
elif [[ -f "$PERSONA_FILE" ]]; then
  PERSONA_CONTENT="$(cat "$PERSONA_FILE")"
  ok "Loaded persona: ${PERSONA_FILE}"
else
  err "Persona file not found: ${PERSONA_FILE}. Using a minimal default."
  PERSONA_CONTENT="You are a helpful personal assistant. Be concise, accurate, and proactive."
fi

# ─── Secrets Manager ─────────────────────────────────────────────────────────

section "Secrets Manager"

echo -e "  How should the assistant retrieve secrets?"
echo ""
echo -e "    ${CYAN}1${RESET}) 1Password  ${GREEN}(recommended — op CLI)${RESET}"
echo -e "    ${CYAN}2${RESET}) Bitwarden   (bw CLI)"
echo -e "    ${CYAN}3${RESET}) Environment file only  (.env)"
echo ""
ask SECRETS_CHOICE "Secrets manager number" "1"

case "$SECRETS_CHOICE" in
  1) SECRETS_MANAGER="1password" ;;
  2) SECRETS_MANAGER="bitwarden" ;;
  3) SECRETS_MANAGER="env-only" ;;
  *) err "Invalid choice, defaulting to env-only"; SECRETS_MANAGER="env-only" ;;
esac
ok "Secrets manager: ${SECRETS_MANAGER}"

if [[ "$SECRETS_MANAGER" == "1password" ]] && ! command -v op &>/dev/null; then
  err "op CLI not found. Install from https://developer.1password.com/docs/cli/"
  info "Continuing with env-only fallback. You can switch after setup."
  SECRETS_MANAGER="env-only"
fi

if [[ "$SECRETS_MANAGER" == "bitwarden" ]] && ! command -v bw &>/dev/null; then
  err "bw CLI not found. Install from https://bitwarden.com/help/cli/"
  info "Continuing with env-only fallback. You can switch after setup."
  SECRETS_MANAGER="env-only"
fi

# ─── Optional Modules ─────────────────────────────────────────────────────────

section "Optional Modules"

echo -e "  Select which modules to install. You can always add more later."
echo ""

MODULE_GOOGLE_WORKSPACE=false
MODULE_OBSIDIAN=false
MODULE_FITNESS=false
MODULE_JOB_SEARCH=false
MODULE_SYSTEM_HEALTH=false
MODULE_RESEARCH=false
MODULE_LCM_MEMORY=false
MODULE_DAILY_BRIEFING=false
MODULE_VOICE_INPUT=false

ask_yn "Google Workspace (calendar & email via gws CLI)?" "n" \
  && MODULE_GOOGLE_WORKSPACE=true && ok "  Google Workspace: enabled"   || info "  Google Workspace: skipped"

ask_yn "Obsidian vault integration?" "n" \
  && MODULE_OBSIDIAN=true && ok "  Obsidian: enabled"                   || info "  Obsidian: skipped"

ask_yn "Fitness coach agent?" "n" \
  && MODULE_FITNESS=true && ok "  Fitness coach: enabled"               || info "  Fitness coach: skipped"

ask_yn "Job search agent?" "n" \
  && MODULE_JOB_SEARCH=true && ok "  Job search: enabled"               || info "  Job search: skipped"

ask_yn "System health monitor agent?" "n" \
  && MODULE_SYSTEM_HEALTH=true && ok "  System health: enabled"         || info "  System health: skipped"

ask_yn "Research agent?" "n" \
  && MODULE_RESEARCH=true && ok "  Research agent: enabled"             || info "  Research agent: skipped"

ask_yn "LCM memory system (session logging + nightly compaction)?" "y" \
  && MODULE_LCM_MEMORY=true && ok "  LCM memory: enabled"              || info "  LCM memory: skipped"

ask_yn "Scheduled daily briefings (morning/evening routines)?" "n" \
  && MODULE_DAILY_BRIEFING=true && ok "  Daily briefings: enabled"      || info "  Daily briefings: skipped"

ask_yn "Voice input via faster-whisper (local STT, no API key)?" "n" \
  && MODULE_VOICE_INPUT=true && ok "  Voice input: enabled"             || info "  Voice input: skipped"

# ─── Credential Collection ────────────────────────────────────────────────────

section "Credential Collection"

ENV_FILE="${DEPLOY_BASE}/.env"
info "Writing credentials to: ${ENV_FILE}"
info "This file will NOT be committed to git."
echo ""

# Initialize or append to .env
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

write_env() {
  local key="$1"
  local val="$2"
  local comment="${3:-}"
  if [[ -n "$comment" ]]; then
    echo "" >> "$ENV_FILE"
    echo "# ${comment}" >> "$ENV_FILE"
  fi
  # Only write if not already set
  if ! grep -q "^export ${key}=" "$ENV_FILE" 2>/dev/null; then
    echo "export ${key}=\"${val}\"" >> "$ENV_FILE"
  fi
}

write_env "AGENT_NAME" "$AGENT_NAME" "Agent identity"
write_env "USER_NAME" "$USER_NAME"
write_env "USER_TIMEZONE" "$USER_TIMEZONE"
write_env "DEPLOY_BASE" "$DEPLOY_BASE"
write_env "SECRETS_MANAGER" "$SECRETS_MANAGER"

if [[ "$CHANNEL" == "telegram" ]]; then
  echo ""
  info "Telegram requires a bot token from @BotFather and your chat ID."
  info "Create a bot at https://t.me/BotFather — send /newbot and copy the token."
  ask TG_TOKEN "Telegram bot token (leave blank to set later)" ""
  ask TG_CHAT_ID "Your Telegram chat ID (leave blank to set later)" ""
  write_env "TELEGRAM_BOT_TOKEN" "$TG_TOKEN"   "Telegram channel"
  write_env "TELEGRAM_CHAT_ID"   "$TG_CHAT_ID"
fi

if [[ "$CHANNEL" == "discord" ]]; then
  echo ""
  info "Discord requires a bot token from https://discord.com/developers/applications"
  ask DC_TOKEN "Discord bot token (leave blank to set later)" ""
  ask DC_CHANNEL "Discord channel ID (leave blank to set later)" ""
  write_env "DISCORD_BOT_TOKEN" "$DC_TOKEN"    "Discord channel"
  write_env "DISCORD_CHANNEL_ID" "$DC_CHANNEL"
fi

if [[ "$MODULE_GOOGLE_WORKSPACE" == true ]]; then
  echo ""
  info "Google Workspace integration uses the gws CLI."
  info "Install gws: https://github.com/nicholasgasior/gws-cli"
  ask GWS_ACCOUNT "Google account email for gws (leave blank to set later)" ""
  write_env "GWS_ACCOUNT" "$GWS_ACCOUNT" "Google Workspace (gws)"
fi

if [[ "$MODULE_OBSIDIAN" == true ]]; then
  echo ""
  ask OBSIDIAN_VAULT "Path to your Obsidian vault directory" "$HOME/Documents/vault"
  write_env "OBSIDIAN_VAULT" "$OBSIDIAN_VAULT" "Obsidian vault"
fi

if [[ "$SECRETS_MANAGER" == "1password" ]]; then
  echo ""
  info "1Password: set OP_SERVICE_ACCOUNT_TOKEN in ${ENV_FILE} if using a service account."
  ask OP_VAULT "1Password vault name" "Personal"
  write_env "OP_VAULT" "$OP_VAULT" "1Password"
fi

if [[ "$SECRETS_MANAGER" == "bitwarden" ]]; then
  echo ""
  ask BW_URL "Bitwarden server URL (leave blank for bitwarden.com)" ""
  write_env "BW_URL" "${BW_URL:-https://vault.bitwarden.com}" "Bitwarden"
fi

ok "Credentials written to ${ENV_FILE}"

# ─── Directory Structure ──────────────────────────────────────────────────────

section "Creating Directory Structure"

# Runtime directory
mkdir -p "${RUNTIME_DIR}/scripts"
mkdir -p "${RUNTIME_DIR}/memory"
mkdir -p "${RUNTIME_DIR}/state"
ok "Runtime dir: ${RUNTIME_DIR}"

# Config repo
mkdir -p "${CONFIG_REPO}/skills"
mkdir -p "${CONFIG_REPO}/modules"
ok "Config repo: ${CONFIG_REPO}"

# ─── File Generation from Templates ──────────────────────────────────────────

section "Generating Config Files"

TMPL_DIR="${SCRIPT_DIR}/templates"

render_template() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || { err "Template not found: ${src}"; return 1; }
  mkdir -p "$(dirname "$dst")"
  sed \
    -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
    -e "s|{{USER_NAME}}|${USER_NAME}|g" \
    -e "s|{{USER_TIMEZONE}}|${USER_TIMEZONE}|g" \
    -e "s|{{DEPLOY_BASE}}|${DEPLOY_BASE}|g" \
    -e "s|{{CHANNEL}}|${CHANNEL}|g" \
    -e "s|{{CHANNEL_FLAG}}|${CHANNEL_FLAG}|g" \
    -e "s|{{SECRETS_MANAGER}}|${SECRETS_MANAGER}|g" \
    "$src" > "$dst"
  ok "Generated: ${dst}"
}

# Render CLAUDE.md
render_template "${TMPL_DIR}/CLAUDE.md.tmpl" "${CONFIG_REPO}/CLAUDE.md"

# Inject module-specific content into CLAUDE.md
inject_module_block() {
  local marker="$1"   # e.g., "google-workspace"
  local content="$2"
  local file="${CONFIG_REPO}/CLAUDE.md"
  if grep -q "# \[MODULE: ${marker}\]" "$file"; then
    # Replace the placeholder comment with actual content
    python3 -c "
import sys, re
marker = '# [MODULE: ${marker}]'
content = '''${content}'''
with open('${file}', 'r') as f:
    text = f.read()
text = text.replace(marker, content)
with open('${file}', 'w') as f:
    f.write(text)
" 2>/dev/null || sed -i "s|# \[MODULE: ${marker}\]|${content}|g" "$file"
  fi
}

[[ "$MODULE_GOOGLE_WORKSPACE" == true ]] && inject_module_block "google-workspace" \
  "## Google Workspace\n\nUse the \`gws\` CLI for calendar and email. Account: \${GWS_ACCOUNT}.\n\n\`\`\`bash\ngws gmail +triage\ngws calendar +agenda --today\n\`\`\`"

[[ "$MODULE_OBSIDIAN" == true ]] && inject_module_block "obsidian" \
  "## Obsidian Vault\n\nVault path: \${OBSIDIAN_VAULT}. Always append to daily notes — never overwrite."

[[ "$MODULE_LCM_MEMORY" == true ]] && inject_module_block "memory" \
  "## Memory\n\nSession logs are written to \${DEPLOY_BASE}/.${AGENT_NAME}/memory/. Nightly compaction via compact-memory.sh. The load-memory.sh script prepends context at startup."

# Render SOUL.md — insert persona content
if [[ -f "${TMPL_DIR}/SOUL.md.tmpl" ]]; then
  SOUL_DST="${CONFIG_REPO}/SOUL.md"
  sed "s|{{PERSONA_CONTENT}}|$(printf '%s' "$PERSONA_CONTENT" | sed 's/[&/\]/\\&/g; s/$/\\n/' | tr -d '\n')|g" \
    "${TMPL_DIR}/SOUL.md.tmpl" > "$SOUL_DST" 2>/dev/null \
    || { echo "# SOUL.md — Persona Definition"; echo ""; echo "$PERSONA_CONTENT"; } > "$SOUL_DST"
  ok "Generated: ${SOUL_DST}"
fi

# Render start script
START_SCRIPT="${DEPLOY_BASE}/start-${AGENT_NAME}.sh"
render_template "${TMPL_DIR}/start.sh.tmpl" "$START_SCRIPT"
chmod +x "$START_SCRIPT"

# Stop script
STOP_SCRIPT="${DEPLOY_BASE}/stop-${AGENT_NAME}.sh"
cat > "$STOP_SCRIPT" << STOPEOF
#!/usr/bin/env bash
# Stop the ${AGENT_NAME} assistant session
tmux kill-session -t "${AGENT_NAME}" 2>/dev/null && echo "Stopped ${AGENT_NAME}" || echo "${AGENT_NAME} was not running"
rm -f "${RUNTIME_DIR}/state/running"
STOPEOF
chmod +x "$STOP_SCRIPT"
ok "Generated: ${STOP_SCRIPT}"

# Render .env template (as reference — actual .env already populated)
if [[ -f "${TMPL_DIR}/.env.tmpl" ]]; then
  render_template "${TMPL_DIR}/.env.tmpl" "${CONFIG_REPO}/.env.example"
  ok "Generated: ${CONFIG_REPO}/.env.example"
fi

# ─── LCM Memory Scripts ───────────────────────────────────────────────────────

if [[ "$MODULE_LCM_MEMORY" == true ]]; then
  section "Setting Up LCM Memory"

  LOAD_MEMORY="${RUNTIME_DIR}/scripts/load-memory.sh"
  cat > "$LOAD_MEMORY" << MEMEOF
#!/usr/bin/env bash
# Load compacted memory context for startup prompt injection
MEMORY_DIR="${RUNTIME_DIR}/memory"
CONTEXT_FILE="\${MEMORY_DIR}/context.md"

if [[ -f "\$CONTEXT_FILE" ]]; then
  echo "--- BEGIN MEMORY CONTEXT ---"
  cat "\$CONTEXT_FILE"
  echo "--- END MEMORY CONTEXT ---"
fi
MEMEOF
  chmod +x "$LOAD_MEMORY"
  ok "Generated: ${LOAD_MEMORY}"

  COMPACT_MEMORY="${RUNTIME_DIR}/scripts/compact-memory.sh"
  cat > "$COMPACT_MEMORY" << COMPEOF
#!/usr/bin/env bash
# Compact session logs into rolling context file
# Runs nightly via cron
set -euo pipefail
MEMORY_DIR="${RUNTIME_DIR}/memory"
LOGS_DIR="\${MEMORY_DIR}/sessions"
CONTEXT_FILE="\${MEMORY_DIR}/context.md"
ARCHIVE_DIR="\${MEMORY_DIR}/archive"

mkdir -p "\$LOGS_DIR" "\$ARCHIVE_DIR"

# Find session logs older than 1 day
OLD_LOGS="\$(find "\$LOGS_DIR" -name "*.md" -mtime +1 2>/dev/null | sort)"

if [[ -z "\$OLD_LOGS" ]]; then
  echo "No logs to compact."
  exit 0
fi

# Ask Claude to summarize
COMBINED="\$(cat \$OLD_LOGS)"
SUMMARY="\$(echo "\$COMBINED" | claude --print --dangerously-skip-permissions \
  "Summarize these session logs into a concise memory context file. \
   Focus on: facts learned about the user, ongoing tasks, preferences, decisions made. \
   Be terse. Output markdown." 2>/dev/null || echo "\$COMBINED")"

# Append to context file
{
  echo ""
  echo "## Compacted: \$(date -I)"
  echo ""
  echo "\$SUMMARY"
} >> "\$CONTEXT_FILE"

# Archive processed logs
for log in \$OLD_LOGS; do
  mv "\$log" "\$ARCHIVE_DIR/"
done

echo "Compacted \$(echo "\$OLD_LOGS" | wc -l) session logs."
COMPEOF
  chmod +x "$COMPACT_MEMORY"
  ok "Generated: ${COMPACT_MEMORY}"

  if [[ "$MODULE_DAILY_BRIEFING" == true ]]; then
    BRIEFING_SCRIPT="${RUNTIME_DIR}/scripts/daily-briefing.sh"
    cat > "$BRIEFING_SCRIPT" << BRIEFEOF
#!/usr/bin/env bash
# Send daily briefing via ${CHANNEL}
# Called by cron
set -euo pipefail
source "${DEPLOY_BASE}/.env"

BRIEFING_TYPE="\${1:-morning}"

if [[ "\$BRIEFING_TYPE" == "morning" ]]; then
  PROMPT="Give me a morning briefing: today's date, day of week, any calendar events \
if you have access, top priorities I should know, and a short motivating note. \
Keep it under 200 words."
else
  PROMPT="Give me an evening summary: what did we accomplish today, what's pending, \
anything to remember for tomorrow. Under 150 words."
fi

claude --print --dangerously-skip-permissions "\$PROMPT" 2>/dev/null
BRIEFEOF
    chmod +x "$BRIEFING_SCRIPT"
    ok "Generated: ${BRIEFING_SCRIPT}"
  fi
fi

# ─── Module Install Scripts ───────────────────────────────────────────────────

section "Running Module Install Scripts"

run_module_install() {
  local module_path="${SCRIPT_DIR}/modules/${1}/install.sh"
  if [[ -f "$module_path" ]]; then
    info "Installing module: ${1}"
    bash "$module_path" \
      AGENT_NAME="$AGENT_NAME" \
      DEPLOY_BASE="$DEPLOY_BASE" \
      RUNTIME_DIR="$RUNTIME_DIR" \
      CONFIG_REPO="$CONFIG_REPO" \
      || err "Module install had warnings: ${1}"
    ok "Module installed: ${1}"
  else
    info "No install script for module: ${1} (skipping)"
  fi
}

[[ "$CHANNEL" != "none" ]] && run_module_install "messaging/${CHANNEL}"
[[ "$MODULE_GOOGLE_WORKSPACE" == true ]] && run_module_install "calendar/google-workspace"
[[ "$MODULE_OBSIDIAN" == true ]]         && run_module_install "storage/obsidian"
[[ "$MODULE_FITNESS" == true ]]          && run_module_install "agents/fitness"
[[ "$MODULE_JOB_SEARCH" == true ]]       && run_module_install "agents/job-search"
[[ "$MODULE_SYSTEM_HEALTH" == true ]]    && run_module_install "agents/system-health"
[[ "$MODULE_RESEARCH" == true ]]         && run_module_install "agents/research"
[[ "$MODULE_LCM_MEMORY" == true ]]       && run_module_install "memory/lcm"
[[ "$MODULE_DAILY_BRIEFING" == true ]]   && run_module_install "routines/daily-briefing"
[[ "$MODULE_VOICE_INPUT" == true ]]        && run_module_install "voice-input/faster-whisper"

# ─── Config Repo: Git Init ────────────────────────────────────────────────────

section "Initializing Config Repository"

cd "$CONFIG_REPO"

# Add .gitignore for the config repo
cat > "${CONFIG_REPO}/.gitignore" << 'GITEOF'
.env
.env.*
!.env.example
*.secret
*.key
*.log
__pycache__/
*.pyc
GITEOF

if [[ ! -d "${CONFIG_REPO}/.git" ]]; then
  git init -q
  ok "Git init: ${CONFIG_REPO}"
fi

# Symlink CLAUDE.md to runtime (Claude Code picks it up from the working dir)
if [[ ! -L "${RUNTIME_DIR}/CLAUDE.md" ]]; then
  ln -sf "${CONFIG_REPO}/CLAUDE.md" "${RUNTIME_DIR}/CLAUDE.md"
  ok "Symlinked CLAUDE.md into runtime dir"
fi
if [[ ! -L "${RUNTIME_DIR}/SOUL.md" ]]; then
  ln -sf "${CONFIG_REPO}/SOUL.md" "${RUNTIME_DIR}/SOUL.md"
  ok "Symlinked SOUL.md into runtime dir"
fi

git add -A
git diff --cached --quiet || git commit -q -m "Initial ${AGENT_NAME} config" \
  --author="setup.sh <setup@personal-ai-playbook>"
ok "Initial commit created in ${CONFIG_REPO}"

cd "$SCRIPT_DIR"

# ─── Cron Jobs ────────────────────────────────────────────────────────────────

section "Setting Up Cron Jobs"

# @reboot: start assistant on boot
REBOOT_CRON="@reboot sleep 30 && ${START_SCRIPT}"
if crontab -l 2>/dev/null | grep -qF "$START_SCRIPT"; then
  info "@reboot cron already set — skipping"
else
  (crontab -l 2>/dev/null || true; echo "$REBOOT_CRON") | crontab -
  ok "@reboot cron added: ${START_SCRIPT}"
fi

# LCM memory compaction: nightly at 2am
if [[ "$MODULE_LCM_MEMORY" == true ]]; then
  COMPACT_CRON="0 2 * * * ${COMPACT_MEMORY} >> ${RUNTIME_DIR}/memory/compact.log 2>&1"
  if crontab -l 2>/dev/null | grep -qF "$COMPACT_MEMORY"; then
    info "Memory compaction cron already set — skipping"
  else
    (crontab -l 2>/dev/null || true; echo "$COMPACT_CRON") | crontab -
    ok "Memory compaction cron added (nightly 2am)"
  fi
fi

# Daily briefings
if [[ "$MODULE_DAILY_BRIEFING" == true ]]; then
  MORNING_CRON="0 7 * * * ${RUNTIME_DIR}/scripts/daily-briefing.sh morning >> ${RUNTIME_DIR}/state/briefing.log 2>&1"
  EVENING_CRON="0 20 * * * ${RUNTIME_DIR}/scripts/daily-briefing.sh evening >> ${RUNTIME_DIR}/state/briefing.log 2>&1"
  (crontab -l 2>/dev/null | grep -v "daily-briefing.sh" || true
   echo "$MORNING_CRON"
   echo "$EVENING_CRON") | crontab -
  ok "Daily briefing crons added (7am morning, 8pm evening)"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

section "Setup Complete"

echo -e "${BOLD}${GREEN}  Your assistant is ready.${RESET}"
echo ""
echo -e "  ${BOLD}Name:${RESET}          ${AGENT_NAME}"
echo -e "  ${BOLD}User:${RESET}          ${USER_NAME}"
echo -e "  ${BOLD}Timezone:${RESET}      ${USER_TIMEZONE}"
echo -e "  ${BOLD}Channel:${RESET}       ${CHANNEL}"
echo -e "  ${BOLD}Persona:${RESET}       $(basename "${PERSONA_FILE:-custom}")"
echo -e "  ${BOLD}Secrets:${RESET}       ${SECRETS_MANAGER}"
echo ""
echo -e "  ${BOLD}Paths:${RESET}"
echo -e "    Runtime dir:   ${CYAN}${RUNTIME_DIR}${RESET}"
echo -e "    Config repo:   ${CYAN}${CONFIG_REPO}${RESET}"
echo -e "    Start script:  ${CYAN}${START_SCRIPT}${RESET}"
echo -e "    Credentials:   ${CYAN}${ENV_FILE}${RESET}"
echo ""
echo -e "  ${BOLD}Modules enabled:${RESET}"
[[ "$MODULE_GOOGLE_WORKSPACE" == true ]] && echo -e "    ${GREEN}+${RESET} Google Workspace"
[[ "$MODULE_OBSIDIAN" == true ]]         && echo -e "    ${GREEN}+${RESET} Obsidian vault"
[[ "$MODULE_FITNESS" == true ]]          && echo -e "    ${GREEN}+${RESET} Fitness coach agent"
[[ "$MODULE_JOB_SEARCH" == true ]]       && echo -e "    ${GREEN}+${RESET} Job search agent"
[[ "$MODULE_SYSTEM_HEALTH" == true ]]    && echo -e "    ${GREEN}+${RESET} System health monitor"
[[ "$MODULE_RESEARCH" == true ]]         && echo -e "    ${GREEN}+${RESET} Research agent"
[[ "$MODULE_LCM_MEMORY" == true ]]       && echo -e "    ${GREEN}+${RESET} LCM memory"
[[ "$MODULE_DAILY_BRIEFING" == true ]]   && echo -e "    ${GREEN}+${RESET} Daily briefings"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo ""

if [[ "$CHANNEL" == "telegram" ]]; then
  echo -e "  ${CYAN}1.${RESET} Complete Telegram setup:"
  echo -e "     - If you haven't already: go to @BotFather → /newbot"
  echo -e "     - Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in ${ENV_FILE}"
  echo -e "     - Find your chat ID by messaging @userinfobot"
  echo ""
fi

if [[ "$CHANNEL" == "discord" ]]; then
  echo -e "  ${CYAN}1.${RESET} Complete Discord setup:"
  echo -e "     - Create a bot at https://discord.com/developers/applications"
  echo -e "     - Set DISCORD_BOT_TOKEN and DISCORD_CHANNEL_ID in ${ENV_FILE}"
  echo ""
fi

echo -e "  ${CYAN}2.${RESET} Start your assistant:"
echo -e "     ${BOLD}${START_SCRIPT}${RESET}"
echo ""
echo -e "  ${CYAN}3.${RESET} Attach to the tmux session to verify it's running:"
echo -e "     ${BOLD}tmux attach -t ${AGENT_NAME}${RESET}"
echo ""
echo -e "  ${CYAN}4.${RESET} Customize your persona and config:"
echo -e "     ${BOLD}${CONFIG_REPO}/SOUL.md${RESET}"
echo -e "     ${BOLD}${CONFIG_REPO}/CLAUDE.md${RESET}"
echo ""
echo -e "  ${CYAN}5.${RESET} The assistant will start automatically on reboot."
echo -e "     To disable: remove the @reboot line from crontab -e"
echo ""
echo -e "${CYAN}  Docs: https://github.com/your-org/personal-ai-playbook${RESET}"
echo ""
