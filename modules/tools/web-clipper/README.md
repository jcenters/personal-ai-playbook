# web-clipper

Saves any URL as clean Markdown to your Obsidian vault. Bypasses bot detection using [Scrapling](https://github.com/D4Vinci/Scrapling)'s stealthy httpx mode, extracts article content with readability-lxml, and writes a file with YAML frontmatter to `~/workspace/clippings/max/{topic}/`.

## What it does

- Fetches the URL with stealthy headers (mimics a real browser at the HTTP level)
- Extracts the main article body using **readability-lxml** (primary)
- Falls back to **trafilatura** if readability returns less than 100 characters
- Converts the extracted HTML to Markdown via **markdownify**
- Writes a `.md` file with YAML frontmatter: `title`, `source`, `clipped`, `topic`
- Returns a JSON object on stdout for easy agent integration

## Prerequisites

- Python 3.9+
- The `scrapling_venv` venv (created by install.sh)
- An Obsidian vault at `~/workspace` (or set `VAULT` to your vault path)

## Installation

```bash
DEPLOY_BASE=$HOME AGENT_NAME=max VAULT=~/workspace bash install.sh
```

Optional overrides:

```bash
DEPLOY_BASE=$HOME \
AGENT_NAME=max \
VENV_DIR=$HOME/scrapling_venv \
VAULT=$HOME/workspace \
CLIPPINGS_BASE=clippings/max \
bash install.sh
```

## Usage

```bash
# Clip to default topic (general)
~/scrapling_venv/bin/python3 ~/.max/scripts/clip.py https://example.com/article

# Clip with a topic label
~/scrapling_venv/bin/python3 ~/.max/scripts/clip.py https://example.com/article tech
~/scrapling_venv/bin/python3 ~/.max/scripts/clip.py https://example.com/article research
~/scrapling_venv/bin/python3 ~/.max/scripts/clip.py https://example.com/article firearms
~/scrapling_venv/bin/python3 ~/.max/scripts/clip.py https://example.com/article education
```

## Output format

JSON on stdout:

```json
{"file": "clippings/max/tech/2026-03-29-page-title.md", "title": "Page Title", "topic": "tech"}
```

The `file` path is relative to `VAULT`. Use it to reference the clipped file in memory or Telegram notifications.

## Clippings directory structure

```
~/workspace/
  clippings/
    max/
      tech/
        2026-03-29-page-title.md
      research/
        2026-03-28-another-article.md
      firearms/
        ...
```

Each file looks like:

```markdown
---
title: "Page Title"
source: "https://example.com/article"
clipped: "2026-03-29"
topic: "tech"
---

Article content here...
```

## Two-extraction-method approach

1. **readability-lxml (primary)** — Mozilla's Readability algorithm ported to Python. Strips nav, sidebars, ads, and boilerplate. Best for article pages with a clear main content area.

2. **trafilatura (fallback)** — Used when readability returns very little content. Trafilatura uses a different heuristic (main content scoring + XML pipeline) and handles some edge cases readability misses, including some news aggregators and documentation sites.

## Integration with the assistant

Tell the agent to clip a page:

> "Clip this page: https://example.com/article — topic: research"

The agent calls `clip.py` and gets JSON back. It can then:
- Notify you via Telegram with the filename
- Log the clip to memory
- Reference the clipped content in a follow-up response

## Server note

`StealthyFetcher` (Scrapling's Playwright/JS mode) requires GTK3/X11 system libraries and cannot run on a headless VPS without root. The httpx mode used here works everywhere. For pages that require JavaScript execution, see the Mac-via-Tailscale approach in your global CLAUDE.md.

## What gets installed

- `~/.max/scripts/clip.py` — the clipping script
- `~/scrapling_venv/` — Python venv with scrapling, trafilatura, readability-lxml, markdownify
- `VAULT` and `CLIPPINGS_BASE` written to `~/.env`
