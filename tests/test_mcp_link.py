"""The voice/AI server talking to the app's voice assistant link, against a fake link: a stdlib HTTP server on 127.0.0.1
that answers like app/lib/data/assistant_link.dart. Nothing here opens the real journal or starts the real app."""
import importlib.util
import json
import os
import threading
import time
import uuid
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest

pytest.importorskip("mcp")

from tests.test_mcp_server import Clock, load_server, make_db, rows  # noqa: E402

TURN_ON = "Open Substance Journal and turn on Settings > Voice assistant."
ENCRYPTED = b"\x8a\x13" * 4096  # an encrypted journal from outside: no SQLite header


class FakeApp:
    """What the app's link answers, with every request kept for the test to look at."""

    def __init__(self, pid: int = os.getpid()):
        self.token = "tok-" + uuid.uuid4().hex
        self.pid = pid
        self.requests: list[dict] = []
        self.entries: dict[str, dict] = {}  # by request_id
        self.removed: set[str] = set()
        self.drop_next_posts = 0  # hang up on this many POST /v1/entries before answering
        self.refuse: tuple[int, str] | None = None
        app = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, body):
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _handle(self, method):
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n)) if n else None
                url = urlparse(self.path)
                app.requests.append({"method": method, "path": url.path, "query": parse_qs(url.query),
                                     "auth": self.headers.get("Authorization"), "body": body})
                if self.headers.get("Authorization") != f"Bearer {app.token}":
                    return self._send(401, {"error": "Not linked."})
                if (method, url.path) == ("GET", "/v1/status"):
                    return self._send(200, app.status())
                if (method, url.path) == ("POST", "/v1/entries"):
                    if app.drop_next_posts:
                        app.drop_next_posts -= 1
                        app.add(body)  # saved, but the answer is lost on the way back
                        self.close_connection = True
                        self.connection.shutdown(2)
                        return None
                    if app.refuse:
                        return self._send(*[app.refuse[0], {"error": app.refuse[1]}])
                    return self._send(200, app.add(body))
                if (method, url.path) == ("POST", "/v1/undo"):
                    ids = body["ids"]
                    ok = [i for i in ids if any(e["id"] == i for e in app.entries.values()) and i not in app.removed]
                    app.removed.update(ok)
                    return self._send(200, {"removed": ok, "skipped": [{"id": i, "reason": "not added through this link"} for i in ids if i not in ok]})
                if (method, url.path) == ("GET", "/v1/recent"):
                    return self._send(200, app.recent())
                if (method, url.path) == ("GET", "/v1/active"):
                    return self._send(200, app.active())
                return self._send(404, {"error": "No such endpoint."})

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def write_link(self, folder: Path, **override):
        folder.mkdir(parents=True, exist_ok=True)
        link = {"version": 1, "port": self.port, "token": self.token, "pid": self.pid, "started": datetime.now().isoformat(timespec="seconds")}
        (folder / "link.json").write_text(json.dumps({**link, **override}))

    # ---- the app's answers ---------------------------------------------------------------------------------------
    def status(self):
        return {
            "app": "Substance Journal", "version": "2.0.0", "link_version": 1, "pid": self.pid,
            "people": [{"name": "Me", "default": True}, {"name": "Alex", "default": False}],
            "presets": {
                "dose": [{"name": "Usual tab", "substance": "lsd", "substance_name": "LSD", "route": "sublingual", "amount": 80.0, "unit": "µg"}],
                "drink": [{"name": "Beer - 12 oz 5%", "volume": 12.0, "unit": "oz", "abv": 5.0}],
            },
            "caps": {"max_backdate_hours": 24.0, "max_entries_per_hour": 12, "undo_window_minutes": 10, "max_note_chars": 500,
                     "max_body_bytes": 65536, "max_recent": 20, "future_allowed": False},
            "entries_last_hour": len(self.entries),
        }

    def add(self, body):
        rid = body["request_id"]
        if rid in self.entries:
            return {**self.entries[rid], "duplicate": True}
        first = not self.entries
        out = {"ok": True, "id": f"row-{len(self.entries) + 1}", "hlc": f"{int(time.time() * 1000):015d}-0000-mcp",
               "table": "timed_notes" if body["kind"] == "note" else "ingestions", "experience_id": "exp-1",
               "experience_created": first and body["kind"] != "note", "summary": "saved", "duplicate": False}
        self.entries[rid] = {**out, "body": body}
        return out

    def recent(self):
        now = datetime.now().replace(microsecond=0)
        return {"person": "Me", "default": True, "items": [
            {"id": "n1", "kind": "note", "at": (now - timedelta(minutes=2)).isoformat(), "note": "peaking", "by_assistant": True},
            {"id": "d1", "kind": "drink", "at": (now - timedelta(minutes=30)).isoformat(), "substance": "alcohol", "name": "Alcohol",
             "route": "oral", "dose": 14.016, "unit": "g", "drink": "Beer - 12 oz 5%", "standard_drinks": 1.0, "by_assistant": True},
            {"id": "i1", "kind": "dose", "at": (now - timedelta(hours=2)).isoformat(), "substance": "lsd", "name": "LSD",
             "route": "sublingual", "dose": 100.0, "unit": "µg", "by_assistant": False},
        ]}

    def active(self):
        now = datetime.now().replace(microsecond=0)
        last = now - timedelta(hours=2)
        return {"person": "Me", "default": True, "now": now.isoformat(), "substances": [
            {"substance": "lsd", "name": "LSD", "route": "sublingual", "phase": "peak", "phase_label": "At its strongest", "doses": 1,
             "last_at": last.isoformat(), "last_dose": 100.0, "unit": "µg", "full_effect_at": (last + timedelta(hours=1)).isoformat(),
             "peak_ends_at": (last + timedelta(hours=5)).isoformat(), "main_effects_end_at": (last + timedelta(hours=9)).isoformat(),
             "linger_ends_at": (last + timedelta(hours=12)).isoformat()}],
            "alcohol": {"standard_drinks_today": 1.0, "drinks_last_24h": [{"at": (now - timedelta(minutes=30)).isoformat(), "grams": 14.016, "standard_drinks": 1.0}]}}

    def posts(self):
        return [r for r in self.requests if r["path"] == "/v1/entries"]


