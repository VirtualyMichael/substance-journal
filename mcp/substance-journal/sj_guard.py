"""The safety layer between an AI and the Substance Journal database.

What an AI can do through this module, and nothing more:

* read the journal (read-only connections);
* add doses, drinks and notes, after a two-step prepare -> the person says yes -> confirm;
* undo entries it added itself, recently, if nobody has touched them since (a soft delete, like the app's own).

It cannot edit or delete anything else. That is enforced three ways: there is no code path for it, the write
connection carries a SQLite authorizer that refuses every statement except the few INSERTs (and, inside undo only,
the soft-delete UPDATE) this module needs, and a backup of the journal is taken before writing.

The assistant's own record (what it added, for undo, the hourly cap and "added by the assistant") lives in a small
separate SQLite file next to the backups, never in the app's database, so the app's migrations and sync never see it.

Two backends do the reading and writing behind the same guard:

* LinkBackend: the app's voice assistant link. While the person has it switched on (Settings > Voice assistant), the open
  app answers on 127.0.0.1 with a token from voice-assistant/link.json and writes the entries itself, so an encrypted
  journal stays encrypted (the app never hands out its key). Preferred whenever it answers.
* SqliteBackend: the journal file directly, for an unencrypted journal (and the tests).

The prepare/confirm flow, the clear yes, the caps, proposal expiry, the assistant's log and the undo window are the same
for both; the app also enforces its own caps on the link, independently.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import sqlite3
import sys
import time
import urllib.parse
import urllib.error
import urllib.request
import uuid
from contextlib import closing
from dataclasses import dataclass, field, fields
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable

DB_NAME = "substance_journal.sqlite"
AI_NODE = "mcp"  # the HLC node id: entries are stamped like another device, so sync carries them to the phone

# Fixed rules. These are code: neither the AI nor the limits file can change them.
PROPOSAL_TTL_SECONDS = 300
MIN_CONFIRM_DELAY_SECONDS = 2.0
MAX_PENDING = 10
NOTE_MAX_CHARS = 500
EXPERIENCE_JOIN_HOURS = 12  # how the app groups doses into one session
PREWRITE_BACKUP_MINUTES = 10
KEEP_BACKUPS = 30
WRITABLE_TABLES = ("ingestions", "experiences", "timed_notes")
LINK_FILE = "link.json"
LINK_PING_SECONDS = 1.0  # how long the app has to answer "are you there"
LINK_CALL_SECONDS = 5.0
LINK_RETRIES = 3
TURN_ON_LINK = "Open Substance Journal and turn on Settings > Voice assistant."
ENCRYPTED_NO_LINK = ("The journal is encrypted (the app keeps its key to itself), so the assistant can only work through the open app. "
                     + TURN_ON_LINK)


@dataclass(frozen=True)
class Limits:
    """Caps on what the assistant may log. Change them in assistant_limits.json (the AI has no tool that writes it);
    values are kept inside BOUNDS whatever the file says."""

    max_backdate_hours: float = 24.0  # how far into the past a log may go (never into the future)
    max_entries_per_hour: int = 12  # doses + drinks + notes the assistant may add in any hour
    max_drinks_per_log: int = 6  # drinks in one "log two beers"
    undo_window_minutes: int = 10  # how long the assistant can take back its own entry


BOUNDS = {
    "max_backdate_hours": (1, 72),
    "max_entries_per_hour": (1, 30),
    "max_drinks_per_log": (1, 10),
    "undo_window_minutes": (1, 30),
}


def load_limits(path: Path) -> Limits:
    defaults = Limits()
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return defaults
    if not isinstance(raw, dict):
        return defaults
    values = {}
    for f in fields(Limits):
        try:
            v = float(raw[f.name])
        except (KeyError, TypeError, ValueError):
            continue
        lo, hi = BOUNDS[f.name]
        v = min(max(v, lo), hi)
        values[f.name] = int(v) if isinstance(getattr(defaults, f.name), int) else v
    return Limits(**{**defaults.__dict__, **values})


class JournalError(Exception):
    """A refusal that is safe to read back to the person."""


# ---- which database --------------------------------------------------------------------------------------------
def app_db_path(platform: str | None = None) -> Path:
    """Where the installed app keeps its journal. The Flutter app writes to getApplicationSupportDirectory(), which on
    Windows is %APPDATA%\\<CompanyName>\\<ProductName> from app/windows/runner/Runner.rc (com.substancejournal,
    Substance Journal), and on Linux $XDG_DATA_HOME/<APPLICATION_ID> from app/linux/CMakeLists.txt."""
    platform = platform or sys.platform
    if platform == "win32":
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")
        return base / "com.substancejournal" / "Substance Journal" / DB_NAME
    if platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "com.substancejournal.substanceJournalApp" / DB_NAME
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    return base / "com.substancejournal.substance_journal_app" / DB_NAME


def resolve_db_path(platform: str | None = None) -> tuple[Path, str]:
    """(path, where it came from). SUBSTANCE_JOURNAL_DB overrides; otherwise only the installed app's own file.
    It never falls back to another copy (an older install's folder, say): it says which file it expected instead."""
    env = os.environ.get("SUBSTANCE_JOURNAL_DB")
    if env:
        p = Path(env)
        if not p.is_file():
            raise JournalError(f"SUBSTANCE_JOURNAL_DB points to {p}, which does not exist.")
        return p, "SUBSTANCE_JOURNAL_DB"
    p = app_db_path(platform)
    if p.is_file():
        return p, "the installed app's folder"
    others = [o for o in p.parent.parent.glob(f"*/{DB_NAME}") if o != p] if p.parent.parent.is_dir() else []
    extra = f" Other copies exist ({'; '.join(str(o) for o in others)}) but are not used automatically." if others else ""
    raise JournalError(f"The journal was not found at {p}. Open the app once, or set SUBSTANCE_JOURNAL_DB.{extra}")


def is_encrypted(path: Path) -> bool:
    """True when the file is not a plain SQLite database (the app encrypts its journal at rest by default)."""
    try:
        with open(path, "rb") as f:
            head = f.read(16)
    except OSError:
        return False
    return len(head) > 0 and head != b"SQLite format 3\x00"


# ---- the person's answer ------------------------------------------------------------------------------------------
_YES_START = {"yes", "yeah", "yep", "yup", "sure", "ok", "okay", "confirm", "confirmed", "correct", "affirmative", "go", "do",
              "please", "log", "add", "save", "undo", "that", "that's", "thats", "right", "y"}
_YES_FILLER = _YES_START | {"it", "ahead", "is", "i", "so", "thanks", "thank", "you", "one", "please"}
_NEGATE = {"no", "nope", "nah", "dont", "don't", "not", "cancel", "stop", "wait", "never", "negative", "hold", "but", "maybe",
           "change", "actually", "instead", "wrong", "hmm", "um", "uh", "later"}


def user_said_yes(reply: str) -> bool:
    """A clear yes: starts with an affirmative, uses only affirmative filler, and contains no negation or hesitation."""
    words = re.findall(r"[a-z']+", (reply or "").lower().replace("’", "'"))
    if not words or any(w in _NEGATE for w in words):
        return False
    return words[0] in _YES_START and all(w in _YES_FILLER for w in words)


# ---- HLC stamps ------------------------------------------------------------------------------------------------------
_last = [0, 0]


def hlc(now_ms: int | None = None) -> str:
    """`<15-digit ms>-<4-hex counter>-mcp`, the app's hybrid-logical-clock text form, strictly increasing in this process."""
    ms = int(time.time() * 1000) if now_ms is None else now_ms
    if ms > _last[0]:
        _last[0], _last[1] = ms, 0
    else:
        _last[1] += 1
        if _last[1] > 0xFFFF:
            _last[0], _last[1] = _last[0] + 1, 0
    return f"{_last[0]:015d}-{_last[1]:04x}-{AI_NODE}"


def to_s(dt: datetime) -> int:
    return int(dt.timestamp())


def from_s(s: int) -> datetime:
    return datetime.fromtimestamp(s)


_LOG_SCHEMA = """
CREATE TABLE IF NOT EXISTS assistant_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    journal TEXT NOT NULL,
    proposal_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    table_name TEXT NOT NULL,
    row_id TEXT NOT NULL,
    row_hlc TEXT NOT NULL,
    summary TEXT NOT NULL,
    created_at TEXT NOT NULL,
    undone_at TEXT
);
CREATE INDEX IF NOT EXISTS assistant_log_created ON assistant_log(journal, created_at);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


@dataclass
class Proposal:
    id: str
    kind: str  # dose | drink | note
    person_id: str
    person_name: str
    at: datetime
    readback: str
    created: float
    items: list[dict] = field(default_factory=list)  # ingestion rows, or one {"note": text}
    warnings: list[str] = field(default_factory=list)
    backend: str = "sqlite"  # which backend prepared it; confirm must use the same one


# ---- backends --------------------------------------------------------------------------------------------------------
class LinkDown(JournalError):
    """The app's link did not answer (closed, switched off, or a stale link file)."""


class SqliteBackend:
    """The journal file itself (unencrypted journals only). Writes go through the guard's authorizer connection."""

    kind = "sqlite"

    def __init__(self, guard: "Guard") -> None:
        self.g = guard

    def describe(self) -> str:
        return f"Journal file in use: {self.g.db_path} (from {self.g.db_source})."

    def people(self) -> list[dict]:
        rows = self.g.query("select id, name, is_default from people where deleted=0 order by is_default desc, name")
        return [{"id": r["id"], "name": r["name"], "is_default": bool(r["is_default"])} for r in rows]

    def presets(self, drinks: bool) -> list[dict]:
        op = "=" if drinks else "!="
        return [dict(r) for r in self.g.query(f"select * from presets where deleted=0 and substance_key{op}'alcohol' order by substance_key, name")]

    def session_near(self, person: dict, at: datetime) -> bool:
        with closing(self.g.reader()) as c:
            return self.g.experience_near(c, person["id"], at) is not None

    def recent(self, person: dict, limit: int) -> tuple[list[dict], set[str]]:
        g = self.g
        doses = g.query(
            "select 'dose' kind, id, time, substance_key, route, dose, unit, details_json, '' note from ingestions "
            "where deleted=0 and person_id=? order by time desc limit ?", (person["id"], limit))
        notes = g.query(
            "select 'note' kind, n.id, n.time, '' substance_key, '' route, null dose, '' unit, '{}' details_json, n.note from timed_notes n "
            "join experiences e on e.id=n.experience_id where n.deleted=0 and e.person_id=? order by n.time desc limit ?", (person["id"], limit))
        items = sorted([dict(r) for r in [*doses, *notes]], key=lambda r: r["time"], reverse=True)[:limit]
        return items, g.assistant_rows()

    def write(self, prop: Proposal) -> list[tuple[str, str, str]]:
        g = self.g
        g.backup("prewrite")
        written: list[tuple[str, str, str]] = []  # (table, id, hlc)
        with closing(g._writer()) as c:
            with c:
                if prop.kind == "note":
                    near = g.experience_near(c, prop.person_id, prop.at)
                    if near is None:
                        raise JournalError("There is no session in the 12 hours around that time to put the note on. Nothing was saved.")
                    nid, h = str(uuid.uuid4()), hlc()
                    c.execute(
                        "insert into timed_notes(id,hlc,deleted,experience_id,time,note,show_on_timeline) values(?,?,0,?,?,?,1)",
                        (nid, h, near["experience_id"], to_s(prop.at), prop.items[0]["note"]),
                    )
                    written.append(("timed_notes", nid, h))
                else:
                    near = g.experience_near(c, prop.person_id, prop.at)
                    created = near is None
                    if created:
                        exp_id, h = str(uuid.uuid4()), hlc()
                        c.execute(
                            "insert into experiences(id,hlc,deleted,person_id,title,notes,sort_date,created_at,is_favorite) values(?,?,0,?,?,?,?,?,0)",
                            (exp_id, h, prop.person_id, "", "", to_s(prop.at), to_s(g.now())),
                        )
                        written.append(("experiences", exp_id, h))
                    else:
                        exp_id = near["experience_id"]
                    for it in prop.items:
                        iid, h = str(uuid.uuid4()), hlc()
                        details = {**it.get("details", {}), "source": "mcp", "addedBy": "voice assistant", "experienceCreated": created}
                        c.execute(
                            "insert into ingestions(id,hlc,deleted,experience_id,person_id,substance_key,route,time,dose,unit,dose_is_estimate,notes,details_json)"
                            " values(?,?,0,?,?,?,?,?,?,?,0,?,?)",
                            (iid, h, exp_id, prop.person_id, it["substance_key"], it["route"], to_s(prop.at), it["dose"], it["unit"],
                             it.get("notes", ""), json.dumps(details, ensure_ascii=False)),
                        )
                        written.append(("ingestions", iid, h))
        return written

    def undo(self, batch: list) -> tuple[list, list[str], list]:
        """(removed log rows, reasons for what was left, log rows of sessions to mark undone)."""
        g = self.g
        removable, skipped = [], []
        with closing(g.reader()) as c:
            for b in batch:
                if b["table_name"] == "experiences":
                    continue
                row = c.execute(f"select hlc, deleted from {b['table_name']} where id=?", (b["row_id"],)).fetchone()
                if row is None or row["deleted"]:
                    skipped.append("one entry is already gone")
                elif row["hlc"] != b["row_hlc"]:
                    skipped.append("one entry was changed in the app, so it was left alone")
                else:
                    removable.append(b)
        sessions = [b for b in batch if b["table_name"] == "experiences"]
        if removable:
            g.backup("prewrite")
            g._undoing = True
            try:
                with closing(g._writer()) as c:
                    with c:
                        for b in removable:
                            c.execute(f"update {b['table_name']} set deleted=1, hlc=? where id=? and hlc=?", (hlc(), b["row_id"], b["row_hlc"]))
                        for s in sessions:  # a session the assistant created goes too, if nothing else is in it and it is untouched
                            left = c.execute("select count(*) from ingestions where experience_id=? and deleted=0", (s["row_id"],)).fetchone()[0]
                            left += c.execute("select count(*) from timed_notes where experience_id=? and deleted=0", (s["row_id"],)).fetchone()[0]
                            if left == 0:
                                c.execute("update experiences set deleted=1, hlc=? where id=? and hlc=?", (hlc(), s["row_id"], s["row_hlc"]))
            finally:
                g._undoing = False
        return removable, skipped, sessions if removable else []


class LinkBackend:
    """The open app's voice assistant link (see app/lib/data/assistant_link.dart). Uses only the standard library, always
    to 127.0.0.1, never through a proxy, with short timeouts."""

    kind = "link"

    def __init__(self, port: int, token: str, pid: int, *, timeout: float = LINK_CALL_SECONDS) -> None:
        self.port, self.token, self.pid, self.timeout = port, token, pid, timeout
        self._status: dict | None = None
        self._open = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    @classmethod
    def discover(cls, path: Path, ping: float = LINK_PING_SECONDS) -> "LinkBackend | None":
        """The link named in link.json, if the app behind it answers within `ping` seconds as the same process. A stale
        file (app closed, another run's pid or port, wrong token) gives None."""
        try:
            raw = json.loads(Path(path).read_text(encoding="utf-8"))
            port, token, pid = int(raw["port"]), str(raw["token"]), int(raw["pid"])
        except (OSError, ValueError, KeyError, TypeError):
            return None
        if not (0 < port < 65536) or not token:
            return None
        link = cls(port, token, pid)
        try:
            status = link._call("GET", "/v1/status", timeout=ping)
        except JournalError:
            return None
        if status.get("pid") != pid:
            return None
        link._status = status
        return link

    def _call(self, method: str, path: str, body: dict | None = None, *, timeout: float | None = None) -> dict:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data, method=method,
                                     headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
        try:
            with self._open.open(req, timeout=timeout or self.timeout) as r:
                return json.loads(r.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as e:
            try:
                msg = json.loads(e.read().decode("utf-8") or "{}").get("error")
            except ValueError:
                msg = None
            if e.code == 401:
                raise LinkDown("The app's voice assistant link refused the key (it was turned off and on again). " + TURN_ON_LINK) from None
            raise JournalError(msg or f"The app refused that (HTTP {e.code}).") from None
        except (urllib.error.URLError, OSError, ValueError) as e:
            raise LinkDown(f"The app's voice assistant link is not answering. {TURN_ON_LINK}") from e

    def describe(self) -> str:
        return "Connected to the open Substance Journal app through its voice assistant link (Settings > Voice assistant)."

    def status(self) -> dict:
        if self._status is None:
            self._status = self._call("GET", "/v1/status")
        return self._status

    def caps(self) -> dict:
        return self.status().get("caps", {})

    def people(self) -> list[dict]:
        return [{"id": p["name"], "name": p["name"], "is_default": bool(p.get("default"))} for p in self.status().get("people", [])]

    def presets(self, drinks: bool) -> list[dict]:
        pre = self.status().get("presets", {})
        if drinks:
            return [{"name": d["name"], "substance_key": "alcohol", "route": "oral", "amount": d["volume"], "unit": d["unit"],
                     "details_json": json.dumps({"abv": d.get("abv", 0)})} for d in pre.get("drink", [])]
        return [{"name": d["name"], "substance_key": d["substance"], "route": d["route"], "amount": d["amount"], "unit": d["unit"],
                 "details_json": "{}"} for d in pre.get("dose", [])]

    def session_near(self, person: dict, at: datetime) -> bool | None:
        items, _ = self.recent(person, 20)
        doses = [r for r in items if r["kind"] == "dose"]
        if len(doses) < 20 and not any(abs(r["time"] - to_s(at)) <= EXPERIENCE_JOIN_HOURS * 3600 for r in doses):
            return False
        return None  # the app decides when the entry is sent

    def recent(self, person: dict, limit: int) -> tuple[list[dict], set[str]]:
        q = urllib.parse.urlencode({"person": person["name"], "limit": limit})
        out = self._call("GET", f"/v1/recent?{q}")
        items, ai = [], set()
        for x in out.get("items", []):
            items.append({
                "kind": "note" if x.get("kind") == "note" else "dose",
                "id": x["id"],
                "time": to_s(datetime.fromisoformat(x["at"])),
                "substance_key": x.get("substance", ""),
                "route": x.get("route", ""),
                "dose": x.get("dose"),
                "unit": x.get("unit") or "",
                "details_json": json.dumps({"drink": x.get("drink")} if x.get("drink") else {}),
                "note": x.get("note", ""),
            })
            if x.get("by_assistant"):
                ai.add(x["id"])
        return items, ai

    def active(self, person: dict) -> dict:
        return self._call("GET", "/v1/active?" + urllib.parse.urlencode({"person": person["name"]}))

    def add(self, payload: dict) -> dict:
        """One entry; retried with the same request_id (the app saves each request id once)."""
        last: Exception | None = None
        for attempt in range(LINK_RETRIES):
            try:
                return self._call("POST", "/v1/entries", payload)
            except LinkDown as e:
                last = e
                time.sleep(0.2 * (attempt + 1))
        raise last  # type: ignore[misc]

    def write(self, prop: Proposal) -> list[tuple[str, str, str]]:
        written: list[tuple[str, str, str]] = []
        nonce = uuid.uuid4().hex[:12]
        try:
            for i, it in enumerate(prop.items):
                payload = {"request_id": f"{prop.id}-{nonce}-{i}", "person": prop.person_name, "at": prop.at.isoformat(timespec="seconds")}
                details = it.get("details", {})
                if prop.kind == "note":
                    payload.update(kind="note", text=it["note"])
                elif prop.kind == "drink":
                    payload.update(kind="drink", drink=details.get("drink", ""), volume=details.get("volume"),
                                   volume_unit=details.get("volumeUnit"), abv=details.get("abv", 0))
                else:
                    payload.update(kind="preset" if details.get("preset") else "dose", substance=it["substance_key"], route=it["route"],
                                   dose=it["dose"], unit=it["unit"], notes=it.get("notes", ""))
                    if details.get("preset"):
                        payload["preset"] = details["preset"]
                out = self.add(payload)
                if out.get("experience_created"):
                    written.append(("experiences", out["experience_id"], ""))
                written.append((out.get("table", "ingestions"), out["id"], out.get("hlc", "")))
        except JournalError as e:
            if not written:
                raise
            raise PartialWrite(written, e) from None
        return written

    def undo(self, batch: list) -> tuple[list, list[str], list]:
        rows = [b for b in batch if b["table_name"] != "experiences"]
        out = self._call("POST", "/v1/undo", {"ids": [b["row_id"] for b in rows]})
        gone = set(out.get("removed", []))
        removed = [b for b in rows if b["row_id"] in gone]
        skipped = [f"one entry was left alone: {s.get('reason', 'refused')}" for s in out.get("skipped", [])]
        sessions = [b for b in batch if b["table_name"] == "experiences"] if removed else []
        return removed, skipped, sessions


class PartialWrite(JournalError):
    """Some entries of a proposal were saved before the app refused the rest."""

    def __init__(self, written: list, cause: Exception) -> None:
        super().__init__(str(cause))
        self.written, self.cause = written, cause


class Guard:
    def __init__(
        self,
        db_path: Path | None = None,
        *,
        sidecar: Path | None = None,
        now: Callable[[], datetime] = datetime.now,
        monotonic: Callable[[], float] = time.monotonic,
        limits: Limits | None = None,
        link_file: Path | None = None,
    ) -> None:
        if db_path is None:
            db_path, self.db_source = resolve_db_path()
        else:
            self.db_source = "given"
        self.db_path = Path(db_path).resolve()
        if not self.db_path.is_file():
            raise JournalError(f"The journal was not found at {self.db_path}.")
        self.sidecar = Path(sidecar or os.environ.get("SUBSTANCE_JOURNAL_ASSISTANT_DIR") or self.db_path.parent / "voice-assistant")
        self.backups = self.sidecar / "backups"
        self.limits_path = self.sidecar / "assistant_limits.json"
        # The app writes its link file beside the journal, whatever the sidecar folder is.
        self.link_file = Path(link_file or os.environ.get("SUBSTANCE_JOURNAL_LINK") or self.db_path.parent / "voice-assistant" / LINK_FILE)
        self._now, self._mono = now, monotonic
        self._limits = limits
        self._proposals: dict[str, Proposal] = {}
        self._undoing = False

    # ---- which backend ---------------------------------------------------------------------------------------------
    def link(self) -> LinkBackend | None:
        return LinkBackend.discover(self.link_file)

    def backend(self) -> "LinkBackend | SqliteBackend":
        """The app's link when it answers; else the file itself, if it is not encrypted; else the plain instruction."""
        link = self.link()
        if link is not None:
            return link
        self._check_plain()
        return SqliteBackend(self)

    # ---- connections ---------------------------------------------------------------------------------------------
    def _check_plain(self) -> None:
        if is_encrypted(self.db_path):
            raise JournalError(ENCRYPTED_NO_LINK)

    def reader(self) -> sqlite3.Connection:
        self._check_plain()
        c = sqlite3.connect(self.db_path.as_uri() + "?mode=ro", uri=True, timeout=15)
        c.row_factory = sqlite3.Row
        return c

    def _writer(self) -> sqlite3.Connection:
        self._check_plain()
        c = sqlite3.connect(self.db_path, timeout=15)
        c.row_factory = sqlite3.Row
        c.set_authorizer(self._authorize)
        return c

    def _authorize(self, action, arg1, arg2, dbname, source):
        ok, deny = sqlite3.SQLITE_OK, sqlite3.SQLITE_DENY
        if action in (sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_FUNCTION, sqlite3.SQLITE_TRANSACTION, sqlite3.SQLITE_SAVEPOINT):
            return ok
        if action == sqlite3.SQLITE_INSERT and arg1 in WRITABLE_TABLES:
            return ok
        if action == sqlite3.SQLITE_UPDATE and self._undoing and arg1 in WRITABLE_TABLES and arg2 in ("deleted", "hlc"):
            return ok
        return deny

    def _log(self) -> sqlite3.Connection:
        self.sidecar.mkdir(parents=True, exist_ok=True)
        c = sqlite3.connect(self.sidecar / "assistant_log.sqlite", timeout=15)
        c.row_factory = sqlite3.Row
        c.executescript(_LOG_SCHEMA)
        return c

    def limits(self) -> Limits:
        return self._limits or load_limits(self.limits_path)

    def now(self) -> datetime:
        return self._now()

    # ---- reads -----------------------------------------------------------------------------------------------------
    def query(self, sql: str, args=()) -> list[sqlite3.Row]:
        with closing(self.reader()) as c:
            return c.execute(sql, args).fetchall()

    def person(self, name: str | None, backend=None) -> dict:
        rows = (backend or self.backend()).people()
        if not rows:
            raise JournalError("The journal has no people yet. Open the app once first.")
        if name and name.strip():
            for r in rows:
                if r["name"].lower() == name.strip().lower():
                    return r
            raise JournalError(f"No person called {name}. People: {', '.join(r['name'] for r in rows)}.")
        return next((r for r in rows if r["is_default"]), rows[0])

    def experience_near(self, con, person_id: str, at: datetime):
        """The person's session within 12 hours of `at`, as the app groups them."""
        lo, hi = to_s(at - timedelta(hours=EXPERIENCE_JOIN_HOURS)), to_s(at + timedelta(hours=EXPERIENCE_JOIN_HOURS))
        return con.execute(
            "select experience_id from ingestions where person_id=? and deleted=0 and time between ? and ? order by abs(time-?) limit 1",
            (person_id, lo, hi, to_s(at)),
        ).fetchone()

    def assistant_rows(self) -> set[str]:
        """Row ids the assistant added and has not undone (for 'added by the assistant')."""
        if not (self.sidecar / "assistant_log.sqlite").exists():
            return set()
        with closing(self._log()) as c:
            return {r[0] for r in c.execute("select row_id from assistant_log where journal=? and undone_at is null", (str(self.db_path),))}

    def meta(self, key: str) -> str | None:
        if not (self.sidecar / "assistant_log.sqlite").exists():
            return None
        with closing(self._log()) as c:
            r = c.execute("select value from meta where key=?", (key,)).fetchone()
        return r[0] if r else None

    def set_meta(self, key: str, value: str) -> None:
        with closing(self._log()) as c, c:
            c.execute("insert or replace into meta(key, value) values(?, ?)", (key, value))

    # ---- step 1: prepare (writes nothing) ----------------------------------------------------------------------------
    def when(self, minutes_ago: float) -> datetime:
        try:
            m = float(minutes_ago)
        except (TypeError, ValueError):
            raise JournalError("minutes_ago must be a number.") from None
        hours = self.limits().max_backdate_hours
        if m < 0:
            raise JournalError("I can't log something in the future. Say how long ago it was, or nothing for now.")
        if m > hours * 60:
            raise JournalError(f"I can only log things from the last {hours:g} hours. Older entries go in the app.")
        return (self.now() - timedelta(minutes=m)).replace(microsecond=0)

    def propose(self, kind: str, person, at: datetime, readback: str, items: list[dict], warnings: list[str], backend=None) -> Proposal:
        self._expire()
        self._check_rate(len(items))
        if len(self._proposals) >= MAX_PENDING:
            raise JournalError("Too many unconfirmed entries are waiting. Ask the person what they want to log.")
        prop = Proposal(secrets.token_hex(4), kind, person["id"], person["name"], at, readback, self._mono(), items, warnings,
                        getattr(backend, "kind", "sqlite"))
        self._proposals[prop.id] = prop
        return prop

    # ---- step 2: confirm (the only way the AI adds anything) ---------------------------------------------------------
    def confirm(self, proposal_id: str, user_reply: str) -> dict:
        self._expire()
        prop = self._proposals.get((proposal_id or "").strip())
        if prop is None:
            raise JournalError("That entry was not prepared, or it expired. Prepare it again and ask the person to confirm.")
        if not user_said_yes(user_reply):
            raise JournalError("The reply was not a clear yes, so nothing was saved. Ask again, or drop it.")
        if self._mono() - prop.created < MIN_CONFIRM_DELAY_SECONDS:
            raise JournalError("Read the entry back to the person and wait for their answer before confirming. Nothing was saved.")
        return self._commit(prop)

    def log_now(self, prop: Proposal) -> dict:
        """The person asked to log something and wants it saved straight away and told what was saved (no yes/no step). An entry with a warning
        (a dose above the reference's strong range, a note that sounds like an emergency) is NOT saved this way: it is held for confirm()."""
        if prop.warnings:
            raise JournalError("Held for a yes: " + " ".join(prop.warnings))
        if prop.id not in self._proposals:
            raise JournalError("That entry was not prepared, or it expired. Prepare it again.")
        return self._commit(prop)

    def _commit(self, prop: Proposal) -> dict:
        self._check_rate(len(prop.items))
        backend = self.backend()
        if backend.kind != prop.backend:
            del self._proposals[prop.id]
            raise JournalError("The connection to the journal changed since this was prepared (the app's link was turned on or off). "
                               "Nothing was saved; prepare it again.")
        del self._proposals[prop.id]  # single use: a repeated commit can never log twice

        stamp = self.now().isoformat(timespec="seconds")
        saved = re.sub(r"^(Log|Add) ", "", prop.readback)
        partial: PartialWrite | None = None
        try:
            written = backend.write(prop)
        except PartialWrite as e:
            written, partial = e.written, e
        with closing(self._log()) as lg, lg:
            for table, rid, h in written:
                lg.execute(
                    "insert into assistant_log(journal,proposal_id,kind,table_name,row_id,row_hlc,summary,created_at) values(?,?,?,?,?,?,?,?)",
                    (str(self.db_path), prop.id, prop.kind, table, rid, h, saved, stamp),
                )
        entries = sum(1 for t, _, _ in written if t != "experiences")
        if partial is not None:
            raise JournalError(f"Only {entries} of {len(prop.items)} were saved; the app refused the rest: {partial.cause} "
                               "The saved ones can be undone with 'undo that'.")
        return {"saved": saved, "entries": entries,
                "warnings": prop.warnings, "undo": f"The person can say 'undo that' within {self.limits().undo_window_minutes} minutes."}

    # ---- undo (own, recent, untouched entries only) ------------------------------------------------------------------
    def undo_last(self, user_reply: str) -> dict:
        if not user_said_yes(user_reply):
            raise JournalError("Ask the person to confirm the undo with a clear yes. Nothing was removed.")
        backend = self.backend()  # says plainly when there is no way in, before anything else
        window = self.limits().undo_window_minutes
        cutoff = (self.now() - timedelta(minutes=window)).isoformat(timespec="seconds")
        with closing(self._log()) as lg:
            last = lg.execute(
                "select proposal_id, summary from assistant_log where journal=? and undone_at is null and created_at >= ? order by id desc limit 1",
                (str(self.db_path), cutoff),
            ).fetchone()
            if last is None:
                raise JournalError(f"Nothing to undo: the assistant added nothing in the last {window} minutes that is still there. Older entries are changed in the app.")
            batch = lg.execute("select * from assistant_log where proposal_id=? and undone_at is null", (last["proposal_id"],)).fetchall()

        removed, skipped, sessions = backend.undo(batch)
        if removed:
            done = self.now().isoformat(timespec="seconds")
            with closing(self._log()) as lg, lg:
                ids = [b["id"] for b in removed] + [s["id"] for s in sessions]
                lg.execute(f"update assistant_log set undone_at=? where id in ({','.join('?' * len(ids))})", (done, *ids))
        return {"removed": len(removed), "what": last["summary"] if removed else None, "left_alone": skipped}

    # ---- helpers -----------------------------------------------------------------------------------------------------
    def backup(self, kind: str = "daily") -> Path | None:
        """Copy the journal into the sidecar's backups folder: 'daily' once a calendar day, 'prewrite' at most every 10 minutes.
        Not while the app's link is in use: then the app owns the file (and keeps its own backups)."""
        if self.link() is not None:
            return None
        now = self.now()
        self.backups.mkdir(parents=True, exist_ok=True)
        existing = sorted(self.backups.glob(f"{kind}-*.sqlite"))
        if existing:
            last = datetime.strptime(existing[-1].stem.split("-", 1)[1], "%Y%m%d-%H%M%S")
            if (kind == "daily" and last.date() == now.date()) or (kind != "daily" and now - last < timedelta(minutes=PREWRITE_BACKUP_MINUTES)):
                return None
        target = self.backups / f"{kind}-{now:%Y%m%d-%H%M%S}.sqlite"
        with closing(self.reader()) as src, closing(sqlite3.connect(target)) as dst:
            src.backup(dst)
        for old in sorted(self.backups.glob(f"{kind}-*.sqlite"))[:-KEEP_BACKUPS]:
            old.unlink(missing_ok=True)
        return target

    def _check_rate(self, adding: int) -> None:
        cap = self.limits().max_entries_per_hour
        since = (self.now() - timedelta(hours=1)).isoformat(timespec="seconds")
        n = 0
        if (self.sidecar / "assistant_log.sqlite").exists():
            with closing(self._log()) as c:
                n = c.execute(
                    "select count(*) from assistant_log where journal=? and table_name!='experiences' and created_at >= ?", (str(self.db_path), since)
                ).fetchone()[0]
        if n + adding > cap:
            raise JournalError(f"The assistant can add at most {cap} entries an hour, as a safety limit. Add more in the app.")

    def _expire(self) -> None:
        cutoff = self._mono() - PROPOSAL_TTL_SECONDS
        for k in [k for k, p in self._proposals.items() if p.created < cutoff]:
            del self._proposals[k]
