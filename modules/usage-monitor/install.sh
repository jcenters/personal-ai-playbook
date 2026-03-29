#!/usr/bin/env bash
# usage-monitor/install.sh
# Installs the Claude Max usage monitor script and cron jobs.
#
# Env vars:
#   DEPLOY_BASE      — base deployment directory (default: $HOME)
#   AGENT_NAME       — assistant name (default: max)
#   TELEGRAM_CHAT_ID — Telegram chat ID to send alerts to (required)
#   TZ_NAME          — IANA timezone (default: America/Chicago)
#
# Usage:
#   DEPLOY_BASE=$HOME AGENT_NAME=max TELEGRAM_CHAT_ID=123456789 bash install.sh

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-max}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"
TZ_NAME="${TZ_NAME:-America/Chicago}"

SCRIPTS_DIR="$DEPLOY_BASE/.$AGENT_NAME/scripts"
STATE_DIR="$DEPLOY_BASE/.$AGENT_NAME/state"
LOGS_DIR="$DEPLOY_BASE/.$AGENT_NAME/logs"
SCRIPT_PATH="$SCRIPTS_DIR/claude_usage_check.py"

echo "==> Installing usage-monitor to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR" "$STATE_DIR" "$LOGS_DIR"

# Write the monitoring script
cat > "$SCRIPT_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""
claude_usage_check.py — Monitor Claude Max usage limits.

Reads token data from ~/.claude/projects/**/*.jsonl (real per-message usage).
Also scans cron logs for actual API error signals.

Modes:
  (default)   Check for danger zones; alert via Telegram only if approaching limits
  --status    Print usage summary to stdout (no Telegram)
  --always    Send Telegram regardless of usage level (weekly report)

Thresholds (conservative — calibrate if you actually hit the limit):
  5h window warning:   350,000 output tokens
  5h window critical:  450,000 output tokens
  Hourly pace warning: 120,000 tokens/hr sustained
  Weekly warning:      3,000,000 tokens (no published limit known)
