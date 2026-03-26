#!/usr/bin/env bash
# modules/agents/system-health/install.sh
# Sets up the system health monitor sub-agent for personal-ai-playbook.
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
HEALTH_CONFIG_DIR="${DEPLOY_BASE}/.${AGENT_NAME}/system-health"
TOOLS_CONFIG="${HEALTH_CONFIG_DIR}/available-tools.json"
LOG_FILE="${HEALTH_CONFIG_DIR}/health.log"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()   { echo "[system-health] $*"; }
ok()    { echo "  [ok] $*"; }
found() { echo "  [found] $*"; }
skip()  { echo "  [skip] $*"; }

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

check_tool() {
  local tool="$1"
  if command -v "$tool" &>/dev/null; then
    found "$tool ($(command -v "$tool"))"
    echo "true"
  else
    skip "$tool not found"
    echo "false"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_env

log "Installing system-health sub-agent"
log "  DEPLOY_BASE : ${DEPLOY_BASE}"
log "  AGENT_NAME  : ${AGENT_NAME}"
echo ""

# 1. Create config directory
mkdir -p "$HEALTH_CONFIG_DIR"
touch "$LOG_FILE"
ok "Created health config dir: ${HEALTH_CONFIG_DIR}"

# 2. Detect available system tools
echo ""
log "Detecting available system tools..."
echo ""

HAS_DF=$(check_tool "df")
HAS_FREE=$(check_tool "free")
HAS_SYSTEMCTL=$(check_tool "systemctl")
HAS_BREW=$(check_tool "brew")
HAS_APT=$(check_tool "apt")
HAS_YUM=$(check_tool "yum")
HAS_DNF=$(check_tool "dnf")
HAS_UPTIME=$(check_tool "uptime")
HAS_TOP=$(check_tool "top")
HAS_PS=$(check_tool "ps")
HAS_NETSTAT=$(check_tool "netstat")
HAS_SS=$(check_tool "ss")
HAS_PING=$(check_tool "ping")
HAS_CURL=$(check_tool "curl")
HAS_JOURNALCTL=$(check_tool "journalctl")
HAS_DOCKER=$(check_tool "docker")
HAS_UNAME=$(check_tool "uname")

echo ""

# 3. Save tools config as JSON
log "Saving available tools config to ${TOOLS_CONFIG}..."

cat > "$TOOLS_CONFIG" << JSON
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname -s 2>/dev/null || echo unknown)",
  "os": "$(uname -s 2>/dev/null || echo unknown)",
  "os_version": "$(uname -r 2>/dev/null || echo unknown)",
  "arch": "$(uname -m 2>/dev/null || echo unknown)",
  "tools": {
    "disk": {
      "df": ${HAS_DF}
    },
    "memory": {
      "free": ${HAS_FREE}
    },
    "services": {
      "systemctl": ${HAS_SYSTEMCTL},
      "journalctl": ${HAS_JOURNALCTL},
      "docker": ${HAS_DOCKER}
    },
    "package_managers": {
      "brew": ${HAS_BREW},
      "apt": ${HAS_APT},
      "yum": ${HAS_YUM},
      "dnf": ${HAS_DNF}
    },
    "process": {
      "uptime": ${HAS_UPTIME},
      "top": ${HAS_TOP},
      "ps": ${HAS_PS}
    },
    "network": {
      "netstat": ${HAS_NETSTAT},
      "ss": ${HAS_SS},
      "ping": ${HAS_PING},
      "curl": ${HAS_CURL}
    },
    "system": {
      "uname": ${HAS_UNAME}
    }
  },
  "checks_enabled": {
    "disk_usage": ${HAS_DF},
    "memory_usage": ${HAS_FREE},
    "service_status": ${HAS_SYSTEMCTL},
    "system_logs": ${HAS_JOURNALCTL},
    "network_connectivity": ${HAS_CURL},
    "process_list": ${HAS_PS},
    "package_updates": $(if [[ "$HAS_BREW" == "true" || "$HAS_APT" == "true" || "$HAS_YUM" == "true" || "$HAS_DNF" == "true" ]]; then echo "true"; else echo "false"; fi)
  }
}
JSON

