#!/usr/bin/env bash
# elevenlabs backend — sourced by modules/tts/speak.sh
# Requires: ELEVENLABS_API_KEY and VOICE_ID in env
# Env: VOICE_ID, ELEVENLABS_API_KEY, ELEVENLABS_MODEL

VOICE_ID="${VOICE_ID:?Set VOICE_ID in .env — find it at elevenlabs.io/app/voice-library}"
API_KEY="${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY in .env}"
MODEL="${ELEVENLABS_MODEL:-eleven_turbo_v2_5}"

curl -sS \
  --request POST \
  --url "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
  --header "xi-api-key: ${API_KEY}" \
  --header "Content-Type: application/json" \
  --data "{\"text\": $(echo "$TEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'), \"model_id\": \"${MODEL}\"}" \
  --output "$OUTPUT"
