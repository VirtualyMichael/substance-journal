# Substance Journal reader (read-only AI context)

Lets a local or cloud AI read your journal without blowing through a small context window. It never
touches the database and never writes anything: it reads small text files the app prepares.

## How it works

The app does the maths (potency, estimated curve, tolerance, overlaps) and writes a folder:

```
Substance Journal digest/
  me/
    README.md        how to read it
    profile.md       one page: what is used, how often, last use, tolerance and direction, last 7 days
    months/2026-10.md   one page per month, day by day, totals, days without use
    experiences/2026-10-28_2043_ab12cd34.md   one fact sheet per experience
    index.json       every experience with its path and size
```

An experience sheet holds every dose (time, route, amount, light/common/strong for that route, THC
consumed versus absorbed, product, strain type, terpenes, notes), the estimated curve (noticeable,
peak, fades), overlaps between compounds, tolerance going in, other use in the 7 days before, and
notes and ratings with their times. Sheets are about 400 to 1,500 tokens. With a 60k window you can
open the profile, a month and several experiences in one conversation.

## Turn it on

1. In the app (computer): **Settings > Summary for an AI > Keep the folder up to date**.
   The folder is plain text, including names and notes as written; the default is `Documents/Substance Journal digest`.
   The app rewrites it a little after every change (it syncs from your phone like everything else).
2. Add the server to your AI tool (LM Studio, Bionic, Claude Desktop or any MCP client):

```json
{"mcpServers": {"substance-journal-reader": {"command": "python", "args": ["<path>/mcp/substance-journal-reader/server.py"]}}}
```

   `pip install mcp` first. Set `SUBSTANCE_JOURNAL_DIGEST` if the folder is somewhere else.

## Tools

`guide`, `profile`, `month`, `list_experiences`, `experience`, `find`, `doses`, `tolerance`,
`compare_months`, `list_people`. Each takes `max_tokens` (or a `limit`) and says when it cut something off.

## No MCP? Copy a summary

**Settings > Summary for an AI > Copy summary** puts text on the clipboard: Small (about 0.5k tokens: the
profile), Medium (about 1.5k: plus this month) or Large (about 4-8k: plus the five latest experiences).
"Leave out names, notes and places" is on by default; use it before pasting into a cloud AI. The phone can do
this too. You can also point any tool that reads files at the digest folder, or load `SKILL.md` into a chat.

## What the AI is told

Numbers are estimates from published ranges; it never says anything is safe, never recommends an
amount, gives only general harm-reduction tips, points to urgent help for severe symptoms, and does not
diagnose. See `SKILL.md`.

Tests: `python -m pytest tests/test_mcp_reader.py`.
