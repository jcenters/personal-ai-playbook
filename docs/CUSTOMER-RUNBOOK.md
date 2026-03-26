# Customer Runbook

This document is for the person who deploys and maintains the system — not the end user. It covers day-to-day operations, common failures, and how to change things after initial setup.

Commands use `{name}` as a placeholder for the actual agent name (e.g., `max`). Replace it everywhere.

---

## Day 1: Post-Setup Verification

Run these checks immediately after `setup.sh` completes, before handing off to the user.

### 1. Verify the environment

```bash
source ~/.{name}/.env
echo "API key set: $([ -n "$ANTHROPIC_API_KEY" ] && echo YES || echo NO)"
echo "Agent name: $AGENT_NAME"
echo "Deploy base: $DEPLOY_BASE"
ls -la ~/.{name}/
ls -la ~/.{name}-config/
```

### 2. Verify agents.json is valid

```bash
python3 -m json.tool ~/.{name}-config/agents.json
```

Should print formatted JSON with no errors. Check that all installed modules are present.

### 3. Test Claude directly

```bash
source ~/.{name}/.env
echo "Say hello in one sentence." | claude --print
```

If this fails: check `ANTHROPIC_API_KEY`, check `claude --version`, check network access.

### 4. Test load-memory.sh

```bash
bash ~/.{name}-config/load-memory.sh
```

Should print the assembled system prompt. If it errors, check the memory directory and `summary.md`.

### 5. Verify the Telegram bot (if configured)

- Open Telegram, find the bot, send it "hello"
- Confirm it responds within 30 seconds
- Confirm it does NOT respond to a message from a different account

### 6. Verify cron jobs

```bash
crontab -l | grep personal-ai-playbook
```

Each installed module's cron entry should appear. If empty, the module may not have installed its cron — re-run the module's `install.sh`.

### 7. Check .env permissions

```bash
stat -c "%a %n" ~/.{name}/.env
```

Should show `600`. If not: `chmod 600 ~/.{name}/.env`

### 8. Send a complete test message

Send via Telegram (or however the user will communicate):

> "What can you do?"

Confirm the response describes the installed agents correctly.

---

## Common Issues and Fixes

### Session crashed / no response from bot

**Symptoms:** Telegram bot stopped responding. Messages go unanswered.

**Diagnosis:**
```bash
# Check if the channel listener is running
pgrep -af telegram
# Check system logs for crash
journalctl -u {name}-telegram --since "1 hour ago" 2>/dev/null || \
  tail -100 ~/.{name}/logs/telegram.log
```

**Fix:**
```bash
# If running as a systemd service:
systemctl restart {name}-telegram

# If running manually:
bash ~/.{name}-config/channels/telegram.sh &
```

If it crashes again immediately, check the log for the error before restarting.

---

### Telegram bot stopped responding — webhook or polling issue

**Symptoms:** Bot was working, then stopped. No crash visible.

**Diagnosis:**
```bash
source ~/.{name}/.env
# Test the bot token is still valid
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | python3 -m json.tool
```

**Fix if token is invalid:** Go to @BotFather, generate a new token, update `.env`:
```bash
# Edit .env manually:
nano ~/.{name}/.env
# Or via sed:
sed -i "s|^export TELEGRAM_BOT_TOKEN=.*|export TELEGRAM_BOT_TOKEN=\"your_new_token\"|" ~/.{name}/.env
# Restart the channel listener
systemctl restart {name}-telegram
```

**Fix if token is valid but bot is stuck:**
```bash
# Clear any stuck getUpdates offset
source ~/.{name}/.env
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=-1"
# Then restart the listener
systemctl restart {name}-telegram
```

---

### Cron job not firing

**Symptoms:** Morning briefing not arriving, system health report not appearing at 2 AM.

**Diagnosis:**
```bash
# Verify the cron entry exists
crontab -l | grep personal-ai-playbook

# Check cron daemon is running
systemctl status cron 2>/dev/null || systemctl status crond 2>/dev/null

# Check the cron log
grep CRON /var/log/syslog | tail -50
# or
journalctl -u cron --since "24 hours ago" | tail -50

# Check the job's own log
cat ~/.{name}/logs/system-health-cron.log
```

