#!/usr/bin/env bash
# Module: storage/obsidian
# Sets up Obsidian vault integration for your Claude Code assistant.

set -euo pipefail

ENV_FILE="${DEPLOY_BASE:-$HOME}/.env"
DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-assistant}"
AGENT_DIR="$DEPLOY_BASE/.$AGENT_NAME"
CLAUDE_MD="$AGENT_DIR/CLAUDE.md"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  Obsidian Vault Integration Setup"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Check if already configured ───────────────────────────────────
if grep -q "OBSIDIAN_VAULT_PATH" "$ENV_FILE" 2>/dev/null; then
  CURRENT_VAULT=$(grep "OBSIDIAN_VAULT_PATH" "$ENV_FILE" | head -1 | sed 's/.*="\?\([^"]*\)"\?.*/\1/')
  print_ok "OBSIDIAN_VAULT_PATH already set: $CURRENT_VAULT"
  echo ""
  echo "  To change the vault path, remove the OBSIDIAN_VAULT_PATH line from"
  echo "  $ENV_FILE and re-run this installer."
  VAULT_PATH="$CURRENT_VAULT"
  SKIP_VAULT=true
else
  SKIP_VAULT=false
fi

# ── Step 2: Prompt for vault path ─────────────────────────────────────────
if [ "$SKIP_VAULT" = false ]; then
  print_step "Configure your Obsidian vault path"
  echo ""
  echo "  Enter the full path to your Obsidian vault directory."
  echo "  This is the folder that contains your .obsidian/ directory."
  echo ""
  echo "  Common locations:"
  echo "    $HOME/vault"
  echo "    $HOME/notes"
  echo "    $HOME/workspace"
  echo "    $HOME/Documents/Obsidian"
  echo ""

  while true; do
    read -rp "  Vault path: " VAULT_PATH_INPUT
    # Expand tilde
    VAULT_PATH="${VAULT_PATH_INPUT/#\~/$HOME}"
    if [ -d "$VAULT_PATH" ]; then
      print_ok "Directory exists: $VAULT_PATH"
      break
    else
      print_warn "Directory not found: $VAULT_PATH"
      echo ""
      read -rp "  Create this directory? (y/n): " CREATE_DIR
      if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
        mkdir -p "$VAULT_PATH"
        print_ok "Created: $VAULT_PATH"
        break
      else
        echo "  Enter a different path or Ctrl+C to exit."
      fi
    fi
  done

  echo "" >> "$ENV_FILE"
  echo "# Obsidian vault path (added by $AGENT_NAME obsidian module installer)" >> "$ENV_FILE"
  echo "export OBSIDIAN_VAULT_PATH=\"$VAULT_PATH\"" >> "$ENV_FILE"
  print_ok "OBSIDIAN_VAULT_PATH saved to $ENV_FILE"
fi

chmod 600 "$ENV_FILE"

# ── Step 3: Check for ob sync daemon ──────────────────────────────────────
print_step "Checking for Obsidian Sync daemon (ob)"
echo ""
if command -v ob &>/dev/null; then
  print_ok "ob CLI is available: $(command -v ob)"
  echo ""
  echo "  Obsidian Sync via 'ob' is available. To run the sync daemon continuously:"
  echo ""
  echo "    ob sync --continuous"
  echo ""
  echo "  To check if it is currently running:"
  echo ""
  echo "    systemctl --user status ob-sync   # If running as a systemd service"
  echo "    pgrep -a ob                        # If running as a background process"
  echo ""
  echo "  To set up as a systemd user service:"
  echo ""
  echo "    systemctl --user enable --now ob-sync"
  echo ""
else
  print_info "ob CLI not found (this is optional)"
  echo ""
  echo "  The 'ob' tool provides continuous Obsidian Sync on headless systems."
  echo "  If you are using Obsidian Sync (paid feature) to keep your vault"
  echo "  in sync across devices including this machine, you may want it."
  echo ""
  echo "  Without ob, your vault is still accessible — it just will not sync"
  echo "  automatically unless Obsidian is open on this machine."
  echo ""
  echo "  To get ob: https://github.com/vrtmrz/obsidian-livesync or check"
  echo "  your Obsidian community plugins for self-hosted sync options."
fi

# ── Step 4: Update CLAUDE.md with vault context ───────────────────────────
print_step "Adding vault path to agent context"
echo ""
if [ -f "$CLAUDE_MD" ]; then
  if grep -q "OBSIDIAN_VAULT_PATH\|Obsidian vault" "$CLAUDE_MD" 2>/dev/null; then
    print_ok "Obsidian vault reference already present in CLAUDE.md"
  else
    cat >> "$CLAUDE_MD" << EOF

## Obsidian Vault

The primary notes vault is at: $VAULT_PATH

When reading or writing notes, use this path. Always append to daily notes rather than overwriting them. Daily notes are at: $VAULT_PATH/$(date +%Y/%m-%d 2>/dev/null || echo "YYYY/MM-DD").md (adjust to match the vault's actual folder structure).

Use \`OBSIDIAN_VAULT_PATH\` environment variable for the vault root path in scripts.
EOF
    print_ok "Vault context added to $CLAUDE_MD"
  fi
else
  print_warn "CLAUDE.md not found at $CLAUDE_MD — vault context not added"
  print_info "You can add it manually after setup completes"
fi

# ── Step 5: Verify vault ───────────────────────────────────────────────────
print_step "Vault summary"
echo ""
source "$ENV_FILE"
echo "  Vault path: ${OBSIDIAN_VAULT_PATH:-not set}"
echo ""

if [ -d "${OBSIDIAN_VAULT_PATH:-}" ]; then
  NOTE_COUNT=$(find "$OBSIDIAN_VAULT_PATH" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  print_ok "Vault accessible — $NOTE_COUNT .md files found"
  if [ -d "$OBSIDIAN_VAULT_PATH/.obsidian" ]; then
    print_ok ".obsidian directory present (Obsidian has opened this vault)"
  else
    print_warn "No .obsidian directory — Obsidian may not have opened this vault yet"
  fi
else
  print_warn "Vault directory not accessible: ${OBSIDIAN_VAULT_PATH:-not set}"
fi

# ── Step 6: Usage notes ────────────────────────────────────────────────────
print_step "Using your vault with your assistant"
echo ""
echo "  Your assistant can read and write to the vault at OBSIDIAN_VAULT_PATH."
echo ""
echo "  Good practices:"
echo "  - For daily notes: always append, never overwrite"
echo "  - Use consistent frontmatter (tags, date) when creating new notes"
echo "  - Keep attachments in $VAULT_PATH/attachments/ or wherever your vault config specifies"
echo ""
echo "  If Obsidian Sync is running, changes made by your assistant will sync"
echo "  to your other devices automatically."
echo ""

echo "========================================"
echo "  Obsidian module setup complete."
echo "========================================"
echo ""