def _server(tmp_path, monkeypatch, *, encrypted: bool):
    db = tmp_path / "journal" / "substance_journal.sqlite"
    if encrypted:
        db.parent.mkdir(parents=True)
        db.write_bytes(ENCRYPTED)
    else:
        make_db(db)
    mod = load_server(monkeypatch, db)
    monkeypatch.delenv("SUBSTANCE_JOURNAL_LINK", raising=False)
    mod.mono = Clock()
    mod._guard = mod.Guard(monotonic=mod.mono)
    mod.db = db
    return mod


@pytest.fixture()
def app():
    a = FakeApp()
    yield a
    a.close()


@pytest.fixture()
def linked(tmp_path, monkeypatch, app):
    """An encrypted journal with the app open and the link on."""
    srv = _server(tmp_path, monkeypatch, encrypted=True)
    app.write_link(srv.db.parent / "voice-assistant")
    return srv


def confirm(srv, text, reply="yes"):
    p = json.loads(text) if not text.startswith("Not done") else pytest.fail(text)
    srv.mono.t += 3
    return srv.confirm_log(p["proposal_id"], reply)


# ---- which way in ------------------------------------------------------------------------------------------------
def test_encrypted_journal_without_the_link_says_how_to_turn_it_on(tmp_path, monkeypatch):
    srv = _server(tmp_path, monkeypatch, encrypted=True)
    outs = [srv.how_to_ask(), srv.list_people(), srv.list_presets(), srv.current_status(), srv.recent(), srv.report("week"),
            srv.prepare_dose("lsd", 100, unit="ug", route="sublingual"), srv.prepare_drink("beer"), srv.prepare_preset("usual tab"),
            srv.prepare_note("hi"), srv.undo_last("yes")]
    for out in outs:
        assert TURN_ON in out, out
    assert srv.db.read_bytes() == ENCRYPTED


