# Substance Journal MCP server

Lets Claude, Bionic or another voice assistant log doses, drinks and notes in the Substance Journal app's database, and read
what is active, recent entries and reports back.

## Turn on the voice assistant link (encrypted journals)

The app encrypts its journal, and it never hands its key to anything. Instead, on a computer (Windows or Linux) you let the
assistant in yourself, while the app is open:

1. Open Substance Journal, go to **Settings > Summary for an AI > Voice assistant**.
2. Switch on **Let my voice assistant add entries while this app is open**. If you set an app lock, it asks for your PIN
   (or your device unlock) first.
3. A **Voice assistant linked** strip shows at the top of the app while it is on, and every entry the assistant adds pops up
   as *"Added by your voice assistant: ..."* with an **Undo** button.

Optional: tick **Turn on again when the app starts** (off by default). Even then it waits until the app lock is passed.

How it works: while the link is on, the app answers on `127.0.0.1` only, on a free port, and writes
`voice-assistant\link.json` beside the journal with that port, the app's process id and a **token**: a random 32-byte key made
new each time you switch the link on. It is a key for this link only, **not the database key**. The server reads the file,
checks the app answers within a second, and sends each confirmed entry to the app, which writes it through its own database
code, so encryption, sync to your phone and every screen (Active now, the digest) behave exactly as for an entry you typed.
Turning the link off (or closing the app) deletes the file and forgets the token.

What it can do through the link: add doses, drinks and notes, and undo its own entries from the last 10 minutes that you have
not changed. It **cannot** read your whole journal (only the few latest entries, what is active now, your people and preset
names), edit or delete your entries, or see anything when the app is closed or the link is off. `report` is not available
through the link; use Insights in the app.

The app enforces its own limits on the link, whatever the server asks: inserts only, nothing in the future, nothing older than
24 hours, at most 12 assistant entries an hour, each request id saved once (a retry never logs twice), JSON bodies under 64 KB
and a short read timeout, requests from this computer only and with the token.

**While the link is on, `link.json` can be read by any program running as your Windows user** (on Linux the file and its folder
are set to your user only). Such a program could add entries for as long as the link is on, within the limits above. Turn the
link off when you are not using it.

If the journal is encrypted and no link answers (app closed, link off, or a stale file from a run that crashed), every tool says:
*"Open Substance Journal and turn on Settings > Voice assistant."*

## How to ask

The assistant explains this the first time you use it (`how_to_ask`):

- **A dose:** "Log 100 micrograms of LSD, under the tongue." Say the compound, the amount with its unit, and how it was taken. Names like "molly", units like "mcg" and routes like "under the tongue" or "snorted" are understood.
- **A drink:** "Log a beer." or "Log two beers." (a drink preset, by name, and how many)
- **A saved preset:** "Log my usual tab." (any dose preset you saved in the app)
- **A past time:** add "20 minutes ago" or "an hour ago". Without it the time is now.
- **Someone else:** add "for Alex". Without it, it is the default person.
- **A note:** "Add a note: feeling anxious, drank some water." It goes on the timeline of your current session (the last 12 hours).
- **Undo:** "Undo that." Removes only what the assistant just added, never entries you made in the app.
- **Check:** "What's active right now?", "What did I log today?" or "Report for this week."

