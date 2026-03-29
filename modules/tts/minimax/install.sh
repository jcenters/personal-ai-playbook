#!/usr/bin/env bash
# minimax install script
# Installs the MiniMax TTS backend (pay-per-use, requires API key + group ID)
# No SDK needed — pure curl
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tts"
ENV_FILE="${DEPLOY_BASE:-.}/.env"

echo ""
echo "  Installing MiniMax backend..."

# Verify curl is available
if ! command -v curl &>/dev/null; then
  echo "  Error: curl is required but not found. Install curl and re-run." >&2
  exit 1
fi

# Verify python3 is available (used for JSON encoding/decoding)
if ! command -v python3 &>/dev/null; then
  echo "  Error: python3 is required but not found." >&2
  exit 1
fi

# chmod +x the backend speak.sh
chmod +x "${SCRIPTS_DIR}/minimax/speak.sh"
chmod +x "${SCRIPTS_DIR}/speak.sh"

# Write env var stubs if not already set
touch "$ENV_FILE"

if ! grep -q "^export MINIMAX_API_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# MiniMax TTS" >> "$ENV_FILE"
  echo 'export MINIMAX_API_KEY=""' >> "$ENV_FILE"
  echo "  Added MINIMAX_API_KEY stub to ${ENV_FILE}"
fi

if ! grep -q "^export MINIMAX_GROUP_ID=" "$ENV_FILE" 2>/dev/null; then
  echo 'export MINIMAX_GROUP_ID=""' >> "$ENV_FILE"
  echo "  Added MINIMAX_GROUP_ID stub to ${ENV_FILE}"
fi

if ! grep -q "^export MINIMAX_VOICE_ID=" "$ENV_FILE" 2>/dev/null; then
  echo 'export MINIMAX_VOICE_ID="male-qn-qingse"' >> "$ENV_FILE"
  echo "  Added MINIMAX_VOICE_ID=male-qn-qingse to ${ENV_FILE}"
fi

if ! grep -q "^export TTS_BACKEND=" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# TTS backend" >> "$ENV_FILE"
  echo 'export TTS_BACKEND="minimax"' >> "$ENV_FILE"
fi

# Check for required env vars (warn, don't fail)
if [[ -z "${MINIMAX_API_KEY:-}" ]]; then
  echo ""
  echo "  Warning: MINIMAX_API_KEY is not set."
  echo "    Get credentials at https://platform.minimaxi.com"
  echo "    Then set MINIMAX_API_KEY and MINIMAX_GROUP_ID in ${ENV_FILE}"
fi

if [[ -z "${MINIMAX_GROUP_ID:-}" ]]; then
  echo ""
  echo "  Warning: MINIMAX_GROUP_ID is not set."
  echo "    Find your Group ID in the MiniMax platform dashboard."
fi

echo ""
echo "  MiniMax backend installed. Usage:"
echo "    TTS_BACKEND=minimax ${SCRIPTS_DIR}/speak.sh 'Hello world'"
echo "    ${SCRIPTS_DIR}/speak.sh 'Hello world' /tmp/output.mp3"
