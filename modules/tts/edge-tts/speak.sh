#!/usr/bin/env bash
# edge-tts backend — sourced by modules/tts/speak.sh
# Requires: edge-tts installed in .tts-venv
# Env: TTS_VOICE (default: en-US-AvaNeural)

VOICE="${TTS_VOICE:-en-US-AvaNeural}"
"$SCRIPTS_DIR/.tts-venv/bin/edge-tts" --voice "$VOICE" --text "$TEXT" --write-media "$OUTPUT"
