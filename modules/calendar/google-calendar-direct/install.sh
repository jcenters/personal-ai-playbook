#!/usr/bin/env bash
# google-calendar-direct/install.sh
# Installs gcal.py for reading and writing Google Calendar events directly via OAuth.
# Does not depend on the gws CLI at runtime — works from cron without keyring.
#
# Env vars:
#   DEPLOY_BASE  — base deployment directory (default: $HOME)
#   AGENT_NAME   — assistant name (default: max)
#   GWS_CREDS    — path to credentials.json (default: ~/.config/gws/credentials.json)
#   CALENDAR_TZ  — IANA timezone for event display (default: America/Chicago)
#
# Usage:
#   DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-max}"
GWS_CREDS="${GWS_CREDS:-$HOME/.config/gws/credentials.json}"
CALENDAR_TZ="${CALENDAR_TZ:-America/Chicago}"

SCRIPTS_DIR="$DEPLOY_BASE/.$AGENT_NAME/scripts"
SCRIPT_PATH="$SCRIPTS_DIR/gcal.py"

echo "==> Installing google-calendar-direct to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

# Check Python 3
PYTHON_BIN=$(command -v python3 || true)
if [[ -z "$PYTHON_BIN" ]]; then
    echo "  ERROR: python3 not found."
    exit 1
fi

# Install dependencies
echo "  Installing Python dependencies"
"$PYTHON_BIN" -m pip install --quiet --upgrade google-auth google-api-python-client

# Check for credentials.json
if [[ ! -f "$GWS_CREDS" ]]; then
    echo ""
    echo "  WARNING: $GWS_CREDS not found."
    echo "  Run 'gws auth login' to generate it, or place credentials.json manually."
    echo "  Required fields: refresh_token, client_id, client_secret"
    echo ""
else
    echo "  credentials.json found at $GWS_CREDS"
fi

# Write gcal.py
cat > "$SCRIPT_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""
gcal.py — Google Calendar CLI using gws OAuth credentials directly.

Bypasses gws and keyring. Works from cron without interactive auth.

Usage:
    gcal.py [today|tomorrow] [--tz America/Chicago]
    gcal.py --date 2026-03-29
    gcal.py --date 2026-03-29 --create "Event Title" --hour 14
    gcal.py --json