ok "Tools config saved"

# 4. Write env var
log "Updating .env..."
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
env_set "SYSTEM_HEALTH_CONFIG" "${TOOLS_CONFIG}"
env_set "SYSTEM_HEALTH_LOG" "${LOG_FILE}"

# 5. Write agent definition to agents.json
log "Writing agent definition to agents.json..."
mkdir -p "$AGENTS_CONFIG_DIR"

AGENT_DEF=$(cat << JSON
{
  "name": "system-health",
  "description": "Monitors system health: disk, memory, services, logs, and network. Reports issues proactively. Reads tool availability from SYSTEM_HEALTH_CONFIG.",
  "trigger_phrases": ["system", "health", "disk", "memory", "cpu", "services", "logs", "server", "monitor", "uptime", "storage"],
  "model_tier": "haiku",
  "system_prompt_snippet": "You are a system health monitor. You have access to the available tools listed in ${TOOLS_CONFIG}. Only use tools that are marked as available (true). When asked for a health check, report: disk usage (warn at >80%, alert at >90%), memory usage, any failed systemctl services, recent error-level log entries via journalctl, and network connectivity. Log each check with timestamp to ${LOG_FILE}. Keep reports concise — lead with any problems found. If everything is healthy, say so in one line, then give a brief summary of what was checked.",
  "env_vars": ["SYSTEM_HEALTH_CONFIG", "SYSTEM_HEALTH_LOG"],
  "data_dir": "${HEALTH_CONFIG_DIR}",
  "schedule": "0 2 * * *"
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
agents = [a for a in agents if a.get("name") != "system-health"]
agents.append(new_entry)
with open(path, "w") as f:
    json.dump(agents, f, indent=2)
print("  [ok] system-health entry written to agents.json")
PYEOF

# 6. Install 2 AM daily cron job
log "Installing daily 2 AM health check cron job..."

# Derive the command the main agent would use — fallback to a direct script call
CRON_SCRIPT="${DEPLOY_BASE}/scripts/run-agent.sh"
CRON_CMD="bash ${CRON_SCRIPT} system-health 'run your daily health check and send me a summary'"
CRON_LOG="${DEPLOY_BASE}/logs/system-health-cron.log"
mkdir -p "${DEPLOY_BASE}/logs"

CRON_LINE="0 2 * * * ${CRON_CMD} >> ${CRON_LOG} 2>&1 # personal-ai-playbook:system-health"

# Add to crontab if not already present
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING_CRON" | grep -q "personal-ai-playbook:system-health"; then
  ok "Cron job already present — skipping"
else
  (echo "$EXISTING_CRON"; echo "$CRON_LINE") | crontab -
  ok "Cron job added: daily at 2:00 AM"
fi

# 7. Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  System Health Agent — Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  What will be checked (based on tools found on this system):"
echo ""
[[ "$HAS_DF" == "true" ]]         && echo "    - Disk usage (alert at >80%)"
[[ "$HAS_FREE" == "true" ]]       && echo "    - Memory usage"
[[ "$HAS_SYSTEMCTL" == "true" ]]  && echo "    - Failed systemd services"
[[ "$HAS_JOURNALCTL" == "true" ]] && echo "    - Recent error-level system logs"
[[ "$HAS_PS" == "true" ]]         && echo "    - Running processes / CPU load"
[[ "$HAS_CURL" == "true" ]]       && echo "    - Network connectivity"
[[ "$HAS_DOCKER" == "true" ]]     && echo "    - Docker container status"
([[ "$HAS_BREW" == "true" ]] || [[ "$HAS_APT" == "true" ]] || [[ "$HAS_YUM" == "true" ]]) && \
                                     echo "    - Available package updates"
echo ""
echo "  Schedule:"
echo "    Daily at 2:00 AM (cron installed)"
echo "    Log: ${CRON_LOG}"
echo ""
echo "  On-demand via Telegram:"
echo "    how is the server doing?"
echo "    run a health check"
echo "    check disk space"
echo "    are any services down?"
echo ""
echo "  Config files:"
echo "    ${TOOLS_CONFIG}"
echo "    ${LOG_FILE}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
