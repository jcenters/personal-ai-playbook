#!/usr/bin/env bash
# modules/agents/researcher/install.sh
# Sets up the research sub-agent for personal-ai-playbook.
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
RESEARCH_DIR="${DEPLOY_BASE}/.${AGENT_NAME}/research"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[researcher] $*"; }
ok()   { echo "  [ok] $*"; }
warn() { echo "  [warn] $*"; }

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

env_clear() {
  local key="$1"
  if grep -q "^export ${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "/^export ${key}=/d" "$ENV_FILE"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_env

log "Installing researcher sub-agent"
log "  DEPLOY_BASE : ${DEPLOY_BASE}"
log "  AGENT_NAME  : ${AGENT_NAME}"
echo ""

# 1. Prompt for optional Brave Search API key
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Brave Search API (optional)"
echo ""
echo "  The researcher can query the live web using the Brave Search API."
echo "  Without a key, it works from Claude's training knowledge only."
echo ""
echo "  Get a free API key at: https://api.search.brave.com/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if already set in environment
EXISTING_KEY="${BRAVE_API_KEY:-}"
if [[ -z "$EXISTING_KEY" ]]; then
  EXISTING_KEY=$(grep -oP "(?<=^export BRAVE_API_KEY=).*" "$ENV_FILE" 2>/dev/null | tr -d '"' || true)
fi

if [[ -n "$EXISTING_KEY" ]]; then
  echo "  Existing BRAVE_API_KEY found in environment."
  read -r -p "  Keep it? (yes/no) [yes]: " KEEP_KEY
  KEEP_KEY="${KEEP_KEY:-yes}"
  if [[ "$KEEP_KEY" =~ ^[Nn] ]]; then
    read -r -s -p "  New Brave API key (leave blank to skip): " BRAVE_API_KEY
    echo ""
  else
    BRAVE_API_KEY="$EXISTING_KEY"
    ok "Keeping existing BRAVE_API_KEY"
  fi
else
  read -r -s -p "  Brave API key (leave blank to skip): " BRAVE_API_KEY
  echo ""
fi

BRAVE_ENABLED=false
if [[ -n "$BRAVE_API_KEY" ]]; then
  BRAVE_ENABLED=true
  ok "Brave Search will be enabled"
else
  warn "No Brave API key provided — web search will not be available"
  warn "The researcher will work from Claude's training knowledge"
fi

# 2. Create research notes directory
log "Creating research directory..."
mkdir -p "${RESEARCH_DIR}/notes"
mkdir -p "${RESEARCH_DIR}/saved"

if [[ ! -f "${RESEARCH_DIR}/index.md" ]]; then
  cat > "${RESEARCH_DIR}/index.md" << 'MD'
# Research Index

<!-- The researcher appends entries here when saving research to disk. -->
<!-- Format: -->
<!-- - [YYYY-MM-DD] [Topic]: notes/YYYY-MM-DD-slug.md -->

MD
  ok "Created research index: ${RESEARCH_DIR}/index.md"
fi

ok "Research directory ready: ${RESEARCH_DIR}"

# 3. Write env vars
log "Updating .env..."
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"

if [[ "$BRAVE_ENABLED" == "true" ]]; then
  env_set "BRAVE_API_KEY" "\"${BRAVE_API_KEY}\""
else
  # Remove any stale key so the agent doesn't assume it has web access
  env_clear "BRAVE_API_KEY"
fi

env_set "RESEARCH_DIR" "${RESEARCH_DIR}"

# 4. Build system prompt snippet based on web access availability
if [[ "$BRAVE_ENABLED" == "true" ]]; then
  WEB_NOTE="You have access to live web search via the Brave Search API (BRAVE_API_KEY is set). Use it when the user asks for current information, recent events, or anything that may have changed since your training cutoff. Cite your sources."
else
  WEB_NOTE="You do NOT have a Brave API key configured, so you cannot perform live web searches. Work from your training knowledge. Clearly state when information may be outdated and suggest the user verify time-sensitive details."
fi

NOTES_NOTE="Save important research to ${RESEARCH_DIR}/notes/ as dated markdown files and update the index at ${RESEARCH_DIR}/index.md."

# 5. Write agent definition to agents.json
log "Writing agent definition to agents.json..."
mkdir -p "$AGENTS_CONFIG_DIR"

AGENT_DEF=$(cat << JSON
{
  "name": "researcher",
  "description": "Deep-dives on topics, synthesizes information, and saves findings as notes. Web search ${BRAVE_ENABLED}.",
  "trigger_phrases": ["research", "look up", "find out", "what is", "explain", "summarize", "compare", "investigate", "who is", "how does", "ask the researcher"],
  "model_tier": "sonnet",
  "web_search_enabled": ${BRAVE_ENABLED},
  "system_prompt_snippet": "You are a rigorous research assistant. ${WEB_NOTE} When you research a topic: (1) state what you found and from where, (2) distinguish facts from inference, (3) flag any conflicting information. ${NOTES_NOTE} Keep notes well-structured with headings, sources, and a summary section. When the user says 'save this' or 'keep a note on this', write the file and confirm.",
  "env_vars": ["BRAVE_API_KEY", "RESEARCH_DIR"],
  "data_dir": "${RESEARCH_DIR}"
}
JSON
)

if [[ ! -f "$AGENTS_JSON" ]]; then
  echo "[]" > "$AGENTS_JSON"
  ok "Created new agents.json"
fi

python3 - "$AGENTS_JSON" "$AGENT_DEF" << 'PYEOF'
import json, sys
path = sys.argv[1]
new_entry = json.loads(sys.argv[2])
with open(path) as f:
    agents = json.load(f)
agents = [a for a in agents if a.get("name") != "researcher"]
agents.append(new_entry)
with open(path, "w") as f:
    json.dump(agents, f, indent=2)
print("  [ok] researcher entry written to agents.json")
PYEOF

# 6. Print usage instructions
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Researcher Agent — Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Web search: $(if [[ "$BRAVE_ENABLED" == "true" ]]; then echo "ENABLED (Brave API)"; else echo "DISABLED (no API key)"; fi)"
echo ""
echo "  How to invoke via Telegram:"
echo ""
echo "    research [topic]"
echo "    look up the best practices for Docker security"
echo "    ask the researcher to explain how LSTMs work"
echo "    compare PostgreSQL and SQLite for a small app"
echo "    who is [person name] and what are they known for?"
echo "    research this and save a note: [topic]"
echo ""
echo "  Saved research:"
echo "    Notes: ${RESEARCH_DIR}/notes/"
echo "    Index: ${RESEARCH_DIR}/index.md"
echo ""
echo "  Env vars added to .env:"
echo "    RESEARCH_DIR=${RESEARCH_DIR}"
if [[ "$BRAVE_ENABLED" == "true" ]]; then
echo "    BRAVE_API_KEY=[set]"
fi
echo ""
echo "  Agent config updated at:"
echo "    ${AGENTS_JSON}"
echo ""
if [[ "$BRAVE_ENABLED" == "false" ]]; then
echo "  To add Brave web search later:"
echo "    1. Get a key at https://api.search.brave.com/"
echo "    2. Add to .env: export BRAVE_API_KEY=\"your_key\""
echo "    3. Re-run this install script"
echo ""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
