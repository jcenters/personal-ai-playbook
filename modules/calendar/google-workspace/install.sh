#!/usr/bin/env bash
# Module: calendar/google-workspace
# Sets up Google Workspace CLI (gws) integration for your Claude Code assistant.

set -euo pipefail

ENV_FILE="${DEPLOY_BASE:-$HOME}/.env"
AGENT_NAME="${AGENT_NAME:-assistant}"
GWS_BIN=""

print_step() { echo ""; echo "  --> $1"; }
print_ok()   { echo "  [OK] $1"; }
print_warn() { echo "  [!]  $1"; }
print_info() { echo "       $1"; }

echo ""
echo "========================================"
echo "  Google Workspace CLI Setup"
echo "  Agent: $AGENT_NAME"
echo "========================================"

# ── Step 1: Find gws ───────────────────────────────────────────────────────
print_step "Checking for Google Workspace CLI (gws)"

# Check common locations
for candidate in \
  "$(command -v gws 2>/dev/null)" \
  "/home/linuxbrew/.linuxbrew/bin/gws" \
  "/usr/local/bin/gws" \
  "$HOME/.local/bin/gws" \
  "/opt/homebrew/bin/gws"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    GWS_BIN="$candidate"
    break
  fi
done

if [ -n "$GWS_BIN" ]; then
  GWS_VERSION=$("$GWS_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  print_ok "gws found at: $GWS_BIN ($GWS_VERSION)"
else
  print_warn "gws CLI not found"
  echo ""
  echo "  Install the Google Workspace CLI:"
  echo ""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "  Via Homebrew:"
    echo "    brew tap wass3r/gws"
    echo "    brew install gws"
    echo ""
  else
    echo "  Via Linuxbrew:"
    echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "    eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\""
    echo "    brew tap wass3r/gws"
    echo "    brew install gws"
    echo ""
    echo "  Or check the project page for binary releases:"
    echo "    https://github.com/wass3r/gws"
  fi
  echo ""
  echo "  After installing gws, re-run this installer."
  exit 1
fi

# ── Step 2: Check if already authenticated ────────────────────────────────
print_step "Checking gws authentication status"
echo ""
AUTH_STATUS=$("$GWS_BIN" auth status 2>&1 || true)
if echo "$AUTH_STATUS" | grep -qi "authenticated\|logged in\|active"; then
  print_ok "gws is authenticated"
  SKIP_AUTH=true
else
  print_info "gws does not appear to be authenticated yet"
  SKIP_AUTH=false
fi

# ── Step 3: Auth login ─────────────────────────────────────────────────────
if [ "$SKIP_AUTH" = false ]; then
  print_step "Authenticate with Google Workspace"
  echo ""
  echo "  This will open a browser window to authorize gws with your Google account."
  echo ""
  echo "  Running: gws auth login"
  echo ""
  "$GWS_BIN" auth login
  echo ""
  print_ok "Authentication complete"
fi

# ── Step 4: Set default account ───────────────────────────────────────────
print_step "Configure default Google account"
echo ""
if grep -q "GWS_DEFAULT_ACCOUNT" "$ENV_FILE" 2>/dev/null; then
  CURRENT_ACCOUNT=$(grep "GWS_DEFAULT_ACCOUNT" "$ENV_FILE" | head -1 | sed 's/.*="\?\([^"]*\)"\?.*/\1/')
  print_ok "GWS_DEFAULT_ACCOUNT already set: $CURRENT_ACCOUNT"
else
  echo "  List authenticated accounts:"
  echo ""
  "$GWS_BIN" auth status 2>&1 | sed 's/^/    /' || true
  echo ""
  read -rp "  Enter the Google account email to use as default: " GWS_ACCOUNT
  if [ -n "$GWS_ACCOUNT" ]; then
    echo "" >> "$ENV_FILE"
    echo "# Google Workspace CLI default account (added by $AGENT_NAME gws module installer)" >> "$ENV_FILE"
    echo "export GWS_DEFAULT_ACCOUNT=\"$GWS_ACCOUNT\"" >> "$ENV_FILE"
    print_ok "GWS_DEFAULT_ACCOUNT=\"$GWS_ACCOUNT\" saved to $ENV_FILE"
  else
    print_warn "No account entered. You can add GWS_DEFAULT_ACCOUNT to $ENV_FILE manually."
  fi
fi

# ── Step 5: Save gws path if not in standard PATH ─────────────────────────
if ! command -v gws &>/dev/null 2>&1; then
  GWS_DIR=$(dirname "$GWS_BIN")
  echo "" >> "$ENV_FILE"
  echo "# gws CLI path" >> "$ENV_FILE"
  echo "export PATH=\"\$PATH:$GWS_DIR\"" >> "$ENV_FILE"
  print_ok "Added $GWS_DIR to PATH in $ENV_FILE"
fi

chmod 600 "$ENV_FILE"

# ── Step 6: Test authentication ────────────────────────────────────────────
print_step "Testing gws authentication"
echo ""
source "$ENV_FILE"
if "$GWS_BIN" auth status &>/dev/null 2>&1; then
  "$GWS_BIN" auth status 2>&1 | sed 's/^/    /'
  echo ""
  print_ok "gws authentication verified"
else
  print_warn "gws auth status returned an error. Try:"
  echo "    $GWS_BIN auth login"
fi

# ── Step 7: Quick reference ────────────────────────────────────────────────
print_step "Common gws commands for your assistant"
echo ""
echo "  Calendar:"
echo "    gws calendar +agenda --today              # Today's agenda"
echo "    gws calendar +agenda --days 7             # Next 7 days"
echo "    gws calendar events insert                # Create an event (interactive)"
echo "    gws calendar events list --max-results 10 # Upcoming events"
echo ""
echo "  Gmail:"
echo "    gws gmail +triage                         # Unread inbox summary"
echo "    gws gmail messages list --unread          # List unread messages"
echo "    gws gmail messages send --to user@example.com --subject 'Subject' --body 'Body'"
echo ""
echo "  Using a specific account:"
echo "    gws --account other@example.com calendar +agenda --today"
echo ""
echo "  Full documentation:"
echo "    gws --help"
echo "    gws calendar --help"
echo "    gws gmail --help"
echo ""

echo "========================================"
echo "  Google Workspace module setup complete."
echo "========================================"
echo ""
