"""The voice/AI server against a database with the app's real table layout (see the schema below)."""
import importlib.util
import sqlite3
import time
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


@pytest.fixture()
def srv(tmp_path, monkeypatch):
    db = tmp_path / "j.sqlite"
    con = sqlite3.connect(db)
    for stmt in SCHEMA:
        con.execute(stmt)
    con.execute("insert into people(id,hlc,deleted,name,is_default) values('p1','h',0,'Me',1)")
    con.execute("insert into people(id,hlc,deleted,name,is_default) values('p2','h',0,'Alex',0)")
    con.execute(
        "insert into presets(id,hlc,deleted,substance_key,route,name,amount,unit,details_json) "
        "values('d1','h',0,'alcohol','oral','Beer',12,'oz','{\"abv\": 5}')"
    )
    con.execute(
        "insert into presets(id,hlc,deleted,substance_key,route,name,amount,unit,details_json) "
        "values('d2','h',0,'lsd','sublingual','Usual tab',80,'µg','{}')"
    )
    con.commit()
    con.close()
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DB", str(db))
    spec = importlib.util.spec_from_file_location("sj_server", SERVER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.db = db
    return mod


def rows(srv, sql, *args):
    con = sqlite3.connect(srv.db)
    con.row_factory = sqlite3.Row
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


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


def test_a_dose_needs_a_yes_and_is_stored_in_the_routes_own_unit(srv):
    first = srv.log_dose("lsd", 100, unit="micrograms", route="under the tongue")
    assert first.startswith("Ready to log 100 µg of LSD (sublingual)")
    assert rows(srv, "select * from ingestions") == []  # nothing saved before the yes

    done = srv.log_dose("lsd", 100, unit="mcg", route="sublingual", notes="blue tab", confirmed=True)
    assert done.startswith("Logged 100 µg of LSD")
    assert "First time here" in done  # the request format comes with the very first save
    r = rows(srv, "select * from ingestions")[0]
    assert (r["substance_key"], r["route"], r["dose"], r["unit"], r["notes"]) == ("lsd", "sublingual", 100, "µg", "blue tab")
    assert r["person_id"] == "p1" and r["hlc"].endswith("-mcp")
    assert len(rows(srv, "select * from experiences")) == 1

    again = srv.log_dose("lsd", 50, unit="ug", route="sublingual", confirmed=True)
    assert "First time here" not in again  # told once only
    assert len(rows(srv, "select * from experiences")) == 1  # joined the session


def test_a_huge_dose_is_flagged_and_nonsense_is_refused(srv):
    msg = srv.log_dose("lsd", 5000, unit="ug", route="sublingual")
    assert "Check the number and unit" in msg
    assert srv.log_dose("lsd", 0, route="sublingual") == "The dose must be more than zero."
    assert "log_drink" in srv.log_dose("alcohol", 1, route="oral")
    with pytest.raises(ValueError, match="not listed"):
        srv.log_dose("lsd", 1, route="snorted")


def test_drinks_and_presets_and_other_people(srv):
    assert "1.0" in srv.log_drink("beer")  # about one standard drink
    srv.log_drink("beer", count=2, person="Alex", minutes_ago=30, confirmed=True)
    assert len(rows(srv, "select * from ingestions where person_id='p2'")) == 2
    assert srv.log_drink("beer", count=0).startswith("How many")
    assert "Ready to log Usual tab" in srv.log_preset("usual tab")
    srv.log_preset("usual tab", confirmed=True)
    assert rows(srv, "select dose, unit from ingestions where substance_key='lsd'")[0]["dose"] == 80
    with pytest.raises(ValueError):
        srv.log_preset("beer")  # drinks go through log_drink
    with pytest.raises(ValueError):
        srv.log_dose("lsd", 100, route="sublingual", person="Nobody", confirmed=True)


def test_notes_go_on_the_current_session_and_can_be_undone(srv):
    assert "no session" in srv.add_note("anxious", confirmed=True)  # nothing logged yet
    srv.log_dose("lsd", 100, unit="ug", route="sublingual", confirmed=True)
    ready = srv.add_note("feeling anxious", minutes_ago=5)
    assert ready.startswith('Ready to add note "feeling anxious"')
    assert rows(srv, "select * from timed_notes") == []
    srv.add_note("feeling anxious", minutes_ago=5, confirmed=True)
    n = rows(srv, "select * from timed_notes")[0]
    exp = rows(srv, "select experience_id from ingestions")[0]["experience_id"]
    assert n["experience_id"] == exp and n["show_on_timeline"] == 1 and n["time"] <= int(time.time()) - 290
    assert "feeling anxious" in srv.recent()

    assert srv.undo_last(what="note") == "Removed 1 note(s)."
    assert rows(srv, "select deleted from timed_notes")[0]["deleted"] == 1
    assert srv.add_note("   ") == "What should the note say?"


def test_undo_only_touches_what_the_server_added(srv):
    now = int(time.time())
    con = sqlite3.connect(srv.db)
    con.execute("insert into experiences(id,hlc,person_id,sort_date,created_at) values('e1','h','p1',?,?)", (now, now))
    con.execute(
        "insert into ingestions(id,hlc,experience_id,person_id,substance_key,route,time,dose,unit) "
        "values('mine','h','e1','p1','mdma','oral',?,80,'mg')", (now,))
    con.commit()
    con.close()
    assert srv.undo_last() == "Nothing of mine to undo."
    srv.log_dose("lsd", 50, unit="ug", route="sublingual", confirmed=True)
    assert srv.undo_last() == "Removed 1 entry."
    live = rows(srv, "select id from ingestions where deleted=0")
    assert [r["id"] for r in live] == ["mine"]


def test_how_to_ask_covers_doses_notes_and_undo(srv):
    text = srv.how_to_ask()
    for word in ("micrograms", "note", "Undo", "yes"):
        assert word in text
