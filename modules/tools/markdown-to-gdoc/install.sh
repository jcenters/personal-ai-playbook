#!/usr/bin/env bash
# markdown-to-gdoc/install.sh
# Installs gdoc.py and its dependencies for converting Markdown files to Google Docs.
#
# Env vars:
#   DEPLOY_BASE  — base deployment directory (default: $HOME)
#   AGENT_NAME   — assistant name (default: max)
#   GWS_CREDS    — path to gws credentials.json (default: ~/.config/gws/credentials.json)
#
# Usage:
#   DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-max}"
GWS_CREDS="${GWS_CREDS:-$HOME/.config/gws/credentials.json}"

SCRIPTS_DIR="$DEPLOY_BASE/.$AGENT_NAME/scripts"
SCRIPT_PATH="$SCRIPTS_DIR/gdoc.py"

echo "==> Installing markdown-to-gdoc to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

# Check Python 3
PYTHON_BIN=$(command -v python3 || true)
if [[ -z "$PYTHON_BIN" ]]; then
    echo "  ERROR: python3 not found."
    exit 1
fi

# Install Python dependencies (into user or system site-packages)
echo "  Installing Python dependencies"
"$PYTHON_BIN" -m pip install --quiet --upgrade google-auth google-api-python-client markdown

# Check for credentials.json
if [[ ! -f "$GWS_CREDS" ]]; then
    echo ""
    echo "  WARNING: $GWS_CREDS not found."
    echo "  Run 'gws auth login' first, or place credentials.json manually."
    echo "  The file must contain: refresh_token, client_id, client_secret."
    echo "  See README.md for the manual credentials format."
    echo ""
else
    echo "  credentials.json found at $GWS_CREDS"
fi

# Write gdoc.py
cat > "$SCRIPT_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""
gdoc.py — Create a Google Doc from a Markdown file.

Converts Markdown to HTML, uploads to Drive as a Google Doc.
Reads OAuth credentials from ~/.config/gws/credentials.json.

Usage:
    gdoc.py path/to/file.md
    gdoc.py path/to/file.md --title "Custom Title"
    gdoc.py path/to/file.md --share email@example.com
    gdoc.py path/to/file.md --title "My Draft" --share editor@example.com

Output:
    Created: My Draft
    URL: https://docs.google.com/document/d/...
"""
import sys
import os
import json
import argparse
from pathlib import Path

CREDS_PATH = os.environ.get("GWS_CREDS", os.path.expanduser("~/.config/gws/credentials.json"))

def load_credentials():
    if not os.path.exists(CREDS_PATH):
        raise FileNotFoundError(
            f"credentials.json not found at {CREDS_PATH}\n"
            "Run 'gws auth login' or set GWS_CREDS env var."
        )
    with open(CREDS_PATH) as f:
        data = json.load(f)
    required = {"refresh_token", "client_id", "client_secret"}
    missing = required - set(data.keys())
    if missing:
        raise ValueError(f"credentials.json missing fields: {missing}")
    return data

def get_credentials(creds_data: dict):
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    creds = Credentials(
        token=None,
        refresh_token=creds_data["refresh_token"],
        client_id=creds_data["client_id"],
        client_secret=creds_data["client_secret"],
        token_uri="https://oauth2.googleapis.com/token",
    )
    creds.refresh(Request())
    return creds

def markdown_to_html(md_path: str) -> str:
    import markdown
    with open(md_path) as f:
        text = f.read()
    return markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "footnotes", "attr_list"],
    )

def create_google_doc(creds, title: str, html: str) -> str:
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaInMemoryUpload

    drive = build("drive", "v3", credentials=creds)

    media = MediaInMemoryUpload(
        html.encode("utf-8"),
        mimetype="text/html",
        resumable=False,
    )
    file_metadata = {
        "name": title,
        "mimeType": "application/vnd.google-apps.document",
    }
    result = drive.files().create(
        body=file_metadata,
        media_body=media,
        fields="id,webViewLink",
    ).execute()
    return result["id"], result["webViewLink"]

def share_doc(creds, file_id: str, email: str):
    from googleapiclient.discovery import build
    drive = build("drive", "v3", credentials=creds)
    drive.permissions().create(
        fileId=file_id,
        body={"type": "user", "role": "writer", "emailAddress": email},
        sendNotificationEmail=False,
    ).execute()

def main():
    parser = argparse.ArgumentParser(description="Upload a Markdown file as a Google Doc")
    parser.add_argument("file", help="Path to the Markdown file")
    parser.add_argument("--title", help="Google Doc title (default: filename without extension)")
    parser.add_argument("--share", metavar="EMAIL", help="Share with this email as writer")
    args = parser.parse_args()

    md_path = args.file
    if not os.path.exists(md_path):
        print(f"Error: file not found: {md_path}", file=sys.stderr)
        sys.exit(1)

    title = args.title or Path(md_path).stem

    creds_data = load_credentials()
    creds = get_credentials(creds_data)
    html = markdown_to_html(md_path)
    file_id, url = create_google_doc(creds, title, html)

    if args.share:
        share_doc(creds, file_id, args.share)
        print(f"Shared with: {args.share}")

    print(f"Created: {title}")
    print(f"URL: {url}")

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$SCRIPT_PATH"

# Write env vars
ENV_FILE="$DEPLOY_BASE/.env"
touch "$ENV_FILE"
if ! grep -q "^export GWS_CREDS=" "$ENV_FILE" 2>/dev/null; then
    echo "export GWS_CREDS=\"$GWS_CREDS\"" >> "$ENV_FILE"
    echo "  Added GWS_CREDS to $ENV_FILE"
fi

echo ""
echo "==> markdown-to-gdoc installed."
echo ""
echo "    Script:      $SCRIPT_PATH"
echo "    Credentials: $GWS_CREDS"
echo ""
echo "    Usage:"
echo "      python3 $SCRIPT_PATH draft.md"
echo "      python3 $SCRIPT_PATH draft.md --title 'My Article'"
echo "      python3 $SCRIPT_PATH draft.md --share colleague@example.com"
echo "      python3 $SCRIPT_PATH draft.md --title 'Draft' --share editor@example.com"
echo ""
echo "    Prerequisites: gws CLI auth (gws auth login) must be completed first."
echo "    credentials.json must contain: refresh_token, client_id, client_secret"
echo ""
