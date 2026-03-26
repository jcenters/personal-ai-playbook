# Onboarding Questionnaire

Complete this document before running `setup.sh` for a new user. Every answer here becomes configuration — the more specific you are, the better the initial experience.

---

## Part 1: About the User

**Full name:**


**Preferred first name / what the AI should call them:**


**Timezone** (e.g., America/Chicago, Europe/London):


**Primary language:**


**Communication style preferences:**

- [ ] Brief and direct — get to the point fast
- [ ] Conversational — some warmth and small talk is fine
- [ ] Detailed — include context and reasoning
- [ ] Formal
- [ ] Casual / irreverent

**Notes on tone or communication quirks:**


**Primary use cases** (check all that apply):

- [ ] Daily check-ins and task management
- [ ] Fitness coaching and workout tracking
- [ ] Job searching and career development
- [ ] Research and information lookup
- [ ] Writing assistance
- [ ] System monitoring and server health
- [ ] Calendar and scheduling help
- [ ] General Q&A and brainstorming
- [ ] Other: _______________

**Anything the AI should always remember about this person:**


---

## Part 2: Technical Setup

**Machine type:**

- [ ] Linux server / VPS
- [ ] macOS laptop/desktop
- [ ] Linux desktop
- [ ] Raspberry Pi or similar
- [ ] Other: _______________

**Operating system and version** (e.g., Ubuntu 22.04, macOS 14 Sonoma):


**Shell:**

- [ ] bash
- [ ] zsh
- [ ] fish
- [ ] Other: _______________

**Claude.ai subscription status:**

- [ ] Free tier
- [ ] Pro (Claude.ai)
- [ ] API access (Anthropic API key) — required for this system

**Anthropic API key available?**

- [ ] Yes
- [ ] No — must obtain one at https://console.anthropic.com before proceeding

**Claude Code installed?**

- [ ] Yes (`claude` command works)
- [ ] No — install from https://claude.ai/download