**Fix — cron entry missing:**
```bash
# Re-run the module's install script to re-add the cron
DEPLOY_BASE=~/.{name} AGENT_NAME={name} bash modules/agents/system-health/install.sh
```

**Fix — cron entry exists but script fails:**
```bash
# Run the script manually to see the error
source ~/.{name}/.env
bash ~/.{name}-config/scripts/health-check.sh
```

**Fix — timezone mismatch (briefing arrives at wrong time):**
```bash
# Check what timezone cron uses
cat /etc/timezone
date
# Compare to TZ in .env
grep TZ ~/.{name}/.env
# Update cron time to match server's local time, or set TZ= in the cron line:
# 30 7 * * * TZ=America/Chicago bash /path/to/script.sh >> log 2>&1
```

---

### Memory filling up

**Symptoms:** `store.jsonl` growing large; `summary.md` regeneration taking too long or hitting token limits.

**Diagnosis:**
```bash
wc -l ~/.{name}/memory/store.jsonl
du -sh ~/.{name}/memory/
```

**Fix — prune old events:**
```bash
# Keep only the last 90 days of events (adjust as needed)
CUTOFF=$(date -d "90 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
         date -v-90d +%Y-%m-%dT%H:%M:%SZ)
python3 - << EOF
import json
with open("$HOME/.{name}/memory/store.jsonl") as f:
    lines = f.readlines()
kept = [l for l in lines if json.loads(l).get("ts","") >= "$CUTOFF"]
with open("$HOME/.{name}/memory/store.jsonl", "w") as f:
    f.writelines(kept)
print(f"Pruned {len(lines)-len(kept)} old events. Kept {len(kept)}.")
EOF

# Regenerate summary after pruning
bash ~/.{name}-config/scripts/compress-memory.sh
```

**Fix — archive the log rather than deleting:**
```bash
ARCHIVE_DATE=$(date +%Y-%m-%d)
cp ~/.{name}/memory/store.jsonl ~/.{name}/memory/store-archive-${ARCHIVE_DATE}.jsonl
# Then prune store.jsonl as above
```

---

### Claude auth expired / API key rejected

**Symptoms:** Error `401 Unauthorized` or `Invalid API key` in logs.

**Diagnosis:**
```bash
source ~/.{name}/.env
echo "Key starts with: ${ANTHROPIC_API_KEY:0:10}..."
# Test the key directly
curl -s -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  https://api.anthropic.com/v1/models | python3 -m json.tool | head -5
```

**Fix:**
1. Generate a new key at https://console.anthropic.com
2. Update `.env`:
   ```bash
   sed -i "s|^export ANTHROPIC_API_KEY=.*|export ANTHROPIC_API_KEY=\"sk-ant-...\"|" ~/.{name}/.env
   ```
3. If using 1Password, update the stored item:
   ```bash
   op item edit "Anthropic API" --vault Max "api_key=sk-ant-..."
   ```
4. Restart any running services

---

## Updating the System

### Pulling a new release

```bash
cd ~/personal-ai-playbook
git pull origin main

# Review the changelog before applying:
git log --oneline HEAD@{1}..HEAD
```

After pulling, re-run any module install scripts that changed:

```bash
DEPLOY_BASE=~/.{name} AGENT_NAME={name} bash modules/agents/fitness-coach/install.sh
```

Most module installs are idempotent — re-running them is safe.

### Updating the persona / CLAUDE.md

```bash
nano ~/.{name}-config/CLAUDE.md
# Changes take effect on the next message — no restart needed
```

### Updating Python or system dependencies

```bash
# Check what the system uses
python3 --version
# Update if needed — platform-specific:
sudo apt update && sudo apt upgrade python3   # Debian/Ubuntu
brew upgrade python                            # macOS
```

---

## Adding New Modules Post-Install