Logging is immediate: the assistant saves what you asked for and tells you exactly what it saved, and you can say "undo that" (within 10 minutes) or press Undo in the app. The one exception is a
entry that carries a warning (a dose above the reference's strong range, or a note that sounds like an emergency): it is read back, **nothing is saved**, and it is saved only after you say yes.

## Tools

| Tool | What it does |
|---|---|
| `log_dose`, `log_drink`, `log_preset`, `log_note` | Match what you said and **save it at once**, returning what was saved for the assistant to say aloud. An entry with a warning is held (`held_for_yes`, nothing saved) and goes through `confirm_log`. |
| `confirm_log(proposal_id, user_reply)` | Saves a held or prepared entry. Needs that proposal, your clear yes in your own words, and a short pause since the read-back. Single use; a proposal expires after 5 minutes. |
| `undo_last(user_reply)` | Removes the assistant's own most recent entry (or drinks), only within 10 minutes and only if you have not changed it in the app. |
| `current_status` | What is active right now: each compound still within its usual duration with an estimated phase (coming up, around the peak, coming down, after-effects), and alcohol in standard drinks. Read-only. |
| `recent` | The last few entries as short sentences, marking the ones the assistant added. Read-only. |
| `report(period)` | today, yesterday, week, month, year, or custom dates. Starts with one sentence to read aloud, then the details. Read-only. |
| `how_to_ask`, `list_people`, `list_presets` | Read-only. `how_to_ask` also says which journal file is in use. |

Everything except the `log_*` tools, `confirm_log` and `undo_last` is marked read-only, so an assistant can run it without asking you each time.
The caps, the app's own limits and (for held entries) the yes are checked by the server and the app, so it can be registered with `"auto_approve": true`.

Phases and times are estimates from the reference durations, not measurements. The assistant never says anything is safe or
suggests an amount. A note that mentions severe symptoms (trouble breathing, chest pain, a seizure, cannot be woken) comes back
with a line telling you to get urgent medical help now.

## Safety

The prepare/confirm flow, the clear yes, the caps, proposal expiry, the assistant's log and the undo window below apply the same
way whether the server writes through the app's link or to an unencrypted file. Through the link the app also checks its own
caps independently, and the SQLite-only points (the authorizer, read-only connections, backups) do not apply because the app owns
the file.

- There is no tool that edits or deletes anything else, and no SQL or file tool.
- The write connection has a SQLite authorizer: only INSERT into `ingestions`, `experiences` and `timed_notes`; inside undo only,
  UPDATE of the `deleted` and `hlc` columns of those tables (the app's own soft delete). `DROP`, `ALTER`, `DELETE`, other
  UPDATEs, settings, people and presets are refused. Reads use a read-only connection.
- Caps: entries from up to 24 hours ago, never in the future; at most 12 assistant entries an hour; at most 6 drinks per log;
  undo within 10 minutes; notes up to 500 characters; at most 10 unconfirmed proposals.
- You can change the first four in `voice-assistant\assistant_limits.json` next to the journal (`max_backdate_hours`,
  `max_entries_per_hour`, `max_drinks_per_log`, `undo_window_minutes`). Values are kept within 1-72 hours, 1-30 an hour,
  1-10 drinks and 1-30 minutes whatever the file says. No tool writes this file.
- Entries the assistant adds are stamped like another device (`...-mcp`), so they sync to your phone, and doses carry
  `"source": "mcp"` in their details.
- The assistant's own record (what it added, when, for undo and the hourly cap) is a separate small file,
  `voice-assistant\assistant_log.sqlite`. Nothing is added to the app's database, so the app's upgrades and sync never see it.
- Backups in `voice-assistant\backups` (unencrypted file only, not while the link is in use): a copy once a day and one before
  writing (at most one per 10 minutes), the newest 30 of each.

## Which database

It uses the file the installed app writes to: `%APPDATA%\com.substancejournal\Substance Journal\substance_journal.sqlite` on
Windows (`~/.local/share/com.substancejournal.substance_journal_app/` on Linux). It never falls back to another copy, such as an
older install's `substance_journal_app` folder; if the file is missing it says which file it expected. Set `SUBSTANCE_JOURNAL_DB`
to use another file, and `SUBSTANCE_JOURNAL_ASSISTANT_DIR` to keep the log, limits and backups elsewhere.

The app's link is preferred whenever it answers. Without it, the server opens the file directly, which works only for an
unencrypted journal.

**Encrypted journals:** the app encrypts its journal at rest with a key held by the system. This server never opens an encrypted
file (it reads only the first 16 bytes to tell); it works through the app's voice assistant link instead (see above). Set
`SUBSTANCE_JOURNAL_LINK` to read the link file from somewhere else. The read-only `substance-journal-reader` server works either
way, because it reads the app's plain-text summary folder.

## Install

`pip install mcp`, then add to your assistant's MCP config:

```json
{"mcpServers": {"substance-journal": {"command": "python", "args": ["<path>/server.py"]}}}
```

Keep `sj_guard.py` next to `server.py`. It reads the compound list from `app/assets/data`; set `SUBSTANCE_JOURNAL_DATA` to point elsewhere.

It needs nothing beyond `mcp`: the link is spoken to with the standard library (`urllib`, to 127.0.0.1 only, no proxy, short timeouts).

Tests: `python -m pytest tests/test_mcp_server.py tests/test_mcp_link.py` (they build throwaway databases with the app's table
layout, and a fake link server on 127.0.0.1; they never open your journal or start the app).
