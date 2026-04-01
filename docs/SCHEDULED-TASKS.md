# Scheduled Tasks

This document describes the full cron schedule for a typical personal-ai-playbook deployment. All times are shown in the user's local timezone — actual cron entries are in UTC. Module install scripts handle the timezone conversion automatically.

---

## Overview

Tasks fall into two categories:

**Nightly self-improvement** (while you're asleep, no notifications)
All scripts run with `NIGHTLY_MODE=1`, buffering results to `~/.{agent}/state/nightly-digest.txt` instead of sending immediate Telegram messages. The morning briefing reads and clears this file.

**Daily routines** (during waking hours, notifications sent immediately)

---

## Nightly Pipeline (4:00–4:45 AM)

Installed by `modules/memory/nightly-pipeline`.

| Time | Script | What it does |
|------|--------|--------------|
| 4:00 AM | `self-evolution.py` | Proposes + applies CLAUDE.md improvements based on recent activity/errors |
| 4:30 AM | `conversation-index.py` | Converts new JSONL sessions to searchable markdown |
| 4:30 AM | `memory-extract.py` | Extracts new facts from conversations, writes memory files |
| 4:30 AM | `skill-scout.py` | Detects recurring task patterns, generates new SKILL.md files |
| 4:30 AM | `user-model-update.py` | Corrects/retires outdated beliefs about the user |

**Undo any nightly change:**
```bash
git -C ~/.claude/skills revert HEAD          # revert skills
git -C ~/.{agent}/memory revert HEAD         # revert memory files
git -C ~/.{agent}-config revert HEAD         # revert CLAUDE.md
```

---

## Daily Routines

| Time | What it does | Module |
|------|--------------|--------|
| 7:00 AM | Morning briefing — weather, calendar, news leads, tweets, overnight digest | Custom (see docs/BRIEFING-PATTERN.md) |
| 6:00 PM | Evening briefing — tomorrow preview, any open items | Custom |
| 10:00 PM | Workout assignment for tomorrow | agents/fitness-coach |
| 10:10 PM | Book workout on calendar, sync dashboard | agents/fitness-coach |

---

## Weekly / Periodic

| Schedule | What it does |
|----------|--------------|
| Mon/Wed/Fri 9:00 AM | Job scout — find new listings, add to dashboard |
| Mon/Wed/Fri 9:30 AM | HR pipeline — route and apply to queued jobs |
| Daily 2:00 AM | System health check — disk, memory, services, connectivity |
| Daily 3:00 AM | Log rotation |
| Saturday 9:00 AM | Weekly review — surface recurring errors and feature requests |
| Hourly (6 AM–11 PM) | Claude usage monitor — alert if approaching limits |
| Nightly 3:30 AM | Max session restart (fresh context) |
| Nightly 5:00 AM | Git sync — push config and skills repos |
| Nightly 12:30 AM | LCM memory compaction |

---

## NIGHTLY_MODE Pattern

All scripts that run overnight should check `os.environ.get("NIGHTLY_MODE")` and write to `~/.{agent}/state/nightly-digest.txt` instead of sending Telegram messages when it's set.

```python
DIGEST_FILE = Path.home() / ".{agent}/state/nightly-digest.txt"

def send_notification(text):
    if os.environ.get("NIGHTLY_MODE"):
        with open(DIGEST_FILE, "a") as f:
            f.write(f"\n[script-name] {text}\n")
        return
    # ... normal Telegram send
```

Set `NIGHTLY_MODE=1` in cron:
```cron
30 9 * * * NIGHTLY_MODE=1 /usr/bin/python3 /path/to/script.py >> /path/to/log 2>&1
```

The morning briefing reads and clears the digest:
```bash
NIGHTLY_DIGEST=$(cat "$DIGEST_FILE" 2>/dev/null)
> "$DIGEST_FILE"
```

---

## Adding a New Scheduled Task

1. Write the script to `~/.{agent}/scripts/`
2. Copy it to `~/personal-ai-playbook/scripts/` (playbook sync rule)
3. If it runs overnight: implement `NIGHTLY_MODE` pattern in `send_notification()`
4. Add a cron entry with `NIGHTLY_MODE=1` if running during quiet hours
5. Document it here and in the module's README
6. If it belongs in the nightly pipeline: add it to `memory/nightly-pipeline` instead of a standalone cron entry
