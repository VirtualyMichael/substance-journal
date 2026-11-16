"""The voice/AI server against throwaway databases with the app's real table layout (see the schema below).

Nothing here opens the real journal: every test points SUBSTANCE_JOURNAL_DB (or APPDATA) at a temporary folder.
"""
import asyncio
import importlib.util
import json
import sqlite3
import time
from datetime import datetime, timedelta
from pathlib import Path

import pytest

pytest.importorskip("mcp")

SERVER = Path(__file__).resolve().parents[1] / "mcp" / "substance-journal" / "server.py"

SCHEMA = [
    '''CREATE TABLE "people" ("id" TEXT NOT NULL, "hlc" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0, "name" TEXT NOT NULL, "color_value" INTEGER NOT NULL DEFAULT 4284960932, "is_default" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"))''',
    '''CREATE TABLE "experiences" ("id" TEXT NOT NULL, "hlc" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0, "person_id" TEXT NOT NULL, "title" TEXT NOT NULL DEFAULT '', "notes" TEXT NOT NULL DEFAULT '', "sort_date" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "is_favorite" INTEGER NOT NULL DEFAULT 0, "location_name" TEXT NULL, "latitude" REAL NULL, "longitude" REAL NULL, PRIMARY KEY ("id"))''',
    '''CREATE TABLE "ingestions" ("id" TEXT NOT NULL, "hlc" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0, "experience_id" TEXT NOT NULL, "person_id" TEXT NOT NULL, "substance_key" TEXT NOT NULL, "route" TEXT NOT NULL, "time" INTEGER NOT NULL, "end_time" INTEGER NULL, "dose" REAL NULL, "unit" TEXT NULL, "dose_is_estimate" INTEGER NOT NULL DEFAULT 0, "dose_std_dev" REAL NULL, "stomach_fullness" TEXT NULL, "custom_unit_id" TEXT NULL, "product_id" TEXT NULL, "absorbed_mg" REAL NULL, "method" TEXT NULL, "notes" TEXT NOT NULL DEFAULT '', "details_json" TEXT NOT NULL DEFAULT '{}', PRIMARY KEY ("id"))''',
    '''CREATE TABLE "timed_notes" ("id" TEXT NOT NULL, "hlc" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0, "experience_id" TEXT NOT NULL, "time" INTEGER NOT NULL, "note" TEXT NOT NULL, "color_value" INTEGER NOT NULL DEFAULT 4284960932, "show_on_timeline" INTEGER NOT NULL DEFAULT 1, PRIMARY KEY ("id"))''',
    '''CREATE TABLE "presets" ("id" TEXT NOT NULL, "hlc" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0, "substance_key" TEXT NOT NULL, "route" TEXT NOT NULL, "name" TEXT NOT NULL, "amount" REAL NOT NULL, "unit" TEXT NOT NULL, "details_json" TEXT NOT NULL DEFAULT '{}', PRIMARY KEY ("id"))''',
    '''CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, "hlc" TEXT NOT NULL, "shared" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("key"))''',
]


