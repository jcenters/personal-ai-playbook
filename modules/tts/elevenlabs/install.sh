#!/usr/bin/env bash
# elevenlabs install script
# Installs the ElevenLabs TTS backend (premium, requires API key)
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tts"
VENV_DIR="${SCRIPTS_DIR}/.tts-venv"
ENV_FILE="${DEPLOY_BASE:-.}/.env"

echo ""
echo "  Installing ElevenLabs backend..."

# Create venv if it doesn't exist
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
  echo "  Created venv: ${VENV_DIR}"
fi

# Install elevenlabs SDK into venv
"${VENV_DIR}/bin/pip" install --quiet --upgrade elevenlabs
echo "  Installed elevenlabs SDK into ${VENV_DIR}"

# chmod +x the backend speak.sh
chmod +x "${SCRIPTS_DIR}/elevenlabs/speak.sh"
chmod +x "${SCRIPTS_DIR}/speak.sh"

# Write env var stubs if not already set
touch "$ENV_FILE"

if ! grep -q "^export ELEVENLABS_API_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# ElevenLabs TTS" >> "$ENV_FILE"
  echo 'export ELEVENLABS_API_KEY=""' >> "$ENV_FILE"
  echo "  Added ELEVENLABS_API_KEY stub to ${ENV_FILE}"
fi

if ! grep -q "^export VOICE_ID=" "$ENV_FILE" 2>/dev/null; then
  echo 'export VOICE_ID=""' >> "$ENV_FILE"
  echo "  Added VOICE_ID stub to ${ENV_FILE}"
fi

if ! grep -q "^export TTS_BACKEND=" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# TTS backend" >> "$ENV_FILE"
  echo 'export TTS_BACKEND="elevenlabs"' >> "$ENV_FILE"
fi

# Check for required env vars (warn, don't fail)
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  echo ""
  echo "  Warning: ELEVENLABS_API_KEY is not set."
  echo "    Get your API key at https://elevenlabs.io/app/speech-synthesis"
  echo "    Then set it in ${ENV_FILE}"
fi

if [[ -z "${VOICE_ID:-}" ]]; then
  echo ""
  echo "  Warning: VOICE_ID is not set."
  echo "    Find or clone a voice at https://elevenlabs.io/app/voice-library"
  echo "    Copy the Voice ID and set it in ${ENV_FILE}"
fi

echo ""
echo "  ElevenLabs backend installed. Usage:"
echo "    TTS_BACKEND=elevenlabs ${SCRIPTS_DIR}/speak.sh 'Hello world'"
echo "    ${SCRIPTS_DIR}/speak.sh 'Hello world' /tmp/output.mp3"
