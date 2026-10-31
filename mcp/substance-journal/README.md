# Substance Journal MCP server

Lets Claude, Bionic or another voice assistant log doses and notes in the Substance Journal app's database, and read reports back.

## How to ask

The assistant explains this the first time you use it (`how_to_ask`):

- **A dose:** "Log 100 micrograms of LSD, under the tongue." Say the compound, the amount with its unit, and how it was taken. Names like "molly", units like "mcg" and routes like "under the tongue" or "snorted" are understood.
- **A drink:** "Log a beer." or "Log two shots of vodka." (a drink preset, by name, and how many)
- **A saved preset:** "Log my usual tab." (any dose preset you saved in the app)
- **A past time:** add "20 minutes ago" or "an hour ago". Without it the time is now.
- **Someone else:** add "for Alex". Without it, it is the default person.
- **A note:** "Add a note: feeling anxious, drank some water." It goes on the timeline of your current session (the last 12 hours).
- **Undo:** "Undo that." Removes only what the assistant added, never entries you made in the app. "Undo the last note" removes a note.
- **Check:** "What did I log today?" or "Report for this week."

Every write is two steps: the assistant reads back what it is about to save and waits for your yes. A dose above the reference's strong range is flagged in the read-back so a wrong number or unit gets caught.

## Tools

`how_to_ask`, `log_dose`, `log_drink`, `log_preset`, `add_note`, `undo_last`, `recent`, `report`, `list_people`, `list_presets`.

It never changes anything but its own rows. Entries it adds are stamped like another device, so they sync to your phone on the next sync.

## Install

`pip install mcp`, then add to your assistant's MCP config:

```json
{"mcpServers": {"substance-journal": {"command": "python", "args": ["<path>/server.py"]}}}
```

It finds the database in `%APPDATA%\com.substancejournal\...` automatically; set `SUBSTANCE_JOURNAL_DB` to override. It reads the compound list from `app/assets/data`; set `SUBSTANCE_JOURNAL_DATA` to point elsewhere.

Tests: `python -m pytest tests/test_mcp_server.py` (they build a throwaway database with the app's table layout).
