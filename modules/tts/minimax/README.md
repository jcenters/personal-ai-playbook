# MiniMax Backend

MiniMax (hailuo.ai) TTS API. Strong multilingual support, competitive pricing vs ElevenLabs, and good custom character voice options. Implemented as pure curl — no SDK required.

---

## Setup

```bash
bash modules/tts/minimax/install.sh
```

This verifies `curl` and `python3` are available, sets the backend scripts executable, and writes `MINIMAX_API_KEY`, `MINIMAX_GROUP_ID`, and `MINIMAX_VOICE_ID` stubs to your `.env`.

---

## Credentials

Both an API key and a Group ID are required. Get both from the MiniMax platform:

1. Sign up at [platform.minimaxi.com](https://platform.minimaxi.com)
2. Copy your API key and Group ID from the dashboard
3. Set them in `.env`:

```bash
export MINIMAX_API_KEY="your-api-key-here"
export MINIMAX_GROUP_ID="your-group-id-here"
```

---

## Voice Selection

Set `MINIMAX_VOICE_ID` in `.env`. MiniMax provides built-in voice IDs and supports custom cloned voices:

```bash
export MINIMAX_VOICE_ID="male-qn-qingse"    # default built-in male voice
export MINIMAX_VOICE_ID="female-shaonv"      # built-in female voice
export MINIMAX_VOICE_ID="your-cloned-id"    # a voice you've cloned in the platform
```

Built-in voices cover English, Chinese, Japanese, Korean, and more.

---

## Model Options

The backend defaults to `speech-02-hd`. To trade quality for speed, edit `minimax/speak.sh` and change the model field:

```json
"model": "speech-02-hd"   // highest quality (default)
"model": "speech-02"      // faster, lower cost
```

---

## Usage

```bash
# Play immediately
TTS_BACKEND=minimax modules/tts/speak.sh "Hello world"

# Write to file
TTS_BACKEND=minimax modules/tts/speak.sh "Hello world" /tmp/out.mp3
```

Or set `TTS_BACKEND=minimax` in `.env` to make it the default.

---

## vs. ElevenLabs

MiniMax is worth considering when you want a custom character voice without ElevenLabs pricing, or when your use case is multilingual (MiniMax has notably strong Chinese and Japanese support). ElevenLabs generally has better English naturalness and a larger pre-built voice library.