Reads credentials from ~/.config/gws/credentials.json (or $GWS_CREDS).
Required fields in credentials.json: refresh_token, client_id, client_secret
"""
import sys
import os
import json
import argparse
from datetime import datetime, timedelta, date, timezone
from zoneinfo import ZoneInfo

CREDS_PATH = os.environ.get("GWS_CREDS", os.path.expanduser("~/.config/gws/credentials.json"))
DEFAULT_TZ = os.environ.get("CALENDAR_TZ", "America/Chicago")

def load_credentials():
    if not os.path.exists(CREDS_PATH):
        raise FileNotFoundError(
            f"credentials.json not found at {CREDS_PATH}\n"
            "Run 'gws auth login' or set GWS_CREDS env var."
        )
    with open(CREDS_PATH) as f:
        data = json.load(f)
    required = {"refresh_token", "client_id", "client_secret"}
    missing = required - set(data.keys())
    if missing:
        raise ValueError(f"credentials.json missing fields: {missing}")
    return data

def get_credentials(creds_data: dict):
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    creds = Credentials(
        token=None,
        refresh_token=creds_data["refresh_token"],
        client_id=creds_data["client_id"],
        client_secret=creds_data["client_secret"],
        token_uri="https://oauth2.googleapis.com/token",
        scopes=["https://www.googleapis.com/auth/calendar"],
    )
    creds.refresh(Request())
    return creds

def get_events(creds, target_date: date, tz_name: str) -> list:
    from googleapiclient.discovery import build
    tz = ZoneInfo(tz_name)
    start = datetime(target_date.year, target_date.month, target_date.day, 0, 0, 0, tzinfo=tz)
    end = start + timedelta(days=1)

    service = build("calendar", "v3", credentials=creds)
    calendars = service.calendarList().list().execute().get("items", [])

    events = []
    for cal in calendars:
        cal_id = cal["id"]
        result = service.events().list(
            calendarId=cal_id,
            timeMin=start.isoformat(),
            timeMax=end.isoformat(),
            singleEvents=True,
            orderBy="startTime",
            maxResults=50,
        ).execute()
        for item in result.get("items", []):
            start_raw = item["start"].get("dateTime", item["start"].get("date", ""))
            end_raw = item["end"].get("dateTime", item["end"].get("date", ""))
            all_day = "dateTime" not in item["start"]
            if not all_day:
                start_dt = datetime.fromisoformat(start_raw).astimezone(tz)
                time_str = start_dt.strftime("%-I:%M %p")
            else:
                time_str = "All day"
            events.append({
                "calendar": cal.get("summary", cal_id),
                "title": item.get("summary", "(no title)"),
                "time": time_str,
                "location": item.get("location", ""),
                "all_day": all_day,
                "start_raw": start_raw,
            })

    events.sort(key=lambda e: (e["all_day"], e["start_raw"]))
    return events

def create_event(creds, target_date: date, title: str, hour: int, tz_name: str) -> str:
    from googleapiclient.discovery import build
    tz = ZoneInfo(tz_name)
    start = datetime(target_date.year, target_date.month, target_date.day, hour, 0, 0, tzinfo=tz)
    end = start + timedelta(hours=1)
    service = build("calendar", "v3", credentials=creds)
    event = service.events().insert(
        calendarId="primary",
        body={
            "summary": title,
            "start": {"dateTime": start.isoformat()},
            "end": {"dateTime": end.isoformat()},
        },
    ).execute()
    return event.get("htmlLink", "")

def format_events(events: list, target_date: date, tz_name: str) -> str:
    label = target_date.strftime("%A, %B %-d")
    if not events:
        return f"{label}: no events."
    lines = [f"{label}:"]
    for e in events:
        loc = f" ({e['location']})" if e["location"] else ""
        lines.append(f"  {e['time']}  {e['title']}{loc}  [{e['calendar']}]")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Google Calendar CLI")
    parser.add_argument("day", nargs="?", choices=["today", "tomorrow"], default="today")
    parser.add_argument("--date", help="Specific date (YYYY-MM-DD)")
    parser.add_argument("--tz", default=DEFAULT_TZ, help="IANA timezone (default: America/Chicago)")
    parser.add_argument("--create", metavar="TITLE", help="Create an event with this title")
    parser.add_argument("--hour", type=int, default=9, help="Hour for new event (24h, default: 9)")
    parser.add_argument("--json", action="store_true", help="Output events as JSON array")
    args = parser.parse_args()

    if args.date:
        target = date.fromisoformat(args.date)
    elif args.day == "tomorrow":
        target = date.today() + timedelta(days=1)
    else:
        target = date.today()

    creds_data = load_credentials()
    creds = get_credentials(creds_data)

    if args.create:
        url = create_event(creds, target, args.create, args.hour, args.tz)
        print(f"Created: {args.create}")
        print(f"URL: {url}")
        return

    events = get_events(creds, target, args.tz)

    if args.json:
        print(json.dumps(events, indent=2))
    else:
        print(format_events(events, target, args.tz))

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$SCRIPT_PATH"

# Write env vars
ENV_FILE="$DEPLOY_BASE/.env"
touch "$ENV_FILE"
if ! grep -q "^export GWS_CREDS=" "$ENV_FILE" 2>/dev/null; then
    echo "export GWS_CREDS=\"$GWS_CREDS\"" >> "$ENV_FILE"
    echo "  Added GWS_CREDS to $ENV_FILE"
fi
if ! grep -q "^export CALENDAR_TZ=" "$ENV_FILE" 2>/dev/null; then
    echo "export CALENDAR_TZ=\"$CALENDAR_TZ\"" >> "$ENV_FILE"
    echo "  Added CALENDAR_TZ to $ENV_FILE"
fi

echo ""
echo "==> google-calendar-direct installed."
echo ""
echo "    Script:       $SCRIPT_PATH"
echo "    Credentials:  $GWS_CREDS"
echo "    Timezone:     $CALENDAR_TZ"
echo ""
echo "    Usage:"
echo "      python3 $SCRIPT_PATH today"
echo "      python3 $SCRIPT_PATH tomorrow"
echo "      python3 $SCRIPT_PATH --date 2026-03-29"
echo "      python3 $SCRIPT_PATH --date 2026-03-29 --create 'Dentist' --hour 10"
echo "      python3 $SCRIPT_PATH today --json"
echo ""
echo "    Works from cron without keyring or interactive auth."
echo ""
