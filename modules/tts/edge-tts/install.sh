#!/usr/bin/env bash
# edge-tts install script
# Installs the Microsoft Edge neural TTS backend (free, no API key required)
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tts"
VENV_DIR="${SCRIPTS_DIR}/.tts-venv"
ENV_FILE="${DEPLOY_BASE:-.}/.env"

echo ""
echo "  Installing edge-tts backend..."

# Create venv if it doesn't exist
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
  echo "  Created venv: ${VENV_DIR}"
fi

# Install edge-tts into venv
"${VENV_DIR}/bin/pip" install --quiet --upgrade edge-tts
echo "  Installed edge-tts into ${VENV_DIR}"

# Check for ffmpeg/ffplay (optional, for playback)
if command -v ffplay &>/dev/null; then
  echo "  ffplay found — audio playback available"
elif command -v mpv &>/dev/null; then
  echo "  mpv found — audio playback available"
elif command -v aplay &>/dev/null; then
  echo "  aplay found — audio playback available"
else
  echo "  Warning: no audio player found (ffplay/mpv/aplay). Install one for speak.sh playback."
  echo "    Ubuntu/Debian: apt install ffmpeg"
fi

# chmod +x the backend speak.sh
chmod +x "${SCRIPTS_DIR}/edge-tts/speak.sh"
chmod +x "${SCRIPTS_DIR}/speak.sh"

# Write env vars if not already set
touch "$ENV_FILE"
if ! grep -q "^export TTS_BACKEND=" "$ENV_FILE" 2>/dev/null; then
  echo "" >> "$ENV_FILE"
  echo "# TTS backend" >> "$ENV_FILE"
  echo 'export TTS_BACKEND="edge-tts"' >> "$ENV_FILE"
  echo "  Set TTS_BACKEND=edge-tts in ${ENV_FILE}"
fi

if ! grep -q "^export TTS_VOICE=" "$ENV_FILE" 2>/dev/null; then
  echo 'export TTS_VOICE="en-US-AvaNeural"' >> "$ENV_FILE"
  echo "  Set TTS_VOICE=en-US-AvaNeural in ${ENV_FILE}"
fi

echo ""
echo "  edge-tts installed. Usage:"
echo "    ${SCRIPTS_DIR}/speak.sh 'Hello world'"
echo "    ${SCRIPTS_DIR}/speak.sh 'Hello world' /tmp/output.mp3"
echo ""
echo "  Browse voices:"
echo "    ${VENV_DIR}/bin/edge-tts --list-voices | grep en-US"
