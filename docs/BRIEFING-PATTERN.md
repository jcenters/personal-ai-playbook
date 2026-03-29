# Briefing Pattern

A two-phase architecture for assembling scheduled briefings (morning summaries, evening check-ins, weekly digests) that keeps data gathering separate from AI assembly.

---

## The core idea

Most briefing scripts try to do everything in one step: gather data, reason about it, format it, send it. This works until something breaks — a weather API times out, a calendar query hangs, or the Claude invocation hits a rate limit. When all three are wired together, you can't tell which one failed, and the whole thing has to run again from scratch.

The two-phase pattern separates concerns cleanly:

- **Phase 1 (shell, no AI):** Gather raw data. Write it to a temp file. Exit.
- **Phase 2 (Claude):** Read the temp file. Assemble and send the briefing.

Each phase can succeed or fail independently.

---

## Why two phases

**Cost.** Claude tokens cost money (or burn through a rate-limited plan). Phase 1 runs entirely in shell — `curl`, `python3`, `cat`. No AI tokens are spent until the data is confirmed ready.

**Debuggability.** You can run phase 1 manually and inspect `/tmp/briefing-data.txt` without triggering a Claude invocation. If the weather block looks wrong or the calendar returned nothing, you fix it in shell, not by reading Claude's hallucinated interpretation.

**Reliability.** If phase 1 fails (network error, bad API response, missing log file), the script exits before phase 2 is ever called. Claude never sees partial data and never produces a broken briefing.

**Separation of concerns.** Phase 1 is boring plumbing. Phase 2 is judgment and formatting. Each is easier to test and modify when they're not tangled together.

---

## Phase 1: Data gathering

Phase 1 is a shell script that assembles a plaintext file. Each data source gets a labeled section. Keep the total output under ~4,000 tokens (~16,000 characters) so it fits comfortably in the Claude context window alongside your system prompt.

```bash
#!/usr/bin/env bash
# briefing-gather.sh — Phase 1: collect raw data

set -euo pipefail

OUTPUT_FILE="${1:-/tmp/briefing-data.txt}"
TZ="${TZ:-America/Chicago}"

{
    echo "=== WEATHER ==="
    curl -s "wttr.in/Nashville?format=3&u" 2>/dev/null || echo "Weather unavailable"

    echo ""
    echo "=== CALENDAR ==="
    python3 ~/.max/scripts/gcal.py today 2>/dev/null || echo "Calendar unavailable"

    echo ""
    echo "=== TASKS ==="
    python3 ~/.openclaw/workspace/scripts/todoist_api.py today 2>/dev/null | head -20 || echo "No tasks"

    echo ""
    echo "=== FITNESS ==="
    cat ~/workspace/fitness-logs/$(date +%Y-%m-%d).md 2>/dev/null || echo "No log yet"

    echo ""
    echo "=== NEWS ==="
    curl -sL "https://feeds.feedburner.com/TheFirearmBlog" 2>/dev/null \
        | python3 -c "
import sys, re
content = sys.stdin.read()
titles = re.findall(r'<title><!\[CDATA\[(.*?)\]\]></title>', content)[:3]
for t in titles:
    print('-', t)
" || echo "Feed unavailable"

} > "$OUTPUT_FILE"

echo "Phase 1 complete: $OUTPUT_FILE"
wc -c "$OUTPUT_FILE"
```

### What data works well in phase 1

| Source | Tool | Notes |
|--------|------|-------|
| Weather | `curl wttr.in` | One-liner format (`?format=3`) keeps output to a single line |
| Calendar | `gcal.py today` | Plain text output; use `--json` if you need to filter |
| Tasks | todoist API script | Pipe through `head -20` to cap token count |
| Fitness log | `cat` daily markdown file | Handle missing file gracefully with `2>/dev/null \|\| echo "No log"` |
| RSS feeds | `curl` + regex | Extract top 3 titles; don't include full article text |
| Memory summary | `cat summary.md` | Include only the most recent section if large |
| Disk/system stats | `df -h` or `uptime` | Useful for evening check-ins |

### Keeping phase 1 output under 4,000 tokens

- Use `head -N` to cap any unbounded source
- For RSS: titles only, not descriptions or full text
- For task lists: today's tasks, not everything
- For fitness logs: the day's log, not the full history
- Skip any source that requires AI to interpret — that's phase 2's job

---

## Phase 2: Claude assembly

Phase 2 reads the data file and asks Claude to assemble a formatted message. The system prompt (from `CLAUDE.md`) is injected via `--append-system-prompt`, which means persona, voice, and tool access all apply normally.

