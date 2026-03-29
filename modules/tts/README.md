# TTS Module

Text-to-speech output for your personal AI assistant. Three backends, one dispatcher.

| Backend | Cost | API Key | Quality | Notes |
|---------|------|---------|---------|-------|
| `edge-tts` | Free | None | Good | Microsoft Edge neural voices. Best starting point. |
| `elevenlabs` | $0-$22/mo | Required | Excellent | Voice cloning, character voices. Most natural output. |
| `minimax` | Pay-per-use | Required | Very good | Strong multilingual, competitive pricing, custom voices. |

Set `TTS_BACKEND` in `.env` to switch. The `speak.sh` dispatcher handles the rest.

---

## Quick Start (edge-tts, 2 commands)

```bash
bash modules/tts/edge-tts/install.sh
modules/tts/speak.sh "Your briefing is ready."
```

No API key required. Works on headless servers.

---

## How It Works

`speak.sh` is the single entry point. It reads `TTS_BACKEND` from your environment and delegates to the appropriate backend script:

```
speak.sh "text" [output.mp3]
    |
    +-- TTS_BACKEND=edge-tts    -> edge-tts/speak.sh
    +-- TTS_BACKEND=elevenlabs  -> elevenlabs/speak.sh
    +-- TTS_BACKEND=minimax     -> minimax/speak.sh
```

If no output file is given, audio is written to a temp file and played immediately via `ffplay`, `mpv`, or `aplay` (whichever is found first).

---

## Voice Customization

### edge-tts

Set `TTS_VOICE` in `.env`:

```bash
export TTS_VOICE="en-US-AvaNeural"     # female (default)
export TTS_VOICE="en-US-AndrewNeural"  # male, natural
export TTS_VOICE="en-US-GuyNeural"     # neutral
```

List all available voices:

```bash
modules/tts/.tts-venv/bin/edge-tts --list-voices | grep en-US
```

### elevenlabs

Set `VOICE_ID` in `.env`. This is the only thing that makes your assistant sound unique. Clone a voice once at [elevenlabs.io/app/voice-library](https://elevenlabs.io/app/voice-library), copy the Voice ID, and it persists forever:

```bash
export VOICE_ID="your-voice-id-here"
export ELEVENLABS_API_KEY="your-api-key-here"
export ELEVENLABS_MODEL="eleven_turbo_v2_5"  # or eleven_multilingual_v2 for best quality
```

### minimax

Set `MINIMAX_VOICE_ID` in `.env`. Use a built-in voice ID or a cloned voice from your MiniMax account:

```bash
export MINIMAX_VOICE_ID="male-qn-qingse"  # default built-in
export MINIMAX_API_KEY="your-api-key-here"
export MINIMAX_GROUP_ID="your-group-id-here"
```

---

## Integration Example

An agent or cron script can call `speak.sh` directly:

```bash
source ~/.env
~/personal-ai-playbook/modules/tts/speak.sh "Your morning briefing is ready."
```

Or capture audio to a file for later playback:

```bash
source ~/.env
~/personal-ai-playbook/modules/tts/speak.sh "Meeting in 10 minutes." /tmp/reminder.mp3
aplay /tmp/reminder.mp3
```

---

## Offline Alternative

For fully offline TTS with higher quality than edge-tts, consider [Kokoro](https://github.com/hexgrad/kokoro). It runs locally without any network calls, at the cost of a heavier model download (~500MB). Kokoro is not included in this module but uses the same `speak.sh` dispatcher pattern — add a `kokoro/speak.sh` backend and set `TTS_BACKEND=kokoro`.
