#!/usr/bin/env bash
# Module: secrets/bitwarden
# Sets up Bitwarden CLI integration for your Claude Code assistant.

set -euo pipefail

ENV_FILE="${DEPLOY_BASE:-$HOME}/.env"
AGENT_NAME="${AGENT_NAME:-assistant}"

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  Bitwarden CLI Integration Setup"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Check if bw is installed ──────────────────────────────────────
print_step "Checking for Bitwarden CLI (bw)"
if command -v bw &>/dev/null; then
  BW_VERSION=$(bw --version 2>/dev/null || echo "unknown")
  print_ok "bw CLI found: version $BW_VERSION"
else
  print_warn "bw CLI not found"
  echo ""
  echo "  Install the Bitwarden CLI:"
  echo ""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "    brew install bitwarden-cli"
  else
    echo "  Via npm (requires Node.js):"
    echo "    npm install -g @bitwarden/cli"
    echo ""
    echo "  Via snap:"
    echo "    sudo snap install bw"
    echo ""
    echo "  Download directly from:"
    echo "    https://bitwarden.com/help/cli/"
  fi
  echo ""
  echo "  After installing bw, re-run this installer."
  exit 1
fi

# ── Step 2: Check if session already exists ────────────────────────────────
if grep -q "BW_SESSION" "$ENV_FILE" 2>/dev/null; then
  print_ok "BW_SESSION already present in $ENV_FILE"
  echo ""
  echo "  Note: Bitwarden session tokens expire. If your assistant cannot access"
  echo "  secrets, re-run this installer to generate a fresh session token."
  echo ""
  SKIP_LOGIN=true
else
  SKIP_LOGIN=false
fi

# ── Step 3: Configure server (for self-hosted) ─────────────────────────────
if [ "$SKIP_LOGIN" = false ]; then
  print_step "Bitwarden server configuration"
  echo ""
  echo "  Are you using:"
  echo "  1) Bitwarden.com (cloud)"
  echo "  2) A self-hosted Bitwarden server"
  echo ""
  read -rp "  Enter 1 or 2: " SERVER_CHOICE
  if [ "$SERVER_CHOICE" = "2" ]; then
    read -rp "  Enter your Bitwarden server URL (e.g., https://vault.example.com): " BW_SERVER
    bw config server "$BW_SERVER"
    print_ok "Server configured: $BW_SERVER"
  else
    print_info "Using Bitwarden.com cloud"
  fi

  # ── Step 4: Login ──────────────────────────────────────────────────────
  print_step "Log in to Bitwarden"
  echo ""
  echo "  You will be prompted for your Bitwarden email and master password."
  echo "  If you have two-factor authentication enabled, you will also be prompted"
  echo "  for your 2FA code."
  echo ""
  echo "  Running: bw login"
  echo ""

  BW_SESSION_TOKEN=""
  # Attempt login and capture session token
  if LOGIN_OUTPUT=$(bw login --raw 2>&1); then
    BW_SESSION_TOKEN="$LOGIN_OUTPUT"
    print_ok "Login successful"
  else
    # bw login may already be logged in
    if echo "$LOGIN_OUTPUT" | grep -q "already logged in"; then
      print_info "Already logged in. Unlocking to get session token..."
      echo ""
      echo "  Running: bw unlock --raw"
      BW_SESSION_TOKEN=$(bw unlock --raw)
    else
      print_warn "Login failed. Output:"
      echo "$LOGIN_OUTPUT"
      echo ""
      echo "  Try running 'bw login' manually and then re-running this installer."
      exit 1
    fi
  fi

  if [ -z "$BW_SESSION_TOKEN" ]; then
    print_warn "Could not capture session token. Running bw unlock manually..."
    echo ""
    BW_SESSION_TOKEN=$(bw unlock --raw)
  fi

  if [ -n "$BW_SESSION_TOKEN" ]; then
    # Remove any existing BW_SESSION entry
    if grep -q "BW_SESSION" "$ENV_FILE" 2>/dev/null; then
      TMPFILE=$(mktemp)
      grep -v "BW_SESSION" "$ENV_FILE" > "$TMPFILE"
      mv "$TMPFILE" "$ENV_FILE"
    fi
    echo "" >> "$ENV_FILE"
    echo "# Bitwarden session token (added by $AGENT_NAME bitwarden module installer)" >> "$ENV_FILE"
    echo "# Note: Session tokens expire. Re-run this installer to refresh." >> "$ENV_FILE"
    echo "export BW_SESSION=\"$BW_SESSION_TOKEN\"" >> "$ENV_FILE"
    print_ok "BW_SESSION saved to $ENV_FILE"
  else
    print_warn "Could not capture session token. Add BW_SESSION manually to $ENV_FILE"
    echo ""
    echo "  To get a session token manually:"
    echo "    bw unlock --raw"
    echo "  Then add the output to your .env:"
    echo "    export BW_SESSION=\"<token>\""
  fi
fi

# ── Step 5: Set permissions on .env ────────────────────────────────────────
chmod 600 "$ENV_FILE"
print_ok ".env permissions set to 600"

# ── Step 6: Test the connection ────────────────────────────────────────────
print_step "Testing Bitwarden access"
source "$ENV_FILE"
echo ""
if bw status 2>/dev/null | grep -q '"status":"unlocked"'; then
  print_ok "Bitwarden vault is unlocked and accessible"
else
  STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
  print_warn "Bitwarden status: $STATUS"
  echo "  If status is 'locked', your session token may have expired."
  echo "  Run: bw unlock --raw  and update BW_SESSION in $ENV_FILE"
fi

# ── Step 7: Usage reference ────────────────────────────────────────────────
print_step "Using Bitwarden secrets in your assistant"
echo ""
echo "  Retrieve a password by item name:"
echo "    bw get password \"Item Name\""
echo ""
echo "  Retrieve a specific field:"
echo "    bw get item \"Item Name\" | jq -r '.fields[] | select(.name==\"api_key\") | .value'"
echo ""
echo "  List all items:"
echo "    bw list items | jq '.[].name'"
echo ""
echo "  Retrieve a secure note:"
echo "    bw get notes \"Note Name\""
echo ""
echo "  All bw commands require BW_SESSION to be set in the environment."
echo "  The session token is included automatically when your assistant sources $ENV_FILE"
echo ""
echo "  Session tokens expire after a period of inactivity (configurable in Bitwarden settings)."
echo "  When expired, run 'bw unlock --raw' and update BW_SESSION in $ENV_FILE"
echo ""

echo "========================================"
echo "  Bitwarden module setup complete."
echo "========================================"
echo ""
