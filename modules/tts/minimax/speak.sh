#!/usr/bin/env bash
# minimax backend — sourced by modules/tts/speak.sh
# Requires: MINIMAX_API_KEY and MINIMAX_GROUP_ID in env
# Env: MINIMAX_API_KEY, MINIMAX_GROUP_ID, MINIMAX_VOICE_ID

API_KEY="${MINIMAX_API_KEY:?Set MINIMAX_API_KEY in .env}"
GROUP_ID="${MINIMAX_GROUP_ID:?Set MINIMAX_GROUP_ID in .env}"
VOICE_ID="${MINIMAX_VOICE_ID:-male-qn-qingse}"

RESPONSE=$(curl -sS \
  --request POST \
  --url "https://api.minimaxi.chat/v1/t2a_v2?GroupId=${GROUP_ID}" \
  --header "Authorization: Bearer ${API_KEY}" \
  --header "Content-Type: application/json" \
  --data "{
    \"model\": \"speech-02-hd\",
    \"text\": $(echo "$TEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
    \"voice_setting\": {\"voice_id\": \"${VOICE_ID}\", \"speed\": 1.0, \"vol\": 1.0, \"pitch\": 0}
  }")

# Extract base64 audio and decode
echo "$RESPONSE" | python3 -c "
import json, sys, base64
d = json.load(sys.stdin)
audio_b64 = d['data']['audio']
sys.stdout.buffer.write(base64.b64decode(audio_b64))
" > "$OUTPUT"
