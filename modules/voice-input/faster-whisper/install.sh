#!/usr/bin/env bash
# faster-whisper/install.sh
# Installs the whisper-auto.sh voice transcription script and its Python venv.
#
# Env vars:
#   DEPLOY_BASE  — base deployment directory (default: $HOME)
#   AGENT_NAME   — assistant name (default: max)
#   VENV_DIR     — where to create the Python venv (default: ~/whisper_venv)
#
# Usage:
#   DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-max}"
VENV_DIR="${VENV_DIR:-$HOME/whisper_venv}"

SCRIPTS_DIR="$DEPLOY_BASE/.$AGENT_NAME/scripts"
LOGS_DIR="$DEPLOY_BASE/.$AGENT_NAME/logs"
SCRIPT_PATH="$SCRIPTS_DIR/whisper-auto.sh"

echo "==> Installing faster-whisper voice transcription to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR" "$LOGS_DIR"

# Check for ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    echo "  ERROR: ffmpeg not found. Install it first:"
    echo "    sudo apt install ffmpeg   # Debian/Ubuntu"
    echo "    brew install ffmpeg       # macOS"
    exit 1
fi
echo "  ffmpeg: $(ffmpeg -version 2>&1 | head -1)"

# Check for Python 3.9+
PYTHON_BIN=$(command -v python3 || true)
if [[ -z "$PYTHON_BIN" ]]; then
    echo "  ERROR: python3 not found."
    exit 1
fi
PY_VERSION=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  python3: $PY_VERSION"

# Create venv and install faster-whisper
if [[ ! -d "$VENV_DIR" ]]; then
    echo "  Creating venv at $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
echo "  Installing faster-whisper into $VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet faster-whisper

# Write whisper-auto.sh
cat > "$SCRIPT_PATH" << 'SCRIPTEOF'
#!/bin/bash
# whisper-auto.sh - Auto-convert Telegram OGG/Opus to WAV and transcribe via faster-whisper
set -euo pipefail

INPUT_FILE="${1:-}"
if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: whisper-auto.sh <audio-file>" >&2
    exit 1
fi

LOCK_FILE="/tmp/whisper-auto.lock"
TEMP_WAV="/tmp/whisper_$$.wav"
VENV_DIR="${VENV_DIR:-$HOME/whisper_venv}"
MODEL="${WHISPER_MODEL:-small}"

PYTHON_SCRIPT=$(cat << 'PYEOF'
import sys, os
from faster_whisper import WhisperModel
audio_path = sys.argv[1]
model_name = sys.argv[2] if len(sys.argv) > 2 else "small"
model = WhisperModel(model_name, device="cpu", compute_type="int8")
segments, _ = model.transcribe(audio_path, beam_size=5)
for seg in segments:
    print(seg.text, end="", flush=True)
PYEOF
)

cleanup() { rm -f "$TEMP_WAV"; }
trap cleanup EXIT

exec 9>"$LOCK_FILE"
if ! flock -w 300 9; then
    echo "Error: lock timeout after 300s — another transcription is still running" >&2
    exit 1
fi

ffmpeg -y -i "$INPUT_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_WAV" >/dev/null 2>&1
timeout -k 5 60 "$VENV_DIR/bin/python3" -c "$PYTHON_SCRIPT" "$TEMP_WAV" "$MODEL"
SCRIPTEOF

chmod +x "$SCRIPT_PATH"

# Write VENV_DIR to .env if not already set
ENV_FILE="$DEPLOY_BASE/.env"
touch "$ENV_FILE"
if ! grep -q "^export VENV_DIR=" "$ENV_FILE" 2>/dev/null; then
    echo "export VENV_DIR=\"$VENV_DIR\"" >> "$ENV_FILE"
    echo "  Added VENV_DIR to $ENV_FILE"
fi

echo ""
echo "==> faster-whisper installed."
echo ""
echo "    Script:      $SCRIPT_PATH"
echo "    Venv:        $VENV_DIR"
echo "    Default model: small (override with WHISPER_MODEL env var)"
echo ""
echo "    Usage:"
echo "      whisper-auto.sh recording.ogg"
echo "      WHISPER_MODEL=medium whisper-auto.sh recording.ogg"
echo ""
echo "    Models: tiny (fastest), small (default), medium (most accurate)"
echo "    All transcription runs locally — no API key required."
echo ""