**Existing accounts / services** (check what's available to integrate):

- [ ] Telegram (required for Telegram channel)
- [ ] 1Password
- [ ] Google Workspace
- [ ] Brave Search account (for researcher web search)
- [ ] Other messaging: _______________

**Python 3 available?**

- [ ] Yes (`python3 --version`)
- [ ] No — required; install before running setup

**Git available?**

- [ ] Yes
- [ ] No — recommended; install before running setup

---

## Part 3: Messaging Channel Preference

How should the user interact with the AI?

**Primary channel:**

- [ ] Telegram bot (recommended — works on mobile and desktop)
- [ ] Claude.ai web interface only (no channel needed)
- [ ] Other / custom: _______________

**If Telegram:**

- Telegram username: `@`_______________
- Telegram user ID (get from @userinfobot): _______________
- Bot token (create via @BotFather): _______________
  - Keep this secret — do not share publicly

**Notification preferences:**

- [ ] Proactive morning briefings
- [ ] Proactive evening check-ins
- [ ] Proactive health alerts only (no daily routine)
- [ ] On-demand only — no proactive messages

**Quiet hours** (proactive messages will be suppressed):

- Start: ___:___ (e.g., 22:00)
- End:   ___:___ (e.g., 07:00)
- Timezone for quiet hours: _______________

---

## Part 4: Persona Selection

Choose a persona for the AI. The persona affects the name, voice, and default behavior — not the underlying capabilities.

**Available personas:**

| Persona | Character | Best for |
|---------|-----------|----------|
| **Max** | Efficient, slightly snarky assistant. Gets things done without fuss. | Power users who want speed over warmth |
| **Ada** | Warm, curious, encouraging. Good at explaining things. | Users who want a supportive, teaching-style assistant |
| **Luca** | Calm and methodical. Thinks out loud, shows its work. | Users doing heavy analysis or research |
| **Custom** | You define the character in CLAUDE.md | Experienced users who want full control |

**Which persona?** _______________

**If custom — describe the character in a few sentences:**


**What should the AI call the user?** (first name, nickname, etc.)


---

## Part 5: Module Selection

Check the modules to install. Each module adds a sub-agent or capability. You can add more later with `bash modules/[module]/install.sh`.

### Agent Modules

- [ ] **fitness-coach** — Assigns workouts, tracks sessions, monitors progress.
  - Requires: nothing extra
  - Creates: `fitness/` log directory

- [ ] **job-search** — Helps find jobs, write cover letters, and prep for interviews.
  - Requires: nothing extra (optional: resume file path)
  - Creates: `job-search.yaml` preferences file

- [ ] **system-health** — Monitors disk, memory, services, and logs. Daily 2 AM cron.
  - Requires: cron access
  - Creates: health config and log

- [ ] **researcher** — Deep research on topics. Optional live web search.
  - Requires: optional Brave Search API key for live web
  - Creates: `research/notes/` directory

### Storage Modules (choose one)

- [ ] **local-only** — All memory stored as markdown files on this machine. No cloud.
  - Best for: privacy-first users, servers without internet-dependent storage
  - Limitation: no sync across devices

- [ ] **obsidian-sync** — Stores notes in an Obsidian vault with Obsidian Sync.
  - Best for: users already on Obsidian Sync
  - Requires: Obsidian Sync subscription, vault path

---

## Part 6: Secrets and Credentials to Gather

Collect these before running setup. Do not paste keys into this document if it will be shared.

| Secret | Module | Where to Get It | Status |
|--------|--------|-----------------|--------|
| Anthropic API key | Core | console.anthropic.com | [ ] ready |
| Telegram bot token | Telegram channel | @BotFather on Telegram | [ ] ready |
| Telegram user ID | Telegram channel | @userinfobot on Telegram | [ ] ready |
| Brave Search API key | researcher (optional) | api.search.brave.com | [ ] ready / [ ] skipping |
| Resume file path | job-search (optional) | local file path | [ ] ready / [ ] skipping |

**1Password in use?**

- [ ] Yes — secrets will be stored in 1Password and read via `op read`
  - Vault name: _______________
- [ ] No — secrets will be stored directly in `.env` (not synced, set perms to 600)

---

## Part 7: Post-Setup Testing Checklist

After running `setup.sh`, verify each of the following:

**Core**

- [ ] `claude --version` works
- [ ] `ANTHROPIC_API_KEY` is set in `.env` and `source`d
- [ ] `.env` permissions are `600` (`chmod 600 ~/.{name}/.env`)
- [ ] `agents.json` exists and contains the installed agents

**Telegram channel** (if configured)

- [ ] Bot responds to a simple message (send "hello")
- [ ] Bot receives and processes messages from the correct user ID only
- [ ] Quiet hours are respected (test by checking config, not by waiting)

**Each installed module**

- [ ] fitness-coach: `FITNESS_LOG_DIR` is set; `workouts.md` exists
- [ ] job-search: `JOB_SEARCH_PREFS_PATH` is set; `job-search.yaml` is readable
- [ ] system-health: `SYSTEM_HEALTH_CONFIG` is set; cron job appears in `crontab -l`
- [ ] researcher: `RESEARCH_DIR` is set; notes directory exists
- [ ] local-only: `NOTES_DIR` is set; subdirectories exist

**Memory**

- [ ] `load-memory.sh` runs without errors
- [ ] A test message is stored and retrieved correctly

**First conversation**

- [ ] Introduce the AI to the user: "This is [persona name]. Say hello and ask what they want to focus on today."
- [ ] Confirm the AI uses the correct name and preferred tone

---

## Part 8: Deployer Notes

Use this space for anything that doesn't fit above — edge cases, known constraints, special instructions from the user, follow-up items.

```
[Notes]



```

---

*Document version: 1.0 — personal-ai-playbook*
