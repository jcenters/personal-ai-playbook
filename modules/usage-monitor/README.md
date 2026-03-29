# usage-monitor

Tracks Claude Max token usage and alerts when you're approaching the 5-hour rolling limit.

## What it does

- Reads real token data from `~/.claude/projects/**/*.jsonl` (the Claude Code CLI writes per-message `output_tokens` to these files after every API call)
- Tracks the 5-hour rolling window, 1-hour pace, and 7-day total
- Sends a Telegram alert only when usage crosses warning or critical thresholds
- Suppresses repeat alerts with a 90-minute cooldown per alert level
- Sends a weekly summary on Sunday evenings

## Why this works

Claude Code stores every conversation in `~/.claude/projects/<project-id>/<session>.jsonl`. Each assistant message contains a `usage` block:

```json
{
  "type": "assistant",
  "timestamp": "2026-03-29T13:00:00Z",
  "message": {
    "usage": {
      "output_tokens": 312,
      "input_tokens": 1024,
      "cache_read_input_tokens": 48000
    }
  }
}
```

This is the only reliable source of real-time usage data available locally. The Anthropic API does not expose a usage percentage endpoint for Claude Max subscriptions, and the OAuth token issued by Claude Code is not accepted by `api.anthropic.com`.

## Thresholds

Defaults are conservative — calibrate to your actual limit if you hit it:

| Level | Threshold | What triggers it |
|-------|-----------|-----------------|
| Pace warning | 120,000 tokens/hr | Burning through the window fast |
| Window warning | 350,000 tokens (5h) | ~75% of estimated ceiling |
| Window critical | 450,000 tokens (5h) | Slow down immediately |
| Weekly warning | 3,000,000 tokens (7d) | No published limit known; adjust as needed |

## Prerequisites

- Claude Code CLI installed and actively used (needs JSONL history)
- Telegram bot token (stored in 1Password or `.env` as `TELEGRAM_BOT_TOKEN`)
- Python 3.9+

## Files installed

- `~/.max/scripts/claude_usage_check.py` — main monitoring script
- `~/.max/state/usage_alert_state.json` — cooldown state (auto-created)
- Cron: hourly check 6 AM – 11 PM, Sunday 8 PM weekly summary

## Manual usage

```bash
# On-demand status (no Telegram)
python3 ~/.max/scripts/claude_usage_check.py --status

# Check and alert if over threshold
python3 ~/.max/scripts/claude_usage_check.py

# Force send weekly summary
python3 ~/.max/scripts/claude_usage_check.py --always
```
