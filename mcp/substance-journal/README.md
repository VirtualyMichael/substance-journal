# Substance Journal MCP server

Lets Claude, Bionic or a voice assistant log doses and read reports from the Substance Journal app's database.

- `log_drink` / `log_dose`: two steps. The first call returns a read-back; only a second call with `confirmed=true` writes.
- `undo_last`: removes only entries this server created.
- `report`: today, week, month, year or a custom range, in standard drinks and per-substance totals.
- `list_people`, `list_presets`.

Install: `pip install mcp`, then add to your assistant's MCP config:

```json
{"mcpServers": {"substance-journal": {"command": "python", "args": ["<path>/server.py"]}}}
```

It finds the database in `%APPDATA%\com.substancejournal\...` automatically; set `SUBSTANCE_JOURNAL_DB` to override.
Entries it adds are stamped like another device, so they sync to your phone on the next sync. It never changes anything but its own rows.
