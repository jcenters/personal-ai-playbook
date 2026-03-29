#!/usr/bin/env bash
# speak.sh — dispatch TTS to configured backend
# Usage: speak.sh "Text to speak" [output.mp3]
# If output file not given, plays via ffplay/mpv/aplay (whichever is available)
# Env: TTS_BACKEND (edge-tts|elevenlabs|minimax), VOICE_ID, TTS_VOICE

set -euo pipefail

TEXT="${1:-}"
OUTPUT="${2:-}"
BACKEND="${TTS_BACKEND:-edge-tts}"
SCRIPTS_DIR="$(dirname "$0")"

if [[ -z "$TEXT" ]]; then
  echo "Usage: speak.sh 'text' [output.mp3]" >&2
  exit 1
fi

# Temp file if no output specified
PLAY_AFTER=false
if [[ -z "$OUTPUT" ]]; then
  OUTPUT=$(mktemp --suffix=.mp3)
  PLAY_AFTER=true
fi

case "$BACKEND" in
  edge-tts)
    source "$SCRIPTS_DIR/edge-tts/speak.sh"
    ;;
  elevenlabs)
    source "$SCRIPTS_DIR/elevenlabs/speak.sh"
    ;;
  minimax)
    source "$SCRIPTS_DIR/minimax/speak.sh"
    ;;
  *)
    echo "Unknown TTS_BACKEND: $BACKEND" >&2
    exit 1
    ;;
esac

if [[ "${PLAY_AFTER}" == true ]]; then
  if command -v ffplay &>/dev/null; then
    ffplay -nodisp -autoexit "$OUTPUT" >/dev/null 2>&1
  elif command -v mpv &>/dev/null; then
    mpv --no-terminal "$OUTPUT"
  elif command -v aplay &>/dev/null; then
    aplay "$OUTPUT" 2>/dev/null
  fi
  rm -f "$OUTPUT"
fi
