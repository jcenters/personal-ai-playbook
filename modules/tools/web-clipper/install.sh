#!/usr/bin/env bash
# web-clipper/install.sh
# Installs clip.py and its dependencies into ~/scrapling_venv.
#
# Env vars:
#   DEPLOY_BASE    — base deployment directory (default: $HOME)
#   AGENT_NAME     — assistant name (default: max)
#   VENV_DIR       — venv path (default: ~/scrapling_venv)
#   VAULT          — Obsidian vault root (default: ~/workspace)
#   CLIPPINGS_BASE — clippings subdirectory inside vault (default: clippings/max)
#
# Usage:
#   DEPLOY_BASE=$HOME AGENT_NAME=max VAULT=~/workspace bash install.sh

set -euo pipefail

DEPLOY_BASE="${DEPLOY_BASE:-$HOME}"
AGENT_NAME="${AGENT_NAME:-max}"
VENV_DIR="${VENV_DIR:-$HOME/scrapling_venv}"
VAULT="${VAULT:-$HOME/workspace}"
CLIPPINGS_BASE="${CLIPPINGS_BASE:-clippings/max}"

SCRIPTS_DIR="$DEPLOY_BASE/.$AGENT_NAME/scripts"
SCRIPT_PATH="$SCRIPTS_DIR/clip.py"

echo "==> Installing web-clipper to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

# Check for Python 3
PYTHON_BIN=$(command -v python3 || true)
if [[ -z "$PYTHON_BIN" ]]; then
    echo "  ERROR: python3 not found."
    exit 1
fi

# Create venv if missing
if [[ ! -d "$VENV_DIR" ]]; then
    echo "  Creating venv at $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "  Installing dependencies into $VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet scrapling trafilatura readability-lxml markdownify

# Write clip.py
cat > "$SCRIPT_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""
clip.py — Fetch a URL, extract clean markdown, save to Obsidian vault.

Usage:
    clip.py <url> [topic]

Output (stdout, JSON):
    {"file": "clippings/max/tech/2026-03-29-page-title.md", "title": "Page Title", "topic": "tech"}

Topics: tech, research, firearms, education, or any custom label.
Default topic: general
"""
import sys
import os
import re
import json
import hashlib
from datetime import datetime, timezone
from urllib.parse import urlparse

VAULT = os.environ.get("VAULT", os.path.expanduser("~/workspace"))
CLIPPINGS_BASE = os.environ.get("CLIPPINGS_BASE", "clippings/max")

def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    return text[:60].strip("-")

def fetch_page(url: str):
    try:
        from scrapling import Fetcher
        fetcher = Fetcher(auto_match=False)
        page = fetcher.get(url, stealthy_headers=True)
        return page.content, page.status
    except Exception as e:
        raise RuntimeError(f"Scrapling fetch failed: {e}")

def extract_with_readability(html: bytes, url: str):
    try:
        from readability import Document
        doc = Document(html)
        title = doc.title()
        content_html = doc.summary()
        from markdownify import markdownify as md
        content_md = md(content_html, heading_style="ATX")
        content_md = re.sub(r"\n{3,}", "\n\n", content_md).strip()
        return title, content_md
    except Exception:
        return None, None

def extract_with_trafilatura(html: bytes, url: str):
    try:
        import trafilatura
        result = trafilatura.extract(html, url=url, include_tables=True, include_links=False)
        title = trafilatura.extract(html, url=url, output_format="xml", include_tables=False)
        # Best-effort title extraction from content
        title_line = ""
        if result:
            first_line = result.strip().split("\n")[0]
            title_line = first_line.lstrip("#").strip()
        return title_line or urlparse(url).netloc, result or ""
    except Exception as e:
        return urlparse(url).netloc, f"Extraction failed: {e}"

def main():
    if len(sys.argv) < 2:
        print("Usage: clip.py <url> [topic]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    topic = sys.argv[2] if len(sys.argv) > 2 else "general"

    html, status = fetch_page(url)
    if status and status >= 400:
        print(json.dumps({"error": f"HTTP {status}"}))
        sys.exit(1)

    title, content = extract_with_readability(html, url)
    if not content or len(content.strip()) < 100:
        title, content = extract_with_trafilatura(html, url)

    if not title:
        title = urlparse(url).netloc

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    slug = slugify(title)
    filename = f"{today}-{slug}.md"

    clippings_dir = os.path.join(VAULT, CLIPPINGS_BASE, topic)
    os.makedirs(clippings_dir, exist_ok=True)
    filepath = os.path.join(clippings_dir, filename)

    frontmatter = f"""---
title: "{title.replace('"', "'")}"
source: "{url}"
clipped: "{today}"
topic: "{topic}"
---

"""

    with open(filepath, "w") as f:
        f.write(frontmatter + content)

    rel_path = os.path.join(CLIPPINGS_BASE, topic, filename)
    print(json.dumps({"file": rel_path, "title": title, "topic": topic}))

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$SCRIPT_PATH"

# Write env vars
ENV_FILE="$DEPLOY_BASE/.env"
touch "$ENV_FILE"
if ! grep -q "^export VAULT=" "$ENV_FILE" 2>/dev/null; then
    echo "export VAULT=\"$VAULT\"" >> "$ENV_FILE"
    echo "  Added VAULT to $ENV_FILE"
fi
if ! grep -q "^export CLIPPINGS_BASE=" "$ENV_FILE" 2>/dev/null; then
    echo "export CLIPPINGS_BASE=\"$CLIPPINGS_BASE\"" >> "$ENV_FILE"
    echo "  Added CLIPPINGS_BASE to $ENV_FILE"
fi

echo ""
echo "==> web-clipper installed."
echo ""
echo "    Script:    $SCRIPT_PATH"
echo "    Venv:      $VENV_DIR"
echo "    Vault:     $VAULT"
echo "    Clippings: $VAULT/$CLIPPINGS_BASE/{topic}/"
echo ""
echo "    Usage:"
echo "      $VENV_DIR/bin/python3 $SCRIPT_PATH https://example.com tech"
echo "      $VENV_DIR/bin/python3 $SCRIPT_PATH https://example.com research"
echo ""
echo "    Output: JSON with file, title, topic."
echo "    Note: StealthyFetcher (Playwright/JS mode) requires X11."
echo "    httpx mode is the default and works on headless servers."
echo ""