```bash
# Example: adding the researcher module after initial setup
DEPLOY_BASE=~/.{name} AGENT_NAME={name} bash modules/agents/researcher/install.sh

# Verify agents.json was updated
python3 -m json.tool ~/.{name}-config/agents.json | grep '"name"'

# Reload the channel listener so it picks up the new agent
systemctl restart {name}-telegram
```

You do not need to re-run `setup.sh`. Module installs are self-contained.

---

## Changing the Persona

The persona is defined in two places:

1. **`~/.{name}-config/CLAUDE.md`** — the system prompt that defines personality, rules, and context
2. **`AGENT_NAME` in `.env`** — controls directory paths and configuration keys

### To change the personality only (keep the name):

```bash
nano ~/.{name}-config/CLAUDE.md
# Edit the character description, tone instructions, etc.
# No restart needed — effective on next message
```

### To rename the persona entirely:

This is a more involved operation because `AGENT_NAME` affects all directory paths.

```bash
OLD_NAME=max
NEW_NAME=ada

# 1. Stop any running services
systemctl stop ${OLD_NAME}-telegram 2>/dev/null || true

# 2. Copy the data directory
cp -r ~/.$OLD_NAME ~/.$NEW_NAME
cp -r ~/${OLD_NAME}-config ~/${NEW_NAME}-config

# 3. Update .env
sed -i "s|AGENT_NAME=${OLD_NAME}|AGENT_NAME=${NEW_NAME}|g" ~/.$NEW_NAME/.env
sed -i "s|/.$OLD_NAME/|/.$NEW_NAME/|g" ~/.$NEW_NAME/.env
sed -i "s|/${OLD_NAME}-config/|/${NEW_NAME}-config/|g" ~/.$NEW_NAME/.env

# 4. Update CLAUDE.md references
sed -i "s/${OLD_NAME}/${NEW_NAME}/gi" ~/.$NEW_NAME/.env

# 5. Update cron jobs
crontab -l | sed "s/${OLD_NAME}/${NEW_NAME}/g" | crontab -

# 6. Update and restart systemd service (if using one)
# Edit /etc/systemd/system/{name}-telegram.service
# systemctl daemon-reload && systemctl start {new-name}-telegram

# 7. Verify
source ~/.$NEW_NAME/.env
echo "Agent name: $AGENT_NAME"
```

---

## Adding a New Messaging Channel

Channels live in `~/.{name}-config/channels/`. Each channel is a script that:
1. Listens for incoming messages
2. Passes them through `claude --print --append-system-prompt "$SYSTEM_PROMPT"`
3. Sends the response back

To add a new channel:

```bash
# Copy the Telegram channel as a template
cp ~/.{name}-config/channels/telegram.sh ~/.{name}-config/channels/my-channel.sh
nano ~/.{name}-config/channels/my-channel.sh
```