```bash
#!/usr/bin/env bash
# briefing-assemble.sh — Phase 2: have Claude assemble and send the briefing

set -euo pipefail

DATA_FILE="${1:-/tmp/briefing-data.txt}"
CHAT_ID="${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"
CONFIG_DIR="$HOME/.max-config"

if [[ ! -f "$DATA_FILE" ]]; then
    echo "Error: data file not found: $DATA_FILE" >&2
    exit 1
fi

DATA=$(cat "$DATA_FILE")
SYSTEM_PROMPT=$(cat "$CONFIG_DIR/CLAUDE.md")

claude --print \
    --append-system-prompt "$SYSTEM_PROMPT" \
    "$DATA

Assemble a morning briefing from the data above. Keep it under 300 words.
Lead with weather and the first calendar event. Then tasks for today.
Send it to Telegram chat_id $CHAT_ID."
```

### Skills injection

If your system prompt includes skill definitions (humanizer, voice style, etc.), they apply automatically via `--append-system-prompt`. You can also inject a skill explicitly:

```bash
SKILL=$(cat ~/.claude/skills/humanizer.md)

claude --print \
    --append-system-prompt "$SYSTEM_PROMPT
$SKILL" \
    "$(cat "$DATA_FILE")

Assemble and humanize a morning briefing..."
```

### Keeping the assembly prompt focused

- Give Claude one job: "assemble a briefing from this data and send it"
- Do not ask Claude to also gather more data in phase 2 — that's phase 1's job
- Specify output format constraints (word count, what to lead with)
- Specify the delivery target (Telegram chat ID, Google Doc, email)

---

## Cron scheduling

Run the two phases as separate cron entries, staggered by 5 minutes. If phase 1 is still running when phase 2 fires, the data file will be incomplete — so give phase 1 enough time to finish.

```cron
# Morning briefing — Central Time
# Phase 1: gather data at 7:00 AM
0 7 * * * TZ=America/Chicago bash ~/.max/scripts/briefing-gather.sh /tmp/morning-data.txt >> ~/.max/logs/briefing.log 2>&1

# Phase 2: assemble and send at 7:05 AM
5 7 * * * TZ=America/Chicago source ~/.env && bash ~/.max/scripts/briefing-assemble.sh /tmp/morning-data.txt >> ~/.max/logs/briefing.log 2>&1
```

If phase 1 consistently takes more than 5 minutes (unlikely unless you have slow RSS feeds or large log files), increase the gap.

---

## Morning vs. evening variants

### Morning briefing

Focus: what's happening today.

Data sources: weather, calendar, today's tasks, any pending items from memory.

Prompt framing: "Lead with weather. Then today's first event. Then tasks. Keep it under 250 words."

### Evening check-in

Focus: what happened today, what's pending tomorrow.

Data sources: today's calendar (completed events), fitness log, tomorrow's first calendar event, any unfinished tasks.

Prompt framing: "Summarize the day. Note anything incomplete. Preview tomorrow morning."

### Weekly digest

Focus: patterns, metrics, what's coming this week.

Data sources: 7-day fitness log summary, next 7 days of calendar, any recurring reports.

Prompt framing: "Write a one-paragraph weekly summary and a 3-item preview of the week ahead."

---

## Anti-patterns to avoid

**Putting API calls in phase 1 that require AI to interpret.** If a data source returns something that needs reasoning (e.g., a raw JSON blob from a job board), save the raw output and let Claude parse it in phase 2 — or run a separate preprocessing step.

**Making phase 2 do its own data gathering.** If your phase 2 prompt says "check the weather and also look at my calendar," Claude will either call tools (slower, uses more tokens) or hallucinate. All data gathering belongs in phase 1.

**Running both phases in a single cron entry.** If you chain them with `&&`, a phase 1 failure will silently skip phase 2 with no notification. Separate entries make it easier to see which phase failed in the cron log.

**Using a single large data file across multiple briefings.** Each briefing run should write to a uniquely named temp file (e.g., include a timestamp or use `mktemp`). Otherwise a failed phase 1 leaves a stale data file, and phase 2 will send yesterday's briefing.

**Skipping the phase 1 output size check.** Large data files slow down Claude and can cause briefings to exceed Telegram's 4,096-character message limit. Add `wc -c "$OUTPUT_FILE"` at the end of phase 1 and pipe to a log so you can spot bloat.

---

## Reference implementation

See `modules/calendar/google-calendar-direct/` for `gcal.py`, which produces clean plain-text calendar output suitable for phase 1 data files.

See `modules/voice-input/faster-whisper/` for an example of a phase 1 tool that runs locally with no API calls.
