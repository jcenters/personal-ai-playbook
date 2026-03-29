# markdown-to-gdoc

Converts a local Markdown file to a Google Doc via the Drive API. Uses the same OAuth credentials that the `gws` CLI writes to `~/.config/gws/credentials.json` — no separate auth setup needed if you've already run `gws auth login`.

## What it does

- Reads a `.md` file from disk
- Converts Markdown to HTML using python-markdown (with tables, fenced code blocks, footnotes, and attr_list extensions)
- Uploads the HTML to Google Drive using `mimeType: application/vnd.google-apps.document`, which triggers Google's server-side conversion to a native Google Doc
- Optionally shares the resulting Doc with a specified email address as a writer (no notification email sent)
- Prints the Doc title and URL to stdout

## Prerequisites

- **Python 3.9+**
- **google-auth and google-api-python-client** (installed by install.sh)
- **python-markdown** (installed by install.sh)
- **gws CLI already authorized**, or a manually created `credentials.json` at `~/.config/gws/credentials.json`

### credentials.json format

The gws CLI writes this automatically after `gws auth login`. If setting up manually, the file must contain:

```json
{
  "refresh_token": "1//...",
  "client_id": "....apps.googleusercontent.com",
  "client_secret": "GOCSPX-..."
}
```

The script uses the refresh token to get a short-lived access token at runtime. No interactive auth is needed after the initial login.

## Installation

```bash
DEPLOY_BASE=$HOME AGENT_NAME=max bash install.sh
```

## Usage

```bash
# Upload draft.md as a Google Doc (title = filename without extension)
python3 ~/.max/scripts/gdoc.py draft.md

# Specify a custom title
python3 ~/.max/scripts/gdoc.py draft.md --title "March Newsletter Draft"

# Share with an editor
python3 ~/.max/scripts/gdoc.py draft.md --share editor@example.com

# Both
python3 ~/.max/scripts/gdoc.py draft.md --title "Q2 Report" --share boss@example.com
```

Output:

```
Created: March Newsletter Draft
URL: https://docs.google.com/document/d/1aBcDeF.../edit
```

## Conversion pipeline

```
Markdown file
    │
    ▼
python-markdown (with tables, fenced_code, footnotes extensions)
    │  → HTML string
    ▼
Drive API files.create()
    mimetype: text/html → mimeType: application/vnd.google-apps.document
    │  → Google Doc (server-side conversion)
    ▼
(optional) permissions.create() → share with writer access
    │
    ▼
Print title + URL
```

The conversion to a native Google Doc happens on Google's side — the script uploads HTML and Drive converts it. This preserves headings, bold, italic, lists, tables, and code blocks. Complex CSS or custom formatting will not survive, but standard Markdown structure converts cleanly.

## Integration with the assistant

Tell the agent to publish a draft:

> "Publish draft.md to Google Docs and share it with josh.centers@gmail.com"

The agent calls:

```bash
python3 ~/.max/scripts/gdoc.py ~/workspace/drafts/draft.md --share josh.centers@gmail.com
```

And reports back the URL.

## What gets installed

- `~/.max/scripts/gdoc.py` — the conversion script
- `GWS_CREDS` written to `~/.env`
- Python packages: google-auth, google-api-python-client, markdown (system pip)
