# ElevenLabs Backend

Premium neural TTS with voice cloning and character voices. $0-$22/mo plans. Voice IDs are portable: clone a voice once, use it by ID forever.

---

## Setup

```bash
bash modules/tts/elevenlabs/install.sh
```

This installs the ElevenLabs Python SDK into `modules/tts/.tts-venv` and writes `ELEVENLABS_API_KEY` and `VOICE_ID` stubs to your `.env`.

---

## API Key

1. Create an account at [elevenlabs.io](https://elevenlabs.io)
2. Go to [elevenlabs.io/app/speech-synthesis](https://elevenlabs.io/app/speech-synthesis)
3. Copy your API key from the profile menu
4. Set it in `.env`:

```bash
export ELEVENLABS_API_KEY="your-api-key-here"
```

Free plan: 10,000 characters/month. Paid plans start at $5/mo.

---

## Voice ID

`VOICE_ID` is the only thing that makes your assistant sound unique. Set it once and `speak.sh` handles the rest.

To find or clone a voice:

1. Visit [elevenlabs.io/app/voice-library](https://elevenlabs.io/app/voice-library)
2. Browse pre-made voices or clone your own
3. Click a voice, copy the Voice ID from the URL or detail panel
4. Set it in `.env`:

```bash
export VOICE_ID="your-voice-id-here"
```

---

## Model Options

Set `ELEVENLABS_MODEL` in `.env` to control quality vs. latency:

```bash
export ELEVENLABS_MODEL="eleven_turbo_v2_5"      # lowest latency and cost (default)
export ELEVENLABS_MODEL="eleven_multilingual_v2"  # highest quality, multilingual
```

For most personal assistant use cases, `eleven_turbo_v2_5` is the right choice.

---

## Usage

```bash
# Play immediately
TTS_BACKEND=elevenlabs modules/tts/speak.sh "Hello world"

# Write to file
TTS_BACKEND=elevenlabs modules/tts/speak.sh "Hello world" /tmp/out.mp3
```

Or set `TTS_BACKEND=elevenlabs` in `.env` to make it the default.