def make_db(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    for stmt in SCHEMA:
        con.execute(stmt)
    con.execute("insert into people(id,hlc,deleted,name,is_default) values('p1','h',0,'Me',1)")
    con.execute("insert into people(id,hlc,deleted,name,is_default) values('p2','h',0,'Alex',0)")
    for pid, key, route, name, amount, unit, details in [
        ("d1", "alcohol", "oral", "Beer - 12 oz 5%", 12, "oz", '{"abv": 5}'),
        ("d2", "alcohol", "oral", "Strong beer - 16 oz 8%", 16, "oz", '{"abv": 8}'),
        ("d3", "lsd", "sublingual", "Usual tab", 80, "µg", "{}"),
    ]:
        con.execute("insert into presets(id,hlc,deleted,substance_key,route,name,amount,unit,details_json) values(?,?,0,?,?,?,?,?,?)",
                    (pid, "h", key, route, name, amount, unit, details))
    con.commit()
    con.close()
    return path


class Clock:
    """A monotonic clock the test moves by hand, so 'the pause since the read-back' is exact."""

    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


def load_server(monkeypatch, db: Path):
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DB", str(db))
    monkeypatch.delenv("SUBSTANCE_JOURNAL_ASSISTANT_DIR", raising=False)
    spec = importlib.util.spec_from_file_location("sj_server", SERVER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture()
def srv(tmp_path, monkeypatch):
    db = make_db(tmp_path / "journal" / "j.sqlite")
    mod = load_server(monkeypatch, db)
    mod.mono = Clock()
    mod._guard = mod.Guard(monotonic=mod.mono)  # finds the file through SUBSTANCE_JOURNAL_DB, like the real server
    mod.db = db
    return mod


def rows(srv, sql, *args):
    con = sqlite3.connect(srv.db)
    con.row_factory = sqlite3.Row
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


def prepared(text: str) -> dict:
    assert not text.startswith("Not done"), text
    return json.loads(text)


def confirm(srv, text: str, reply: str = "yes", wait: float = 3.0) -> str:
    p = prepared(text)
    srv.mono.t += wait
    return srv.confirm_log(p["proposal_id"], reply)


# ---- parsing (kept from the old flow) --------------------------------------------------------------------------
def test_names_units_and_routes_are_understood(srv):
    assert srv.resolve_substance("molly")["key"] == "mdma"
    assert srv.resolve_substance("LSD")["key"] == "lsd"
    lsd = srv.resolve_substance("lsd")
    roa = srv.resolve_route(lsd, "under the tongue")
    assert roa["route"] == "sublingual"
    value, unit = srv.convert_dose(0.1, "mg", roa)
    assert unit == "µg" and round(value, 6) == 100
    with pytest.raises(ValueError):
        srv.resolve_substance("flarbnarb")
    with pytest.raises(ValueError):
        srv.resolve_route(srv.resolve_substance("ketamine"), "")  # more than one route: it must ask


def test_drink_presets_match_what_people_say(srv):
    drinks = rows(srv, "select * from presets where substance_key='alcohol'")
    assert srv.find_preset(drinks, "beer")["name"] == "Beer - 12 oz 5%"
    assert srv.find_preset(drinks, "a beer")["name"] == "Beer - 12 oz 5%"
    assert srv.find_preset(drinks, "two beers")["name"] == "Beer - 12 oz 5%"
    assert srv.find_preset(drinks, "strong beer")["name"] == "Strong beer - 16 oz 8%"
    with pytest.raises(ValueError, match="No preset"):
        srv.find_preset(drinks, "wine")


# ---- prepare writes nothing; confirm needs a matching proposal, a clear yes and a pause ------------------------
def test_prepare_writes_nothing_and_confirm_saves_in_the_routes_own_unit(srv):
    p = prepared(srv.prepare_dose("lsd", 100, unit="micrograms", route="under the tongue", notes="blue tab"))
    assert p["read_back_to_user"].startswith("Log 100 micrograms of LSD, under the tongue, for Me, now")
    assert p["warnings_to_say_aloud"] == []
    assert rows(srv, "select * from ingestions") == [] and rows(srv, "select * from experiences") == []
    assert not (srv.db.parent / "voice-assistant" / "assistant_log.sqlite").exists()

    srv.mono.t += 3
    done = json.loads(srv.confirm_log(p["proposal_id"], "Yes, log it"))
    assert done["entries"] == 1 and "first_time_read_this_out" in done
    r = rows(srv, "select * from ingestions")[0]
    assert (r["substance_key"], r["route"], r["dose"], r["unit"], r["notes"]) == ("lsd", "sublingual", 100, "µg", "blue tab")
    assert r["person_id"] == "p1" and r["hlc"].endswith("-mcp")
    details = json.loads(r["details_json"])
    assert details["source"] == "mcp" and details["experienceCreated"] is True
    assert len(rows(srv, "select * from experiences")) == 1

    again = json.loads(confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual")))
    assert "first_time_read_this_out" not in again  # told once only
    assert len(rows(srv, "select * from experiences")) == 1  # joined the session


def test_confirm_is_single_use_and_needs_a_real_proposal(srv):
    p = prepared(srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    srv.mono.t += 3
    assert json.loads(srv.confirm_log(p["proposal_id"], "yes"))["entries"] == 1
    assert srv.confirm_log(p["proposal_id"], "yes").startswith("Not done: That entry was not prepared")
    assert srv.confirm_log("made-up-id", "yes").startswith("Not done: That entry was not prepared")
    assert len(rows(srv, "select * from ingestions")) == 1


def test_confirm_needs_the_pause_since_the_read_back(srv):
    p = prepared(srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    srv.mono.t += 0.5
    assert "wait for their answer" in srv.confirm_log(p["proposal_id"], "yes")
    assert rows(srv, "select * from ingestions") == []
    srv.mono.t += 3  # the proposal survives a too-early confirm
    assert json.loads(srv.confirm_log(p["proposal_id"], "yes"))["entries"] == 1


def test_proposals_expire(srv):
    p = prepared(srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    srv.mono.t += srv.sj_guard.PROPOSAL_TTL_SECONDS + 1
    assert "expired" in srv.confirm_log(p["proposal_id"], "yes")
    assert rows(srv, "select * from ingestions") == []


@pytest.mark.parametrize("reply", ["no", "wait", "yes but make it 50", "maybe", "hmm", "I think so", "not yet", "",
                                   "yes, actually no", "hold on", "change it to two", "cancel", "what?", "nope"])
def test_anything_but_a_clear_yes_saves_nothing(srv, reply):
    msg = confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"), reply)
    assert msg.startswith("Not done"), (reply, msg)
    assert rows(srv, "select * from ingestions") == []


@pytest.mark.parametrize("reply", ["yes", "Yes.", "yeah", "yep, do it", "ok", "okay go ahead", "sure", "confirm", "that's right", "Yes please"])
def test_clear_yes_variants(srv, reply):
    assert srv.sj_guard.user_said_yes(reply), reply


def test_a_huge_dose_is_flagged_and_nonsense_is_refused(srv):
    p = prepared(srv.prepare_dose("lsd", 5000, unit="ug", route="sublingual"))
    assert any("Check the number and unit" in w for w in p["warnings_to_say_aloud"])
    assert srv.prepare_dose("lsd", 0, route="sublingual").startswith("Not done: The dose must be")
    assert "log_drink" in srv.prepare_dose("alcohol", 1, route="oral")
    assert "not listed" in srv.prepare_dose("lsd", 1, route="snorted")
    assert "No person called Nobody" in srv.prepare_dose("lsd", 100, route="sublingual", person="Nobody")


def test_drinks_presets_and_other_people(srv):
    p = prepared(srv.prepare_drink("beer"))
    assert "about 1.0 standard drinks" in p["read_back_to_user"]
    out = json.loads(confirm(srv, srv.prepare_drink("beers", count=2, person="Alex", minutes_ago=30)))
    assert out["entries"] == 2
    two = rows(srv, "select * from ingestions where person_id='p2'")
    assert len(two) == 2 and all(json.loads(r["details_json"])["drink"] == "Beer - 12 oz 5%" for r in two)
    assert abs(two[0]["time"] - (int(time.time()) - 1800)) < 5
    assert srv.prepare_drink("beer", count=0).startswith("Not done: How many")
    assert srv.prepare_drink("beer", count=7).startswith("Not done: How many")  # the per-log cap

    p = prepared(srv.prepare_preset("my usual tab"))
    assert p["read_back_to_user"].startswith("Log Usual tab: 80 micrograms of LSD, under the tongue")
    confirm(srv, srv.prepare_preset("usual tab"))
    assert rows(srv, "select dose, unit from ingestions where substance_key='lsd'")[0]["dose"] == 80
    assert srv.prepare_preset("beer").startswith("Not done: No preset")  # drinks go through prepare_drink


def test_notes_go_on_the_current_session(srv):
    assert "no session" in srv.prepare_note("anxious")  # nothing logged yet
    confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    p = prepared(srv.prepare_note("feeling anxious", minutes_ago=5))
    assert p["read_back_to_user"].startswith('Add the note "feeling anxious" for Me, at')
    assert rows(srv, "select * from timed_notes") == []
    confirm(srv, srv.prepare_note("feeling anxious", minutes_ago=5))
    n = rows(srv, "select * from timed_notes")[0]
    exp = rows(srv, "select experience_id from ingestions")[0]["experience_id"]
    assert n["experience_id"] == exp and n["show_on_timeline"] == 1 and n["time"] <= int(time.time()) - 290
    assert n["hlc"].endswith("-mcp")
    assert "feeling anxious" in srv.recent()
    assert srv.prepare_note("   ") == "Not done: What should the note say?"
    assert "too long" in srv.prepare_note("x" * 501)


def test_a_worrying_note_carries_the_urgent_help_line(srv):
    confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    p = prepared(srv.prepare_note("friend has chest pain and can't breathe properly"))
    assert any("urgent medical help" in w for w in p["warnings_to_say_aloud"])
    assert prepared(srv.prepare_note("drank some water"))["warnings_to_say_aloud"] == []


# ---- caps -----------------------------------------------------------------------------------------------------
def test_time_window_caps(srv):
    assert "future" in srv.prepare_dose("lsd", 100, unit="ug", route="sublingual", minutes_ago=-5)
    assert "last 24 hours" in srv.prepare_dose("lsd", 100, unit="ug", route="sublingual", minutes_ago=24 * 60 + 1)
    assert prepared(srv.prepare_dose("lsd", 100, unit="ug", route="sublingual", minutes_ago=24 * 60))


def test_hourly_cap_on_assistant_entries(srv):
    srv._guard._limits = srv.sj_guard.Limits(max_entries_per_hour=3)
    confirm(srv, srv.prepare_drink("beer", count=2))
    p = prepared(srv.prepare_drink("beer"))  # 2 + 1 = 3: allowed
    assert srv.prepare_drink("beer", count=2).startswith("Not done: The assistant can add at most 3")
    srv.mono.t += 3
    json.loads(srv.confirm_log(p["proposal_id"], "yes"))
    assert "at most 3" in srv.prepare_dose("lsd", 100, unit="ug", route="sublingual")
    assert len(rows(srv, "select * from ingestions")) == 3


def test_confirm_rechecks_the_hourly_cap(srv):
    srv._guard._limits = srv.sj_guard.Limits(max_entries_per_hour=2)
    a = prepared(srv.prepare_drink("beer"))
    b = prepared(srv.prepare_drink("beer", count=2))  # each alone fits; both together do not
    srv.mono.t += 3
    srv.confirm_log(a["proposal_id"], "yes")
    assert "at most 2" in srv.confirm_log(b["proposal_id"], "yes")
    assert len(rows(srv, "select * from ingestions")) == 1


def test_limits_file_is_read_and_kept_inside_the_bounds(srv, tmp_path):
    f = tmp_path / "limits.json"
    f.write_text(json.dumps({"max_backdate_hours": 1000, "max_entries_per_hour": 0, "max_drinks_per_log": 3, "undo_window_minutes": "x"}))
    lim = srv.sj_guard.load_limits(f)
    assert lim.max_backdate_hours == 72 and lim.max_entries_per_hour == 1 and lim.max_drinks_per_log == 3 and lim.undo_window_minutes == 10
    assert srv.sj_guard.load_limits(tmp_path / "missing.json") == srv.sj_guard.Limits()
    g = srv._guard
    g.sidecar.mkdir(parents=True, exist_ok=True)
    g.limits_path.write_text(json.dumps({"max_drinks_per_log": 2}))
    assert srv.prepare_drink("beer", count=3).startswith("Not done: How many drinks? Give a whole number from 1 to 2")


# ---- the authorizer -------------------------------------------------------------------------------------------
@pytest.mark.parametrize("sql", [
    "UPDATE ingestions SET dose = 1",
    "UPDATE ingestions SET deleted = 1",
    "DELETE FROM ingestions",
    "DROP TABLE ingestions",
    "ALTER TABLE ingestions ADD COLUMN x TEXT",
    "CREATE TABLE evil (x)",
    "INSERT INTO people(id,hlc,name) VALUES('p9','h','X')",
    "INSERT INTO presets(id,hlc,substance_key,route,name,amount,unit) VALUES('x','h','lsd','oral','x',1,'mg')",
    "INSERT OR REPLACE INTO settings(key,value,hlc) VALUES('k','v','h')",
    "UPDATE people SET name = 'X'",
    "PRAGMA journal_mode = WAL",
    "ATTACH DATABASE ':memory:' AS other",
])
def test_authorizer_refuses_everything_but_the_needed_inserts(srv, sql):
    with pytest.raises(sqlite3.DatabaseError):
        with srv._guard._writer() as c:
            c.execute(sql)
    assert rows(srv, "select count(*) n from people")[0]["n"] == 2


def test_authorizer_allows_only_the_soft_delete_columns_inside_undo(srv):
    g = srv._guard
    g._undoing = True
    try:
        with pytest.raises(sqlite3.DatabaseError):
            with g._writer() as c:
                c.execute("UPDATE ingestions SET dose = 1")
        with pytest.raises(sqlite3.DatabaseError):
            with g._writer() as c:
                c.execute("DELETE FROM ingestions")
        with g._writer() as c:
            c.execute("UPDATE ingestions SET deleted = 1, hlc = 'x' WHERE id = 'none'")
    finally:
        g._undoing = False


def test_reads_use_a_read_only_connection(srv):
    with pytest.raises(sqlite3.OperationalError, match="readonly"):
        srv._guard.reader().execute("insert into people(id,hlc,name) values('p9','h','X')")


# ---- undo -----------------------------------------------------------------------------------------------------
def _add_app_entry(srv, iid="mine"):
    now = int(time.time())
    con = sqlite3.connect(srv.db)
    con.execute("insert into experiences(id,hlc,person_id,sort_date,created_at) values('e1','h','p1',?,?)", (now - 86400 * 3, now))
    con.execute("insert into ingestions(id,hlc,experience_id,person_id,substance_key,route,time,dose,unit) "
                "values(?,'h','e1','p1','mdma','oral',?,80,'mg')", (iid, now - 86400 * 3))
    con.commit()
    con.close()


def test_undo_only_touches_what_the_assistant_added(srv):
    _add_app_entry(srv)
    assert "Nothing to undo" in srv.undo_last("yes")
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    assert srv.undo_last("no").startswith("Not done: Ask the person to confirm the undo")
    out = json.loads(srv.undo_last("yes"))
    assert out["removed"] == 1 and "LSD" in out["what"]
    assert [r["id"] for r in rows(srv, "select id from ingestions where deleted=0")] == ["mine"]
    gone = rows(srv, "select * from ingestions where id!='mine'")[0]
    assert gone["deleted"] == 1 and gone["hlc"].endswith("-mcp")
    # the session the assistant created for it went too, and the app's own session is untouched
    exps = {r["id"]: r["deleted"] for r in rows(srv, "select id, deleted from experiences")}
    assert exps.pop("e1") == 0 and list(exps.values()) == [1]
    assert "Nothing to undo" in srv.undo_last("yes")  # never twice


def test_undo_removes_a_whole_drink_batch_and_notes(srv):
    confirm(srv, srv.prepare_drink("beer", count=3))
    assert json.loads(srv.undo_last("yes"))["removed"] == 3
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    confirm(srv, srv.prepare_note("peaking"))
    out = json.loads(srv.undo_last("yes"))
    assert out["removed"] == 1 and "peaking" in out["what"]
    assert rows(srv, "select deleted from timed_notes")[0]["deleted"] == 1
    assert len(rows(srv, "select * from ingestions where deleted=0")) == 1  # the dose stays until asked again


def test_undo_leaves_an_entry_edited_in_the_app(srv):
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    con = sqlite3.connect(srv.db)
    con.execute("update ingestions set dose=60, hlc='999999999999999-0000-desktop'")
    con.commit()
    con.close()
    out = json.loads(srv.undo_last("yes"))
    assert out["removed"] == 0 and "changed in the app" in out["left_alone"][0]
    assert rows(srv, "select deleted, dose from ingestions")[0]["deleted"] == 0


def test_undo_window(srv):
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    later = datetime.now() + timedelta(minutes=11)
    srv._guard._now = lambda: later
    assert "Nothing to undo" in srv.undo_last("yes")
    assert rows(srv, "select deleted from ingestions")[0]["deleted"] == 0


# ---- backups and the assistant's own log ------------------------------------------------------------------------
def test_backups_before_writes_and_daily(srv):
    backups = srv._guard.backups
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    pre = sorted(backups.glob("prewrite-*.sqlite"))
    assert len(pre) == 1
    copy = sqlite3.connect(pre[0])
    assert copy.execute("select count(*) from people").fetchone()[0] == 2  # a real copy, taken before the insert
    assert copy.execute("select count(*) from ingestions").fetchone()[0] == 0
    copy.close()
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    assert len(list(backups.glob("prewrite-*.sqlite"))) == 1  # at most one per 10 minutes
    assert srv._guard.backup("daily") is not None and srv._guard.backup("daily") is None  # once a day


def test_assistant_log_lives_outside_the_journal(srv):
    confirm(srv, srv.prepare_dose("lsd", 50, unit="ug", route="sublingual"))
    tables = {r[0] for r in rows(srv, "select name from sqlite_master where type='table'")}
    assert tables == {"people", "experiences", "ingestions", "timed_notes", "presets", "settings"}  # nothing added to the app's database
    assert rows(srv, "select * from settings") == []
    log = sqlite3.connect(srv.db.parent / "voice-assistant" / "assistant_log.sqlite")
    kinds = sorted(r[0] for r in log.execute("select table_name from assistant_log"))
    log.close()
    assert kinds == ["experiences", "ingestions"]
    assert "(added by the assistant)" in srv.recent()


# ---- choosing the database --------------------------------------------------------------------------------------
def test_db_selection_uses_the_installed_apps_folder_and_never_an_old_copy(tmp_path, monkeypatch):
    import sys
    sys.path.insert(0, str(SERVER.parent))
    import sj_guard

    base = tmp_path / "Roaming" / "com.substancejournal"
    monkeypatch.setenv("APPDATA", str(tmp_path / "Roaming"))
    monkeypatch.delenv("SUBSTANCE_JOURNAL_DB", raising=False)
    old = make_db(base / "substance_journal_app" / "substance_journal.sqlite")
    with pytest.raises(sj_guard.JournalError) as e:
        sj_guard.resolve_db_path("win32")
    assert "Substance Journal" in str(e.value) and str(old) in str(e.value)  # says which file it expected; names the copy it will not use

    live = make_db(base / "Substance Journal" / "substance_journal.sqlite")
    old.touch()  # the old copy is newer: it must not matter
    path, source = sj_guard.resolve_db_path("win32")
    assert path == live and source == "the installed app's folder"

    monkeypatch.setenv("SUBSTANCE_JOURNAL_DB", str(old))
    assert sj_guard.resolve_db_path("win32") == (old, "SUBSTANCE_JOURNAL_DB")
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DB", str(tmp_path / "nope.sqlite"))
    with pytest.raises(sj_guard.JournalError, match="does not exist"):
        sj_guard.resolve_db_path("win32")


def test_how_to_ask_names_the_file_in_use(srv):
    text = srv.how_to_ask()
    for word in ("micrograms", "note", "Undo", "yes", "right now"):
        assert word in text
    assert str(srv.db.resolve()) in text and "SUBSTANCE_JOURNAL_DB" in text


def test_an_encrypted_journal_is_refused_cleanly(tmp_path, monkeypatch):
    db = tmp_path / "enc.sqlite"
    db.write_bytes(b"\x8a\x13" * 4096)  # what the app's encrypted file looks like from outside: no SQLite header
    mod = load_server(monkeypatch, db)
    assert "encrypted" in mod.how_to_ask()
    assert "encrypted" in mod.recent()
    assert "encrypted" in mod.prepare_dose("lsd", 100, unit="ug", route="sublingual")
    assert db.read_bytes() == b"\x8a\x13" * 4096
    assert not (tmp_path / "voice-assistant" / "backups").exists() or not list((tmp_path / "voice-assistant" / "backups").iterdir())


# ---- status, recent and reports read well aloud ---------------------------------------------------------------------
def test_current_status_gives_an_estimated_phase(srv):
    assert "nothing active" in srv.current_status()
    confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual", minutes_ago=120))
    confirm(srv, srv.prepare_drink("beer", count=2, minutes_ago=30))
    status = srv.current_status()
    assert "estimated" in status
    assert "LSD, under the tongue: last 100 micrograms 2 hours ago, estimated around the peak" in status
    assert "Alcohol: about 1.5 standard drinks estimated still being processed" in status
    assert "safe" not in status.replace("not a measure of whether it is safe to drive", "")
    # an old dose is not active any more
    srv._guard._now = lambda: datetime.now() + timedelta(hours=40)
    assert "LSD" not in srv.current_status()


def test_recent_reads_as_sentences(srv):
    assert srv.recent() == "Me: nothing logged yet."
    confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    confirm(srv, srv.prepare_drink("beer"))
    text = srv.recent()
    assert "Today " in text and "100 micrograms of LSD, under the tongue (added by the assistant)." in text
    assert "Beer - 12 oz 5%, about 1.0 standard drinks (added by the assistant)." in text


def test_report_starts_with_a_spoken_sentence(srv):
    assert srv.report("today") == "Spoken summary: You logged nothing today."
    confirm(srv, srv.prepare_drink("beer", count=2))
    confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    text = srv.report("week")
    first = text.splitlines()[0]
    assert first == "Spoken summary: In the last 7 days, you logged 2.0 standard drinks over 1 day and LSD once (100 micrograms in all)."
    assert "Alcohol: 2.0 standard drinks" in text and "LSD: 1 dose(s), 100 µg total" in text
    assert srv.report("week", person="Alex") == "Spoken summary: Alex logged nothing in the last 7 days."
    assert srv.report("fortnight").startswith("Not done: period must be")


# ---- annotations ------------------------------------------------------------------------------------------------
def test_tool_annotations(srv):
    tools = {t.name: t.annotations for t in asyncio.run(srv.mcp.list_tools())}
    read_only = {"how_to_ask", "current_status", "recent", "report", "list_people", "list_presets"}
    assert set(tools) == read_only | {"confirm_log", "undo_last", "log_dose", "log_drink", "log_preset", "log_note"}
    for name in ("log_dose", "log_drink", "log_preset", "log_note"):
        a = tools[name]
        assert getattr(a, "read_only_hint", getattr(a, "readOnlyHint", None)) is False and getattr(a, "destructive_hint", getattr(a, "destructiveHint", None)) is False

    def ro(a):
        return getattr(a, "read_only_hint", getattr(a, "readOnlyHint", None))

    def destructive(a):
        return getattr(a, "destructive_hint", getattr(a, "destructiveHint", None))

    for name in read_only:
        assert ro(tools[name]) is True, name
    assert ro(tools["confirm_log"]) is False and destructive(tools["confirm_log"]) is False
    assert ro(tools["undo_last"]) is False and destructive(tools["undo_last"]) is True


# ---- log now: saved at once and told, no yes/no step -------------------------------------------------------------
def test_log_dose_saves_straight_away_and_says_what_it_saved(srv):
    out = json.loads(srv.log_dose("lsd", 100, unit="micrograms", route="under the tongue"))
    assert out["told_to_user"].startswith("Saved: 100 micrograms of LSD, under the tongue, for Me, now") and out["entries"] == 1
    assert "undo" in out and "first_time_read_this_out" in out
    r = rows(srv, "select * from ingestions")[0]
    assert (r["substance_key"], r["dose"], r["unit"]) == ("lsd", 100, "µg") and r["hlc"].endswith("-mcp")
    assert "first_time_read_this_out" not in json.loads(srv.log_dose("lsd", 50, unit="ug", route="sublingual"))  # told once only
    assert len(rows(srv, "select * from ingestions")) == 2


def test_log_drink_and_note_save_straight_away_and_can_be_undone(srv):
    out = json.loads(srv.log_drink("beer", count=2))
    assert out["entries"] == 2 and "standard drinks" in out["told_to_user"]
    note = json.loads(srv.log_note("drank some water"))
    assert note["told_to_user"].startswith('Saved: the note "drank some water"') or "drank some water" in note["told_to_user"]
    assert len(rows(srv, "select * from ingestions")) == 2
    assert json.loads(srv.undo_last("yes"))["removed"] >= 1


def test_a_dose_above_the_strong_range_is_held_for_a_yes_and_saves_nothing(srv):
    held = json.loads(srv.log_dose("lsd", 5000, unit="micrograms", route="under the tongue"))
    assert held["held_for_yes"] is True and held["saved"] == "nothing" and held["warnings_to_say_aloud"]
    assert rows(srv, "select * from ingestions") == []
    srv.mono.t += 3
    assert json.loads(srv.confirm_log(held["proposal_id"], "yes, that's right"))["entries"] == 1  # the old yes step still works for these
    assert len(rows(srv, "select * from ingestions")) == 1


def test_an_emergency_sounding_note_is_held_not_saved(srv):
    srv.log_dose("lsd", 100, unit="micrograms", route="under the tongue")
    held = json.loads(srv.log_note("I can't breathe and my chest hurts"))
    assert held.get("held_for_yes") is True and rows(srv, "select * from timed_notes") == []


def test_log_now_still_obeys_the_hourly_cap(srv):
    for _ in range(12):
        assert "Not done" not in srv.log_drink("beer")
    assert srv.log_drink("beer").startswith("Not done")


def test_the_prepare_tools_still_write_nothing(srv):
    prepared(srv.prepare_drink("beer"))
    assert rows(srv, "select * from ingestions") == []


def test_the_dose_hold_uses_the_audited_high_and_heavy_edges(srv):
    # Cocaine snorted: the catalog's heavy is 150 mg, the cross-checked audit (PsychonautWiki now, TripSit) puts it at 90 mg.
    roa = srv.resolve_route(srv.resolve_substance("cocaine"), "snorted")
    assert roa["dose_heavy"] == 150
    assert "heavy" in srv.dose_warning(roa, 100)
    assert srv.dose_warning(roa, 50) == ""
    held = json.loads(srv.log_dose("cocaine", 100, unit="mg", route="snorted"))
    assert held["held_for_yes"] is True and held["saved"] == "nothing"
    # A route the audit does not cover keeps the catalog's own bands.
    shrooms = srv.resolve_route(srv.resolve_substance("psilocybin mushrooms"), "oral")
    assert id(shrooms) not in srv._audited_edges
    assert "heavy" in srv.dose_warning(shrooms, shrooms["dose_heavy"])


def test_without_the_audit_file_the_catalog_bands_stand(srv, tmp_path, monkeypatch):
    data = tmp_path / "data"
    data.mkdir()
    real = SERVER.parents[2] / "app" / "assets" / "data"
    for name in ("substances.json", "substances_extra.json"):
        (data / name).write_text((real / name).read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DATA", str(data))
    srv._catalog = None
    roa = srv.resolve_route(srv.resolve_substance("cocaine"), "snorted")
    assert srv._audited_edges == {}
    assert srv.dose_warning(roa, 100) == ""
    (data / "dose_audit.json").write_text("{not json", encoding="utf-8")
    srv._catalog = None
    roa = srv.resolve_route(srv.resolve_substance("cocaine"), "snorted")
    assert srv._audited_edges == {} and srv.dose_warning(roa, 100) == ""
