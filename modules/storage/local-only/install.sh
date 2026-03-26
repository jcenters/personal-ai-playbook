#!/usr/bin/env bash
# modules/storage/local-only/install.sh
# Sets up local-only markdown note storage for personal-ai-playbook.
# No cloud sync. Notes live entirely on this machine.
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
NOTES_DIR="${DEPLOY_BASE}/.${AGENT_NAME}/notes"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[local-only] $*"; }
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

log "Installing local-only note storage"
log "  DEPLOY_BASE : ${DEPLOY_BASE}"
log "  AGENT_NAME  : ${AGENT_NAME}"
echo ""

# 1. Create notes directory structure
log "Creating notes directory structure..."

mkdir -p "${NOTES_DIR}"
mkdir -p "${NOTES_DIR}/daily"
mkdir -p "${NOTES_DIR}/topics"
mkdir -p "${NOTES_DIR}/people"
mkdir -p "${NOTES_DIR}/projects"

ok "Created: ${NOTES_DIR}/"
ok "Created: ${NOTES_DIR}/daily/     — date-stamped daily notes"
ok "Created: ${NOTES_DIR}/topics/    — evergreen topic notes"
ok "Created: ${NOTES_DIR}/people/    — notes about people/contacts"
ok "Created: ${NOTES_DIR}/projects/  — project-specific notes"

# 2. Write a README inside the notes directory explaining the structure
cat > "${NOTES_DIR}/README.md" << MD
# Local Notes

This directory is managed by **${AGENT_NAME}** (personal-ai-playbook local-only storage module).

All notes are plain markdown files stored on this machine only.
**No cloud sync is configured.** Back up this directory manually or via your own backup tooling.

## Directory Structure

\`\`\`
notes/
  daily/        Date-stamped notes (YYYY-MM-DD.md)
                Written during daily check-ins and conversations.

  topics/       Evergreen reference notes by topic.
                Filename format: slug-topic.md
                Example: linux-commands.md, meal-planning.md

  people/       Notes about people and contacts.
                Filename format: firstname-lastname.md

  projects/     Project-specific notes and status.
                Each project gets its own file or subdirectory.
\`\`\`

## How the Agent Uses These Files

- **Reading**: The agent reads relevant files before answering questions
  that match a topic or person.
- **Writing**: When you say "make a note", "remember this", or "save this",
  the agent appends to the appropriate file.
- **Daily notes**: Each day's check-in summary is written to \`daily/YYYY-MM-DD.md\`.

## Backup Recommendation

This data is local only. To back it up:

\`\`\`bash
# Simple rsync to an external drive or remote server:
rsync -avz ${NOTES_DIR}/ /mnt/backup/notes/

# Or include it in your existing backup routine.
\`\`\`

## Privacy

Nothing in this directory is sent anywhere unless you explicitly share it.
The agent reads these files locally when forming responses.
MD

ok "Created notes README"

# 3. Write initial daily note
TODAY=$(date +%Y-%m-%d)
DAILY_NOTE="${NOTES_DIR}/daily/${TODAY}.md"
if [[ ! -f "$DAILY_NOTE" ]]; then
  cat > "$DAILY_NOTE" << MD
# ${TODAY}

<!-- This file was created by the local-only storage module on install. -->
<!-- The agent will append notes here throughout the day. -->

## Setup

Local-only storage module installed for ${AGENT_NAME}.
Notes directory: ${NOTES_DIR}

MD
  ok "Created today's daily note: ${DAILY_NOTE}"
fi

# 4. Write env var
log "Updating .env..."
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
env_set "NOTES_DIR" "${NOTES_DIR}"

# 5. Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Local-Only Storage — Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Storage type: LOCAL ONLY — no cloud sync"
echo ""
echo "  All memory is stored as plain markdown files."
echo "  Nothing leaves this machine unless you configure backup separately."
echo ""
echo "  Directory layout:"
echo ""
echo "    ${NOTES_DIR}/"
echo "    ├── daily/     — daily check-in notes (YYYY-MM-DD.md)"
echo "    ├── topics/    — evergreen topic notes"
echo "    ├── people/    — notes about contacts"
echo "    ├── projects/  — project status and notes"
echo "    └── README.md  — full directory documentation"
echo ""
echo "  Env var added to .env:"
echo "    NOTES_DIR=${NOTES_DIR}"
echo ""
echo "  Usage via Telegram:"
echo "    make a note: [whatever you want to remember]"
echo "    remember that [person] prefers [preference]"
echo "    what do I know about [topic]?"
echo "    save this to my project notes: [project name] — [note]"
echo ""
echo "  Backup recommendation:"
echo "    rsync -avz ${NOTES_DIR}/ /your/backup/location/"
echo ""
echo "  IMPORTANT: This module provides no automatic backup."
echo "  Add the notes directory to your backup routine."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
