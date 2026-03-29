# faster-whisper

Local speech-to-text transcription for voice messages. Converts OGG/Opus audio (as received from Telegram) to text using [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — a CTranslate2-based reimplementation of OpenAI Whisper. Runs entirely on-device with no API key and no cloud dependency.

## What it does

- Accepts any audio file ffmpeg can decode (OGG, Opus, MP3, WAV, M4A)
- Converts to 16kHz mono WAV in a temp file
- Transcribes using faster-whisper on CPU with int8 quantization
- Prints the transcript to stdout
- Uses a file lock to serialize concurrent transcription requests (avoids memory spikes)

## Prerequisites

- **ffmpeg** — audio conversion. Install with `sudo apt install ffmpeg` (Linux) or `brew install ffmpeg` (macOS)
- **Python 3.9+** — required by faster-whisper
- **~500 MB disk space** for the `small` model (downloaded on first use to `~/.cache/huggingface/hub/`)

## Installation

```bash
DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh
```

Optional overrides:

```bash
DEPLOY_BASE=$HOME \
AGENT_NAME=max \
VENV_DIR=$HOME/whisper_venv \
bash install.sh
```

## Usage

```bash
# Basic
~/.max/scripts/whisper-auto.sh recording.ogg

# Choose a different model
WHISPER_MODEL=medium ~/.max/scripts/whisper-auto.sh recording.ogg
```

Output is plain text on stdout — suitable for piping or capture:

```bash
TRANSCRIPT=$(~/.max/scripts/whisper-auto.sh "$AUDIO_FILE")
```

## Model options

| Model | Size | Speed (CPU) | Accuracy |
|-------|------|-------------|----------|
| `tiny` | ~75 MB | Very fast | Basic |
| `small` | ~244 MB | Fast | Good — default |
| `medium` | ~769 MB | Moderate | Better for accents, background noise |

Set `WHISPER_MODEL` in `~/.env` to change the default. For a VPS or low-RAM server, `tiny` or `small` are recommended. `medium` is better when voice quality varies or the speaker has a strong accent.

All models are downloaded automatically from HuggingFace on first use.

## Telegram integration

The Telegram channel plugin delivers voice messages as `.ogg` (Opus codec) files via `download_attachment`. Pass the returned path directly to `whisper-auto.sh`:

```bash
# In your channel listener or Claude tool call:
AUDIO_PATH=$(download_attachment "$FILE_ID")   # returns /tmp/voice_xxx.ogg
TRANSCRIPT=$("$SCRIPTS_DIR/whisper-auto.sh" "$AUDIO_PATH")
# Then inject $TRANSCRIPT into the user message prompt
```

The agent receives the transcript as plain text and responds normally. No special handling is needed.

## What gets installed

- `~/.max/scripts/whisper-auto.sh` — the transcription script
- `~/whisper_venv/` — Python venv with faster-whisper installed
- `VENV_DIR` written to `~/.env`