"""

import os
import re
import json
import glob
import subprocess
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

TZ = ZoneInfo(os.environ.get("TZ_NAME", "America/Chicago"))
LOG_DIR = os.environ.get("LOG_DIR", os.path.expanduser("~/.max/logs"))
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
STATE_FILE = os.environ.get("STATE_FILE", os.path.expanduser("~/.max/state/usage_alert_state.json"))

WARN_5H_TOKENS = 350_000
CRIT_5H_TOKENS = 450_000
WARN_HOURLY_TOKENS = 120_000
WARN_WEEKLY_TOKENS = 3_000_000
ALERT_COOLDOWN_MINUTES = 90

RATE_LIMIT_PATTERNS = [
    r"rate.limit", r"usage.limit", r"overloaded",
    r"too many requests", r"529", r"quota exceeded",
]


def get_telegram_token() -> str:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if token:
        return token
    try:
        result = subprocess.run(
            ["op", "read", "op://Max/Wintermute Telegram Bot Token/credential"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return ""


def send_telegram(text: str):
    token = get_telegram_token()
    if not token or not TELEGRAM_CHAT_ID:
        print("WARNING: No Telegram token or chat ID")
        return
    payload = json.dumps({"chat_id": TELEGRAM_CHAT_ID, "text": text, "parse_mode": "HTML"})
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload.encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        print("Telegram sent.")
    except Exception as e:
        print(f"Telegram error: {e}")


def load_alert_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_alert_state(state: dict):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def already_alerted(state: dict, level: str) -> bool:
    last = state.get(f"last_alert_{level}")
    if not last:
        return False
    last_ts = datetime.fromisoformat(last)
    return (datetime.now(timezone.utc) - last_ts) < timedelta(minutes=ALERT_COOLDOWN_MINUTES)


def mark_alerted(state: dict, level: str):
    state[f"last_alert_{level}"] = datetime.now(timezone.utc).isoformat()


def get_token_usage() -> dict:
    now = datetime.now(timezone.utc)
    buckets = {
        "1h": now - timedelta(hours=1),
        "5h": now - timedelta(hours=5),
        "24h": now - timedelta(hours=24),
        "7d": now - timedelta(days=7),
    }
    tokens = {k: 0 for k in buckets}
    msg_counts = {k: 0 for k in buckets}
    window_messages = []
    error_signals = []

    for f in glob.glob(os.path.join(PROJECTS_DIR, "**", "*.jsonl"), recursive=True):
        try:
            with open(f) as fh:
                for line in fh:
                    try:
                        d = json.loads(line)
                        if d.get("type") != "assistant":
                            continue
                        ts_str = d.get("timestamp", "")
                        if not ts_str:
                            continue
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        msg = d.get("message", {})
                        if not isinstance(msg, dict):
                            continue
                        usage = msg.get("usage", {})
                        out_tok = usage.get("output_tokens", 0)
                        for bucket, cutoff in buckets.items():
                            if ts >= cutoff:
                                tokens[bucket] += out_tok
                                msg_counts[bucket] += 1
                        if ts >= buckets["5h"]:
                            window_messages.append((ts.astimezone(TZ), out_tok))
                        if msg.get("stop_reason") == "error" or msg.get("type") == "error":
                            error_signals.append({
                                "ts": ts.astimezone(TZ).strftime("%H:%M"),
                                "file": os.path.basename(f),
                            })
                    except Exception:
                        pass
        except Exception:
            pass

    window_messages.sort()
    reset_time = None
    window_start = None
    if window_messages:
        window_start = window_messages[0][0]
        reset_time = window_start + timedelta(hours=5)

    hourly = defaultdict(int)
    for ts_ct, tok in window_messages:
        hourly[ts_ct.strftime("%H:00")] += tok

    return {
        "tokens_1h": tokens["1h"],
        "tokens_5h": tokens["5h"],
        "tokens_24h": tokens["24h"],
        "tokens_7d": tokens["7d"],
        "msgs_5h": msg_counts["5h"],
        "window_start": window_start.strftime("%H:%M") if window_start else "none",
        "reset_time": reset_time.strftime("%H:%M") if reset_time else "unknown",
        "reset_time_obj": reset_time,
        "hourly": dict(sorted(hourly.items())),
        "error_signals": error_signals,
    }


def scan_logs_for_errors() -> list:
    hits = []
    for log_file in glob.glob(os.path.join(LOG_DIR, "*.log")):
        try:
            with open(log_file) as f:
                content = f.read()
        except Exception:
            continue
        for line in content.splitlines():
            for pattern in RATE_LIMIT_PATTERNS:
                if re.search(pattern, line, re.IGNORECASE):
                    hits.append({"file": os.path.basename(log_file), "line": line.strip()[:150]})
                    break
    return hits


def status_report(usage: dict) -> str:
    now_ct = datetime.now(TZ)
    tz_label = TZ.key.split("/")[-1] if hasattr(TZ, "key") else "local"
    lines = [
        f"Claude Max Usage — {now_ct.strftime('%H:%M')} {tz_label}",
        f"",
        f"5h window:  {usage['tokens_5h']:>9,} tokens  ({usage['msgs_5h']} msgs)",
        f"1h pace:    {usage['tokens_1h']:>9,} tokens",
        f"24h total:  {usage['tokens_24h']:>9,} tokens",
        f"7-day:      {usage['tokens_7d']:>9,} tokens",
        f"",
        f"Window started: {usage['window_start']}",
        f"Resets at:      {usage['reset_time']}",
        f"",
        f"Thresholds:  warn={WARN_5H_TOKENS:,}  critical={CRIT_5H_TOKENS:,}",
        f"",
        f"Hourly:",
    ]
    for hour, tok in sorted(usage["hourly"].items()):
        bar = "#" * min(int(tok / 1000), 30)
        lines.append(f"  {hour}: {tok:,} {bar}")
    return "\n".join(lines)


def run(notify_always: bool = False, status_only: bool = False):
    usage = get_token_usage()
    log_errors = scan_logs_for_errors()
    state = load_alert_state()
    now_ct = datetime.now(TZ)

    if status_only:
        print(status_report(usage))
        return {}

    alerts = []
    level = None

    if usage["error_signals"] and not already_alerted(state, "error"):
        alerts.append(f"API error at {usage['error_signals'][-1]['ts']} — limit may have been hit.")
        level = "error"

    if log_errors and not already_alerted(state, "log_error"):
        for hit in log_errors[:2]:
            alerts.append(f"Rate limit in log [{hit['file']}]: {hit['line'][:80]}")
        level = "log_error"

    if usage["tokens_5h"] >= CRIT_5H_TOKENS and not already_alerted(state, "crit_5h"):
        alerts.append(f"5h window at {usage['tokens_5h']:,} tokens — CRITICAL. Slow down.")
        level = "crit_5h"
    elif usage["tokens_5h"] >= WARN_5H_TOKENS and not already_alerted(state, "warn_5h"):
        pct = int(usage["tokens_5h"] / CRIT_5H_TOKENS * 100)
        alerts.append(f"5h window at {usage['tokens_5h']:,} tokens ({pct}% of critical). Resets {usage['reset_time']}.")
        level = "warn_5h"

    if usage["tokens_1h"] >= WARN_HOURLY_TOKENS and not already_alerted(state, "pace"):
        alerts.append(f"Burning {usage['tokens_1h']:,} tokens/hr. Window resets {usage['reset_time']}.")
        level = level or "pace"

    if usage["tokens_7d"] >= WARN_WEEKLY_TOKENS and not already_alerted(state, "weekly"):
        alerts.append(f"7-day total: {usage['tokens_7d']:,} tokens.")
        level = level or "weekly"

    if alerts:
        msg = "<b>Claude Usage Warning</b>\n\n"
        msg += "\n".join(f"• {a}" for a in alerts)
        msg += f"\n\n5h: {usage['tokens_5h']:,} | 1h: {usage['tokens_1h']:,} | Reset: {usage['reset_time']}"
        send_telegram(msg)
        if level:
            mark_alerted(state, level)
        save_alert_state(state)
    elif notify_always:
        msg = (
            f"<b>Claude Usage — Weekly Check</b>\n"
            f"{now_ct.strftime('%a %b %-d, %H:%M')}\n\n"
            f"All clear.\n\n"
            f"5h window: {usage['tokens_5h']:,} tokens ({usage['msgs_5h']} msgs)\n"
            f"Resets: {usage['reset_time']}\n"
            f"24h: {usage['tokens_24h']:,} | 7-day: {usage['tokens_7d']:,}"
        )
        send_telegram(msg)

    summary = {
        "tokens_5h": usage["tokens_5h"],
        "tokens_1h": usage["tokens_1h"],
        "tokens_7d": usage["tokens_7d"],
        "reset_time": usage["reset_time"],
        "alerts_sent": len(alerts),
    }
    print(json.dumps(summary, indent=2))
    return summary


if __name__ == "__main__":
    import sys
    env_file = os.path.expanduser("~/.env")
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith("export "):
                    line = line[7:]
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    v = v.strip('"\'')
                    if k not in os.environ:
                        os.environ[k] = v
    if "--status" in sys.argv:
        run(status_only=True)
    elif "--always" in sys.argv:
        run(notify_always=True)
    else:
        run()
PYEOF

chmod +x "$SCRIPT_PATH"

# Write env vars
ENV_FILE="$DEPLOY_BASE/.env"
touch "$ENV_FILE"
if ! grep -q "^export TELEGRAM_CHAT_ID=" "$ENV_FILE" 2>/dev/null; then
    echo "export TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$ENV_FILE"
    echo "  Added TELEGRAM_CHAT_ID to $ENV_FILE"
fi
if ! grep -q "^export TZ_NAME=" "$ENV_FILE" 2>/dev/null; then
    echo "export TZ_NAME=\"$TZ_NAME\"" >> "$ENV_FILE"
    echo "  Added TZ_NAME to $ENV_FILE"
fi

# Install cron jobs
CRON_HOURLY="0 6-23 * * * TZ=$TZ_NAME LOG_DIR=$LOGS_DIR TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID source $DEPLOY_BASE/.env && python3 $SCRIPT_PATH >> $LOGS_DIR/claude-usage.log 2>&1"
CRON_WEEKLY="0 20 * * 0 TZ=$TZ_NAME LOG_DIR=$LOGS_DIR TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID source $DEPLOY_BASE/.env && python3 $SCRIPT_PATH --always >> $LOGS_DIR/claude-usage.log 2>&1"

# Remove old entries if present
TMPFILE=$(mktemp)
crontab -l 2>/dev/null | grep -v "claude_usage_check\|Claude usage" > "$TMPFILE" || true
echo "# Claude usage — hourly check, alert if approaching limits" >> "$TMPFILE"
echo "$CRON_HOURLY" >> "$TMPFILE"
echo "# Claude usage — Sunday weekly summary" >> "$TMPFILE"
echo "$CRON_WEEKLY" >> "$TMPFILE"
crontab "$TMPFILE"
rm "$TMPFILE"

echo ""
echo "==> usage-monitor installed."
echo ""
echo "    Script:     $SCRIPT_PATH"
echo "    State:      $STATE_FILE"
echo "    Logs:       $LOGS_DIR/claude-usage.log"
echo "    Cron:       hourly 6AM-11PM + Sunday 8PM weekly summary"
echo ""
echo "    Manual check:  python3 $SCRIPT_PATH --status"
echo "    Force alert:   python3 $SCRIPT_PATH --always"
echo ""
echo "    Set TELEGRAM_BOT_TOKEN in $ENV_FILE to enable notifications."
