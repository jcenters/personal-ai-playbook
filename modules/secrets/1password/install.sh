#!/usr/bin/env bash
# Module: secrets/1password
# Sets up 1Password CLI integration for your Claude Code assistant.

set -euo pipefail

ENV_FILE="${DEPLOY_BASE:-$HOME}/.env"
AGENT_NAME="${AGENT_NAME:-assistant}"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  1Password CLI Integration Setup"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Check if op is installed ──────────────────────────────────────
print_step "Checking for 1Password CLI (op)"
if command -v op &>/dev/null; then
  OP_VERSION=$(op --version 2>/dev/null || echo "unknown")
  print_ok "op CLI found: version $OP_VERSION"
else
  print_warn "op CLI not found"
  echo ""
  echo "  Install the 1Password CLI:"
  echo ""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "    brew install 1password-cli"
    echo ""
    echo "  Or download from: https://developer.1password.com/docs/cli/get-started/"
  else
    echo "  On Debian/Ubuntu:"
    echo "    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \\"
    echo "      sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg"
    echo "    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \\"
    echo "      https://downloads.1password.com/linux/debian/amd64 stable main' | \\"
    echo "      sudo tee /etc/apt/sources.list.d/1password.list"
    echo "    sudo apt update && sudo apt install 1password-cli"
    echo ""
    echo "  On other Linux systems:"
    echo "    https://developer.1password.com/docs/cli/get-started/"
  fi
  echo ""
  echo "  After installing op, re-run this installer."
  exit 1
fi

# ── Step 2: Check if token already exists ─────────────────────────────────
if grep -q "OP_SERVICE_ACCOUNT_TOKEN" "$ENV_FILE" 2>/dev/null; then
  print_ok "OP_SERVICE_ACCOUNT_TOKEN already present in $ENV_FILE"
  SKIP_TOKEN=true
else
  SKIP_TOKEN=false
fi

# ── Step 3: Service account token setup ───────────────────────────────────
if [ "$SKIP_TOKEN" = false ]; then
  print_step "Create a 1Password Service Account"
  echo ""
  echo "  A service account lets your assistant read secrets from 1Password"
  echo "  without interactive login. It is scoped to specific vaults."
  echo ""
  echo "  1. Go to: https://my.1password.com/integrations/infrastructure-secrets"
  echo "     (Or: 1Password > Integrations > Developer > Service Accounts)"
  echo "  2. Click 'New Service Account'"
  echo "  3. Give it a name (e.g., '${AGENT_NAME} assistant')"
  echo "  4. Grant it read access to the vault(s) your assistant will need"
  echo "     - Read access is sufficient for secret lookups"
  echo "     - Do not grant write access unless your assistant needs to store secrets"
  echo "  5. Copy the token — it starts with 'ops_' and is shown only once"
  echo ""

  while true; do
    read -rp "  Paste your service account token: " SA_TOKEN
    if [[ "$SA_TOKEN" =~ ^ops_[A-Za-z0-9]{20,} ]]; then
      break
    else
      print_warn "That does not look like a valid service account token (should start with 'ops_')."
      echo "  Try again, or Ctrl+C to exit."
    fi
  done

  echo "" >> "$ENV_FILE"
  echo "# 1Password service account token (added by $AGENT_NAME 1password module installer)" >> "$ENV_FILE"
  echo "export OP_SERVICE_ACCOUNT_TOKEN=\"$SA_TOKEN\"" >> "$ENV_FILE"
  print_ok "OP_SERVICE_ACCOUNT_TOKEN saved to $ENV_FILE"
fi

# ── Step 4: Set permissions on .env ────────────────────────────────────────
chmod 600 "$ENV_FILE"
print_ok ".env permissions set to 600"

# ── Step 5: Vault name setup ───────────────────────────────────────────────
print_step "Configure your vault name"
echo ""
if grep -q "OP_VAULT_NAME" "$ENV_FILE" 2>/dev/null; then
  CURRENT_VAULT=$(grep "OP_VAULT_NAME" "$ENV_FILE" | head -1 | sed 's/.*="\?\([^"]*\)"\?.*/\1/')
  print_ok "OP_VAULT_NAME already set: $CURRENT_VAULT"
else
  echo "  Enter the name of the 1Password vault your assistant should use."
  echo "  This is the vault name as it appears in your 1Password account."
  echo "  If unsure, you can run: op vault list  (after the next step)"
  echo ""
  read -rp "  Vault name: " VAULT_NAME
  if [ -n "$VAULT_NAME" ]; then
    echo "" >> "$ENV_FILE"
    echo "export OP_VAULT_NAME=\"$VAULT_NAME\"" >> "$ENV_FILE"
    print_ok "OP_VAULT_NAME=\"$VAULT_NAME\" saved to $ENV_FILE"
  else
    print_warn "No vault name entered. You can add OP_VAULT_NAME to $ENV_FILE manually."
  fi
fi

# ── Step 6: Test connection ────────────────────────────────────────────────
print_step "Testing 1Password connection"
source "$ENV_FILE"
echo ""
if op vault list &>/dev/null 2>&1; then
  echo "  op vault list output:"
  echo ""
  op vault list | sed 's/^/    /'
  echo ""
  print_ok "1Password CLI authenticated successfully"
else
  print_warn "Could not connect to 1Password. Check your token and try:"
  echo ""
  echo "    source $ENV_FILE && op vault list"
  echo ""
  echo "  Common issues:"
  echo "  - Token was copied with extra whitespace"
  echo "  - Service account does not have access to any vaults"
  echo "  - Token was revoked or expired"
fi

# ── Step 7: Usage reference ────────────────────────────────────────────────
print_step "Using 1Password secrets in your assistant"
echo ""
echo "  Reference pattern:"
echo "    op read \"op://VaultName/ItemName/field\""
echo ""
echo "  Examples:"
echo "    op read \"op://\${OP_VAULT_NAME}/Twitter/api_key\""
echo "    op read \"op://\${OP_VAULT_NAME}/Database/password\""
echo "    op read \"op://\${OP_VAULT_NAME}/Stripe/secret_key\""
echo ""
echo "  In your CLAUDE.md or tools, reference secrets with op read rather"
echo "  than hardcoding them. This keeps secrets out of config files."
echo ""

echo "========================================"
echo "  1Password module setup complete."
echo "========================================"
echo ""