def test_a_dead_or_stale_link_falls_back_to_the_plain_message(tmp_path, monkeypatch, app):
    srv = _server(tmp_path, monkeypatch, encrypted=True)
    folder = srv.db.parent / "voice-assistant"
    app.write_link(folder, pid=app.pid + 1)  # another run's file: the app answering is not that process
    assert TURN_ON in srv.list_people()
    app.write_link(folder, token="old-token")  # turned off and on again since: the old key is refused
    assert TURN_ON in srv.list_people()
    app.write_link(folder)
    port = app.port
    app.close()  # the app was closed without turning the link off
    start = time.monotonic()
    assert TURN_ON in srv.list_people()
    assert time.monotonic() - start < 3
    (folder / "link.json").write_text("not json")
    assert TURN_ON in srv.list_people()
    assert port


def test_the_link_is_preferred_even_when_the_file_could_be_opened(tmp_path, monkeypatch, app):
    srv = _server(tmp_path, monkeypatch, encrypted=False)
    app.write_link(srv.db.parent / "voice-assistant")
    assert "voice assistant link" in srv.how_to_ask()
    done = json.loads(confirm(srv, srv.prepare_dose("lsd", 100, unit="ug", route="sublingual")))
    assert done["entries"] == 1
    assert rows(srv, "select * from ingestions") == []  # the app wrote it, not this server
    assert len(app.posts()) == 1
    assert not (srv.db.parent / "voice-assistant" / "backups").exists() or not list((srv.db.parent / "voice-assistant" / "backups").iterdir())


# ---- writing through the link --------------------------------------------------------------------------------------
def test_confirm_sends_one_entry_with_the_token_and_a_request_id(linked, app):
    p = json.loads(linked.prepare_dose("lsd", 100, unit="micrograms", route="under the tongue", notes="blue tab"))
    assert p["read_back_to_user"].startswith("Log 100 micrograms of LSD, under the tongue, for Me, now")
    assert app.posts() == []  # prepare writes nothing
    assert all(r["auth"] == f"Bearer {app.token}" for r in app.requests)

    linked.mono.t += 3
    done = json.loads(linked.confirm_log(p["proposal_id"], "yes"))
    assert done["entries"] == 1
    (post,) = app.posts()
    body = post["body"]
    assert post["auth"] == f"Bearer {app.token}"
    assert body["request_id"].startswith(p["proposal_id"])
    assert {k: body[k] for k in ("kind", "person", "substance", "route", "dose", "unit", "notes")} == {
        "kind": "dose", "person": "Me", "substance": "lsd", "route": "sublingual", "dose": 100, "unit": "µg", "notes": "blue tab"}
    assert abs(datetime.fromisoformat(body["at"]) - datetime.now()) < timedelta(seconds=10)
    # a no or a second confirm sends nothing more
    assert linked.confirm_log(p["proposal_id"], "yes").startswith("Not done")
    assert "Not done" in confirm(linked, linked.prepare_dose("lsd", 50, unit="ug", route="sublingual"), "no")
    assert len(app.posts()) == 1
    # the assistant's own log knows it, for undo and the hourly cap
    import sqlite3
    log = sqlite3.connect(linked._guard.sidecar / "assistant_log.sqlite")
    assert [r[0] for r in log.execute("select row_id from assistant_log where table_name='ingestions'")] == ["row-1"]
    log.close()


