# google-calendar-direct

Read and write Google Calendar events directly via OAuth, without going through the `gws` CLI at runtime. Because it uses a refresh token rather than an interactive keyring session, this script works reliably from cron jobs and non-interactive agent invocations.

## What it does

- Lists all events for today, tomorrow, or any specified date across all your calendars
- Creates 1-hour events on the primary calendar at a specified hour
- Outputs clean plain text (for Telegram messages or briefing assembly) or JSON (for downstream scripts)
- Handles timezone-aware display — events show in your local timezone regardless of where they were created

## Why "direct"

The `gws` CLI uses the system keyring for token storage. On a headless VPS, the keyring is either absent or locked, which means `gws calendar` hangs or fails in cron. This script reads the same `credentials.json` that `gws auth login` writes, but handles the token refresh itself using `google-auth`. No keyring, no interactive prompt, no problem.

## Prerequisites

- **Python 3.9+**
- **google-auth and google-api-python-client** (installed by install.sh)
- **gws CLI already authorized** (`gws auth login` run at least once), or a manually created `credentials.json`

### credentials.json format

```json
{
  "refresh_token": "1//...",
  "client_id": "....apps.googleusercontent.com",
  "client_secret": "GOCSPX-..."
}
```

## Installation

```bash
DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh
```

Optional overrides:

```bash
DEPLOY_BASE=$HOME \
AGENT_NAME=max \
GWS_CREDS=$HOME/.config/gws/credentials.json \
CALENDAR_TZ=America/Chicago \
bash install.sh
```

## Usage

```bash
GCAL="python3 ~/.max/scripts/gcal.py"

# Read today's events
$GCAL today

# Read tomorrow's events
$GCAL tomorrow

# Read a specific date
$GCAL --date 2026-03-29

# Create an event (defaults to 9 AM)
$GCAL --date 2026-03-29 --create "Doctor appointment"

# Create an event at a specific hour (24h clock)
$GCAL --date 2026-03-29 --create "Team call" --hour 14

# JSON output (for scripts, briefing assembly)
$GCAL today --json
```

### Example output (plain text)

```
Sunday, March 29:
  All day  Family Liturgy Day  [Personal]
  1:00 PM  Lunch with Hannah  [Personal]
  3:30 PM  Chapter House editorial review  [Work]
```

### Example output (JSON)

```json
[
  {
    "calendar": "Personal",
    "title": "Lunch with Hannah",
    "time": "1:00 PM",
    "location": "",
    "all_day": false,
    "start_raw": "2026-03-29T13:00:00-05:00"
  }
]
```

## Wiring into the agent

**For conversational calendar queries:**

Tell the agent "what's on my calendar today" and it calls:

```bash
python3 ~/.max/scripts/gcal.py today
```

The plain-text output gets injected into the response directly.

**For booking from natural language:**

> "Schedule a dentist appointment on April 3rd at 10 AM"

The agent calls:

```bash
python3 ~/.max/scripts/gcal.py --date 2026-04-03 --create "Dentist" --hour 10
```

**For briefing scripts (phase 1 data gathering):**

```bash
echo "=== CALENDAR ===" >> /tmp/briefing-data.txt
python3 ~/.max/scripts/gcal.py today >> /tmp/briefing-data.txt
```

## What gets installed

- `~/.max/scripts/gcal.py` — the calendar script
- `GWS_CREDS` and `CALENDAR_TZ` written to `~/.env`
- Python packages: google-auth, google-api-python-client (system pip)
