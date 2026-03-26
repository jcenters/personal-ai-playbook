# personal-ai-playbook

A framework for deploying a personal AI assistant using Claude Code. Runs on a VPS, Raspberry Pi, or Mac mini. You interact through messaging channels — Telegram, Discord, or iMessage. No Anthropic API key required: the framework uses the Claude Code binary, which authenticates through your existing claude.ai subscription.

---

## What This Is

Most personal AI setups require managing API keys, paying per token, and stitching together half-finished libraries. This project takes a different path: it uses the `claude` CLI binary you already have, wraps it in a clean runtime, and gives you a persistent assistant you can message from anywhere.

The result is a single assistant that:

- Lives on always-on hardware (VPS, Raspberry Pi, Mac mini)
- Responds to messages via Telegram, Discord, or iMessage
- Remembers context across sessions through the LCM memory system
- Has a configurable persona and can run scheduled routines
- Talks to your calendar, email, Obsidian vault, and other tools through modular plugins
- Costs nothing beyond your claude.ai subscription and your hardware

---

## Key Features

**No API key required.** Authentication goes through the Claude Code binary and your claude.ai account — no Anthropic API keys, no per-token billing on top of your subscription.

**Modular.** Every capability is a module. Install only what you need. Modules are self-contained directories with their own install scripts and documentation.

**Channel-agnostic.** Swap messaging channels by changing one config value. The core assistant is decoupled from how messages arrive.

**Persona system.** Drop in a persona pack (or write your own) to shape tone, behavior, and priorities. The persona is injected at startup via `--append-system-prompt`.

**LCM memory.** Session logs are compacted nightly into a rolling context file the assistant loads at startup. The assistant remembers things across sessions without ballooning context windows.

**Scheduled routines.** Morning briefings, evening summaries, and custom cron-triggered tasks run via the same assistant process.

**Skills system.** Capabilities are added as skill files (markdown or shell) that Claude Code picks up automatically. Community skills are published under `skills/`.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Always-on machine | VPS (Ubuntu/Debian recommended), Raspberry Pi 4+, or Mac mini |
| claude.ai subscription | Pro or higher. The `claude` CLI authenticates through this. |
| Claude Code binary | Install from [claude.ai/download](https://claude.ai/download) or `npm install -g @anthropic-ai/claude-code` |
| `git` | Any recent version |
| Node.js (v18+) or Bun | For channel bridge scripts and tooling |
| `tmux` | Session management for the assistant process |

Optional per-module requirements are listed in each module's `README.md`.

---

## Quick Start

```bash
git clone https://github.com/your-org/personal-ai-playbook
cd personal-ai-playbook
./setup.sh
```

The setup wizard will walk you through everything: naming your assistant, picking a messaging channel, selecting a persona, choosing modules, and collecting credentials. At the end it generates a ready-to-run deployment and adds a `@reboot` cron job.

After setup:

```bash
~/start-assistant.sh       # Start (or attach to) the assistant session
~/stop-assistant.sh        # Stop the assistant
tmux attach -t assistant   # Attach directly to the tmux session
```

---

## Architecture

```
~/.assistant/              Runtime directory (generated, not committed)
  scripts/                 Utility scripts (load-memory.sh, compact-memory.sh, etc.)
  memory/                  LCM session logs and compacted context
  state/                   Runtime state files

~/assistant-config/        Config repo (git-tracked, symlinked into place)
  CLAUDE.md                Assistant identity and tool configuration
  SOUL.md                  Persona definition
  skills/                  Skill files loaded by Claude Code
  modules/                 Enabled module configs

~/start-assistant.sh       tmux launcher (generated)
~/.env                     Secrets (never committed)
```

The **runtime directory** (`~/.$AGENT_NAME/`) holds everything ephemeral. The **config repo** (`~/$AGENT_NAME-config/`) holds everything you want version-controlled: your CLAUDE.md, persona, and skills. Setup creates symlinks between them.

The assistant process runs inside a named tmux session. The channel bridge (e.g., a Telegram bot) forwards messages to the Claude Code process via stdin/pipe or a local socket, depending on the channel plugin.

---

## Modules

| Module | What it does |
|---|---|
| `messaging/telegram` | Telegram bot bridge (recommended) |
| `messaging/discord` | Discord bot bridge |
| `messaging/imessage` | iMessage via AppleScript (macOS only) |
| `secrets/1password` | Secrets via `op` CLI |
| `secrets/bitwarden` | Secrets via `bw` CLI |
| `calendar/google-workspace` | Google Calendar and Gmail via `gws` CLI |
| `storage/obsidian` | Obsidian vault read/write integration |
| `agents/fitness` | Fitness logging and coaching agent |
| `agents/job-search` | Job application tracking and research agent |
| `agents/system-health` | System and service health monitoring |
| `agents/research` | Web research and synthesis agent |
| `memory/lcm` | Session logging and nightly context compaction |
| `routines/daily-briefing` | Scheduled morning and evening reports |

---

## Persona Packs

Persona packs live in `personas/`. Each pack is a markdown file injected as `SOUL.md` at deploy time.

| Pack | Best for |
|---|---|
| `executive-pa` | Scheduling, task management, professional communication |
| `creative-partner` | Writing, brainstorming, editorial feedback |
| `coach` | Goals, habits, accountability, fitness |
| `researcher` | Deep research, synthesis, fact-checking |
| `family-hub` | Household coordination, reminders, family logistics |

To use a custom persona, select "Custom" during setup. You can edit `$AGENT_NAME-config/SOUL.md` at any time and restart the assistant.

---

## Directory Reference

```
personal-ai-playbook/
  setup.sh                 Interactive setup wizard
  templates/               File templates used by setup.sh
    CLAUDE.md.tmpl
    SOUL.md.tmpl
    start.sh.tmpl
    .env.tmpl
  modules/                 Module install scripts and configs
    messaging/
    secrets/
    calendar/
    storage/
    agents/
    memory/
    routines/
  personas/                Persona pack markdown files
  skills/                  Community skills
  scripts/                 Shared utility scripts
  docs/                    Extended documentation
```

---

## Contributing

Contributions are welcome — especially new persona packs, module plugins, and skill files.

1. Fork the repository.
2. Create a branch: `git checkout -b feature/my-module`
3. Follow the module structure in `modules/template/` for new modules.
4. Make sure `setup.sh` runs cleanly from scratch on a fresh machine.
5. Open a pull request with a clear description of what the module does and what credentials it requires.

Bug reports and feature requests go in GitHub Issues. Keep issues focused: one bug or one feature per issue.

---

## License

MIT. See [LICENSE](LICENSE).