def test_drinks_presets_and_notes_go_as_their_own_kinds(linked, app):
    out = json.loads(confirm(linked, linked.prepare_drink("beers", count=2, person="Alex", minutes_ago=30)))
    assert out["entries"] == 2
    a, b = app.posts()
    assert a["body"]["request_id"] != b["body"]["request_id"]
    assert {k: a["body"][k] for k in ("kind", "person", "drink", "volume", "volume_unit", "abv")} == {
        "kind": "drink", "person": "Alex", "drink": "Beer - 12 oz 5%", "volume": 12.0, "volume_unit": "oz", "abv": 5.0}
    confirm(linked, linked.prepare_preset("my usual tab"))
    assert app.posts()[-1]["body"]["kind"] == "preset" and app.posts()[-1]["body"]["preset"] == "Usual tab"
    confirm(linked, linked.prepare_note("feeling fine", minutes_ago=5))
    assert app.posts()[-1]["body"]["kind"] == "note" and app.posts()[-1]["body"]["text"] == "feeling fine"


def test_a_lost_answer_is_retried_with_the_same_request_id(linked, app):
    app.drop_next_posts = 1
    out = json.loads(confirm(linked, linked.prepare_dose("lsd", 100, unit="ug", route="sublingual")))
    assert out["entries"] == 1
    first, second = app.posts()
    assert first["body"]["request_id"] == second["body"]["request_id"]
    assert len(app.entries) == 1  # saved once


def test_the_apps_refusal_is_read_back(linked, app):
    app.refuse = (429, "The assistant can add at most 12 entries an hour, as a safety limit. Add more in the app.")
    out = confirm(linked, linked.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    assert out.startswith("Not done: The assistant can add at most 12")
    app.refuse = None
    app.drop_next_posts = 0


def test_link_turned_off_between_prepare_and_confirm_saves_nothing(linked, app):
    p = json.loads(linked.prepare_dose("lsd", 100, unit="ug", route="sublingual"))
    (linked.db.parent / "voice-assistant" / "link.json").unlink()
    linked.mono.t += 3
    assert TURN_ON in linked.confirm_log(p["proposal_id"], "yes")
    assert app.posts() == []


def test_undo_goes_through_the_link(linked, app):
    confirm(linked, linked.prepare_drink("beer", count=2))
    out = json.loads(linked.undo_last("yes"))
    assert out["removed"] == 2
    undo = [r for r in app.requests if r["path"] == "/v1/undo"][-1]
    assert sorted(undo["body"]["ids"]) == ["row-1", "row-2"]
    assert "Nothing to undo" in linked.undo_last("yes")


# ---- reading through the link -------------------------------------------------------------------------------------
def test_people_presets_recent_and_status_come_from_the_link(linked, app):
    assert linked.list_people() == "Me, Alex"
    presets = linked.list_presets()
    assert "Beer - 12 oz 5%" in presets and "Usual tab (LSD, 80 µg)" in presets
    text = linked.recent()
    assert text.startswith("Me, latest first:")
    assert "note, peaking (added by the assistant)." in text
    assert "Beer - 12 oz 5%, about 1.0 standard drinks (added by the assistant)." in text
    assert "100 micrograms of LSD, under the tongue." in text
    status = linked.current_status()
    assert "LSD, under the tongue: last 100 micrograms 2 hours ago, estimated at its strongest" in status
    assert "Alcohol: about 0.5 standard drinks estimated still being processed" in status
    assert "Reports are not available through the app's voice assistant link" in linked.report("week")
    assert all(r["auth"] == f"Bearer {app.token}" for r in app.requests)
    assert any(r["path"] == "/v1/recent" for r in app.requests) and any(r["path"] == "/v1/active" for r in app.requests)


def test_a_note_with_no_session_nearby_is_caught_before_the_read_back(linked, app, monkeypatch):
    monkeypatch.setattr(app, "recent", lambda: {"person": "Me", "default": True, "items": []})
    assert "no session" in linked.prepare_note("hello")
