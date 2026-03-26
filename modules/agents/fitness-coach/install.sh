#!/usr/bin/env bash
# modules/agents/fitness-coach/install.sh
# Sets up the fitness coach sub-agent for personal-ai-playbook.
#
# Usage: DEPLOY_BASE=~/.max AGENT_NAME=max bash install.sh
# Required env vars:
#   DEPLOY_BASE  — root deploy directory (e.g. ~/.max)
#   AGENT_NAME   — the persona name (e.g. max)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
DEPLOY_BASE="${DEPLOY_BASE:-$HOME/.max}"
AGENT_NAME="${AGENT_NAME:-max}"
ENV_FILE="${DEPLOY_BASE}/.env"
AGENTS_CONFIG_DIR="${DEPLOY_BASE}/${AGENT_NAME}-config"
AGENTS_JSON="${AGENTS_CONFIG_DIR}/agents.json"
FITNESS_DIR="${DEPLOY_BASE}/.${AGENT_NAME}/fitness"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[fitness-coach] $*"; }
info() { echo "  $*"; }
ok()   { echo "  [ok] $*"; }

require_env() {
  if [[ -z "${DEPLOY_BASE:-}" || -z "${AGENT_NAME:-}" ]]; then
    echo "ERROR: DEPLOY_BASE and AGENT_NAME must be set."
    echo "  Example: DEPLOY_BASE=~/.max AGENT_NAME=max bash install.sh"
    exit 1
  fi
}

env_set() {
  local key="$1" val="$2"
  if grep -q "^export ${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^export ${key}=.*|export ${key}=${val}|" "$ENV_FILE"
    ok "Updated ${key} in .env"
  else
    echo "export ${key}=${val}" >> "$ENV_FILE"
    ok "Added ${key} to .env"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_env

log "Installing fitness-coach sub-agent"
log "  DEPLOY_BASE : ${DEPLOY_BASE}"
log "  AGENT_NAME  : ${AGENT_NAME}"
echo ""

# 1. Create fitness log directory
log "Creating fitness log directory..."
mkdir -p "$FITNESS_DIR"
ok "Directory ready: ${FITNESS_DIR}"

# Create a starter log file if none exists
if [[ ! -f "${FITNESS_DIR}/workouts.md" ]]; then
  cat > "${FITNESS_DIR}/workouts.md" << 'MD'
# Workout Log

<!-- Entries are appended here by the fitness coach. Format: -->
<!-- ## YYYY-MM-DD — [Workout Name] -->
<!-- - exercise: sets x reps @ weight -->
<!-- Notes: ... -->
MD
  ok "Created starter log: ${FITNESS_DIR}/workouts.md"
fi

if [[ ! -f "${FITNESS_DIR}/progress.md" ]]; then
  cat > "${FITNESS_DIR}/progress.md" << 'MD'
# Progress Tracking

<!-- Weekly summaries and milestone notes go here. -->
MD
  ok "Created progress file: ${FITNESS_DIR}/progress.md"
fi

# 2. Write env var
log "Updating .env..."
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
env_set "FITNESS_LOG_DIR" "${FITNESS_DIR}"

# 3. Write agent definition to agents.json
log "Writing agent definition to agents.json..."
mkdir -p "$AGENTS_CONFIG_DIR"

AGENT_DEF=$(cat << JSON
{
  "name": "fitness-coach",
  "description": "Plans workouts, tracks progress, and provides fitness advice. Logs sessions to FITNESS_LOG_DIR.",
  "trigger_phrases": ["coach,", "fitness", "workout", "exercise", "training", "gym"],
  "model_tier": "sonnet",
  "system_prompt_snippet": "You are a knowledgeable, encouraging fitness coach. You assign structured workouts, track the user's progress in the fitness log at ${FITNESS_DIR}, and adapt plans based on past performance. When logging a workout, append a dated entry to workouts.md. Always be specific: sets, reps, rest periods, and cues. If the user has not shared their goals, ask before assigning a program.",
  "env_vars": ["FITNESS_LOG_DIR"],
  "data_dir": "${FITNESS_DIR}"
}
JSON
)

if [[ ! -f "$AGENTS_JSON" ]]; then
  echo "[]" > "$AGENTS_JSON"
  ok "Created new agents.json"
fi

# Remove existing fitness-coach entry if present, then append
python3 - "$AGENTS_JSON" "$AGENT_DEF" << 'PYEOF'
import json, sys
path = sys.argv[1]
new_entry = json.loads(sys.argv[2])
with open(path) as f:
    agents = json.load(f)
agents = [a for a in agents if a.get("name") != "fitness-coach"]
agents.append(new_entry)
with open(path, "w") as f:
    json.dump(agents, f, indent=2)
print("  [ok] fitness-coach entry written to agents.json")
PYEOF

# 4. Print usage instructions
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Fitness Coach — Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  How to invoke via Telegram:"
echo ""
echo "    coach, assign me a workout"
echo "    coach, I just finished a 30-minute run"
echo "    coach, what's my progress this week?"
echo "    coach, I need a rest day plan"
echo ""
echo "  Data lives at:"
echo "    ${FITNESS_DIR}/workouts.md    — session log"
echo "    ${FITNESS_DIR}/progress.md   — weekly summaries"
echo ""
echo "  Env var added to .env:"
echo "    FITNESS_LOG_DIR=${FITNESS_DIR}"
echo ""
echo "  Agent config updated at:"
echo "    ${AGENTS_JSON}"
echo ""
echo "  Tip: Start by telling the coach your goals and current fitness level."
echo "  Example: \"coach, my goal is to lose 20 lbs and I can work out 3x/week\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