Key things to adapt in the template:
- The listener loop (replace polling with your channel's event source)
- The trust/allowlist check (match your channel's user identity mechanism)
- The reply mechanism (send back however your channel expects)

Install as a systemd service:

```bash
sudo tee /etc/systemd/system/{name}-my-channel.service << EOF
[Unit]
Description={Name} AI — my-channel listener
After=network.target

[Service]
User=$USER
EnvironmentFile=$HOME/.{name}/.env
ExecStart=/bin/bash $HOME/.{name}-config/channels/my-channel.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now {name}-my-channel
```

---

## Monitoring

### Log locations

| Log | Path | What it contains |
|-----|------|-----------------|
| Telegram channel | `~/.{name}/logs/telegram.log` | All incoming messages, errors |
| System health cron | `~/.{name}/logs/system-health-cron.log` | Daily health run output |
| Morning briefing | `~/.{name}/logs/morning-briefing.log` | Briefing send attempts |
| Memory compression | `~/.{name}/logs/compress-memory.log` | Nightly compression run |
| General errors | `~/.{name}/logs/errors.log` | Unhandled errors from any script |

### What to watch

- `telegram.log` — high error rate or crashes indicate bot token problems or network issues
- `system-health-cron.log` — contains the actual health check results; review weekly
- `store.jsonl` line count — run `wc -l ~/.{name}/memory/store.jsonl` monthly; prune if over ~5,000 lines
- Disk space on the deploy partition — `df -h $HOME`

### Simple health check command

```bash
source ~/.{name}/.env
echo "=== Service status ===" && \
  systemctl is-active {name}-telegram 2>/dev/null || echo "not a service" && \
echo "=== Recent errors ===" && \
  tail -20 ~/.{name}/logs/errors.log 2>/dev/null || echo "no error log" && \
echo "=== Memory size ===" && \
  wc -l ~/.{name}/memory/store.jsonl && \
echo "=== Disk ===" && \
  df -h "$HOME" | tail -1
```

---

## Backup

### What to back up

| Path | Frequency | Why |
|------|-----------|-----|
| `~/.{name}/.env` | After every change | Contains secrets and all config |
| `~/.{name}/memory/` | Daily | Core memory — loss means starting over |
| `~/.{name}-config/` | After every change | Agents, persona, channel scripts |
| `~/.{name}/notes/` | Daily (if local-only module) | User's saved notes |
| `~/.{name}/fitness/` | Weekly | Workout history |

### Simple rsync backup

```bash
# To a local external drive
rsync -avz --exclude=".env" \
  ~/.$AGENT_NAME/ \
  /mnt/backup/ai-assistant/

# Back up .env separately with stricter permissions
install -m 600 ~/.$AGENT_NAME/.env /mnt/backup/ai-assistant/.env.backup

# To a remote server via SSH
rsync -avz -e "ssh -i ~/.ssh/backup_key" \
  ~/.$AGENT_NAME/ \
  backup-user@backup-host:/backups/ai-assistant/
```

### Restore from backup

```bash
# Stop services first
systemctl stop {name}-telegram 2>/dev/null || true

# Restore data
rsync -avz /mnt/backup/ai-assistant/ ~/.$AGENT_NAME/
cp -p /mnt/backup/ai-assistant/.env.backup ~/.$AGENT_NAME/.env
chmod 600 ~/.$AGENT_NAME/.env

# Verify and restart
source ~/.$AGENT_NAME/.env
echo "Agent: $AGENT_NAME"
systemctl start {name}-telegram
```

---

## Uninstall

Complete removal of the system.

### 1. Stop and disable services

```bash
systemctl stop {name}-telegram 2>/dev/null || true
systemctl disable {name}-telegram 2>/dev/null || true
sudo rm -f /etc/systemd/system/{name}-telegram.service
sudo systemctl daemon-reload
```

### 2. Remove cron jobs

```bash
# Remove all cron entries tagged with personal-ai-playbook
crontab -l | grep -v "personal-ai-playbook" | crontab -

# Verify they're gone
crontab -l | grep personal-ai-playbook && echo "WARNING: entries remain" || echo "Cron clean"
```

### 3. Remove data and config directories

```bash
# Back up first if you want to preserve any data:
cp -r ~/.$AGENT_NAME ~/.$AGENT_NAME.bak
cp -r ~/${AGENT_NAME}-config ~/${AGENT_NAME}-config.bak

# Then remove:
rm -rf ~/.$AGENT_NAME
rm -rf ~/${AGENT_NAME}-config
```

### 4. Remove the playbook source

```bash
rm -rf ~/personal-ai-playbook
```

### 5. Revoke credentials

- Revoke the Anthropic API key at https://console.anthropic.com
- Delete the Telegram bot via @BotFather (`/deletebot`)
- Revoke any Brave API key if the researcher module was used

### 6. Verify removal

```bash
ls ~/.$AGENT_NAME 2>/dev/null && echo "WARNING: data dir remains" || echo "Data dir removed"
crontab -l | grep personal-ai-playbook && echo "WARNING: cron entries remain" || echo "Cron clean"
systemctl status {name}-telegram 2>/dev/null && echo "WARNING: service still exists" || echo "Service removed"
```

---

*Document version: 1.0 — personal-ai-playbook*
