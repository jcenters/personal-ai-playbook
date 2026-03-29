# edge-tts Backend

Microsoft Edge's neural TTS, accessible for free via the `edge-tts` Python package. No API key. 400+ voices. Works on headless servers.

---

## Setup

```bash
bash modules/tts/edge-tts/install.sh
```

This creates a Python venv at `modules/tts/.tts-venv`, installs `edge-tts`, and sets `TTS_BACKEND=edge-tts` and `TTS_VOICE=en-US-AvaNeural` in your `.env` (if not already set).

---

## Voice Selection

Set `TTS_VOICE` in `.env`:

```bash
export TTS_VOICE="en-US-AvaNeural"     # female, natural (default)
export TTS_VOICE="en-US-AndrewNeural"  # male, natural
export TTS_VOICE="en-US-GuyNeural"     # neutral
```

List all English (US) voices:

```bash
modules/tts/.tts-venv/bin/edge-tts --list-voices | grep en-US
```

Full voice list includes 400+ options across dozens of languages. All are neural voices (no robotic cadence).

---

## Usage

```bash
# Play immediately
modules/tts/speak.sh "Hello world"

# Write to file
modules/tts/speak.sh "Hello world" /tmp/out.mp3
```

---

## Offline Alternative

edge-tts requires a network connection (it streams from Microsoft's servers). For fully offline use, consider [Kokoro](https://github.com/hexgrad/kokoro) — a local neural TTS model that produces higher quality output at the cost of a ~500MB model download.
