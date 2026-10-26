"""Substance Journal MCP server: voice/AI logging and reports for the Flutter app's database.

Safe by design: it only ever adds rows (stamped like any other device so sync carries them) and
can soft-delete only entries it created itself. Every log asks for a read-back and a yes first.
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path

try:
    from mcp.server.mcpserver import MCPServer as FastMCP  # mcp 2.x
except ImportError:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x

mcp = FastMCP("substance-journal")

FL_OZ_ML = 29.5735
ETHANOL_G_PER_FL_OZ = 23.36  # matches the app (Alcohol Tracker's density)
STANDARD_DRINK_G = 0.6 * ETHANOL_G_PER_FL_OZ
SHOT_OZ = 1.5


def db_path() -> Path:
    env = os.environ.get("SUBSTANCE_JOURNAL_DB")
    if env:
        return Path(env)
    base = Path(os.environ.get("APPDATA", Path.home() / ".local/share")) / "com.substancejournal"
    found = sorted(base.glob("*/substance_journal.sqlite"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not found:
        raise FileNotFoundError("Substance Journal database not found; set SUBSTANCE_JOURNAL_DB.")
    return found[0]


def connect() -> sqlite3.Connection:
    con = sqlite3.connect(db_path(), timeout=15)
    con.row_factory = sqlite3.Row
    return con


_counter = 0


def hlc() -> str:
    global _counter
    _counter = (_counter + 1) & 0xFFFF
    return f"{int(time.time() * 1000):015d}-{_counter:04x}-mcp"


def to_s(dt: datetime) -> int:
    return int(dt.timestamp())


def from_s(s: int) -> datetime:
    return datetime.fromtimestamp(s)


def person_row(con, name):
    rows = con.execute("select * from people where deleted=0").fetchall()
    if name:
        for r in rows:
            if r["name"].lower() == name.lower():
                return r
        raise ValueError(f"No person called {name}. People: {', '.join(r['name'] for r in rows)}")
    for r in rows:
        if r["is_default"]:
            return r
    return rows[0]


def drink_fl_oz(volume: float, unit: str) -> float:
    u = unit.lower()
    if u in ("oz", "fl oz", "floz"):
        return volume
    if u in ("shot", "shots"):
        return volume * SHOT_OZ
    if u == "ml":
        return volume / FL_OZ_ML
    if u in ("l", "liter", "litre"):
        return volume * 1000 / FL_OZ_ML
    raise ValueError(f"Unknown volume unit {unit}")


def grams(volume: float, unit: str, abv: float) -> float:
    return drink_fl_oz(volume, unit) * abv / 100 * ETHANOL_G_PER_FL_OZ


@mcp.tool()
def list_people() -> str:
    """Names of the people tracked in the journal."""
    with connect() as con:
        return ", ".join(r["name"] for r in con.execute("select name from people where deleted=0"))


@mcp.tool()
def list_presets() -> str:
    """Drink presets that can be logged by name."""
    with connect() as con:
        rows = con.execute("select name from presets where deleted=0 and substance_key='alcohol' order by name").fetchall()
    return "\n".join(r["name"] for r in rows) or "No presets."


def find_preset(con, text: str):
    rows = con.execute("select * from presets where deleted=0 and substance_key='alcohol'").fetchall()
    t = text.lower().strip()
    exact = [r for r in rows if r["name"].lower() == t]
    hits = exact or [r for r in rows if t in r["name"].lower()]
    if not hits:
        raise ValueError(f"No preset matching '{text}'. Try list_presets.")
    if len(hits) > 1 and not exact:
        raise ValueError("More than one match: " + ", ".join(r["name"] for r in hits))
    return hits[0]


def _insert(con, person, at, substance, route, dose, unit, details, notes=""):
    # Join the person's experience within 12 hours, as the app does.
    lo, hi = to_s(at - timedelta(hours=12)), to_s(at + timedelta(hours=12))
    near = con.execute(
        "select experience_id from ingestions where person_id=? and deleted=0 and time between ? and ? order by abs(time-?) limit 1",
        (person["id"], lo, hi, to_s(at)),
    ).fetchone()
    created = near is None
    if created:
        exp_id = str(uuid.uuid4())
        con.execute(
            "insert into experiences(id,hlc,deleted,person_id,title,notes,sort_date,created_at,is_favorite) values(?,?,0,?,?,?,?,?,0)",
            (exp_id, hlc(), person["id"], "", "", to_s(at), to_s(datetime.now())),
        )
    else:
        exp_id = near["experience_id"]
    ing_id = str(uuid.uuid4())
    details = {**details, "source": "mcp", "experienceCreated": created}
    con.execute(
        "insert into ingestions(id,hlc,deleted,experience_id,person_id,substance_key,route,time,dose,unit,dose_is_estimate,notes,details_json)"
        " values(?,?,0,?,?,?,?,?,?,?,0,?,?)",
        (ing_id, hlc(), exp_id, person["id"], substance, route, to_s(at), dose, unit, notes, json.dumps(details)),
    )
    return ing_id


@mcp.tool()
def log_drink(preset: str, count: int = 1, person: str | None = None, minutes_ago: int = 0, confirmed: bool = False) -> str:
    """Log a preset drink. First call with confirmed=false to get a read-back, read it to the user,
    and only call again with confirmed=true after they say yes."""
    with connect() as con:
        p = find_preset(con, preset)
        who = person_row(con, person)
        abv = json.loads(p["details_json"]).get("abv", 0)
        at = datetime.now() - timedelta(minutes=minutes_ago)
        g = grams(p["amount"], p["unit"], abv)
        std = g / STANDARD_DRINK_G
        line = f"{count} x {p['name']} for {who['name']} at {at:%I:%M %p} ({std * count:.1f} standard drinks)"
        if not confirmed:
            return f"Ready to log {line}. Ask the user to confirm, then call again with confirmed=true."
        for _ in range(count):
            _insert(con, who, at, "alcohol", "oral", g, "g",
                    {"drink": p["name"], "volume": p["amount"], "volumeUnit": p["unit"], "abv": abv})
        con.commit()
        return f"Logged {line}."


@mcp.tool()
def log_dose(substance: str, route: str, dose: float, unit: str, person: str | None = None,
             minutes_ago: int = 0, confirmed: bool = False) -> str:
    """Log any other substance dose (e.g. substance 'cannabis', route 'smoked', dose 10, unit 'mg').
    Same two-step confirmation as log_drink."""
    with connect() as con:
        who = person_row(con, person)
        at = datetime.now() - timedelta(minutes=minutes_ago)
        line = f"{dose:g} {unit} {substance} ({route}) for {who['name']} at {at:%I:%M %p}"
        if not confirmed:
            return f"Ready to log {line}. Ask the user to confirm, then call again with confirmed=true."
        _insert(con, who, at, substance.lower(), route.lower(), dose, unit, {})
        con.commit()
        return f"Logged {line}."


@mcp.tool()
def undo_last(count: int = 1) -> str:
    """Remove the most recent entries this server logged (it never touches entries made in the app)."""
    with connect() as con:
        rows = con.execute(
            "select id, experience_id, details_json from ingestions where deleted=0 "
            "and details_json like '%\"source\": \"mcp\"%' order by time desc limit ?", (count,)).fetchall()
        for r in rows:
            con.execute("update ingestions set deleted=1, hlc=? where id=?", (hlc(), r["id"]))
            if json.loads(r["details_json"]).get("experienceCreated"):
                left = con.execute("select count(*) c from ingestions where experience_id=? and deleted=0", (r["experience_id"],)).fetchone()["c"]
                if left == 0:
                    con.execute("update experiences set deleted=1, hlc=? where id=?", (hlc(), r["experience_id"]))
        con.commit()
    return f"Removed {len(rows)} entr{'y' if len(rows) == 1 else 'ies'}." if rows else "Nothing of mine to undo."


def span(period: str, start, end):
    now = datetime.now()
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "custom" and start:
        s = datetime.fromisoformat(start)
        e = datetime.fromisoformat(end) + timedelta(days=1) if end else now + timedelta(seconds=1)
        return s, e
    days = {"today": 0, "week": 6, "month": 29, "year": 364}.get(period)
    if days is None:
        raise ValueError("period must be today, week, month, year or custom")
    return midnight - timedelta(days=days), now + timedelta(seconds=1)


@mcp.tool()
def report(period: str = "week", person: str | None = None, start: str | None = None, end: str | None = None) -> str:
    """Report of what was taken: period today|week|month|year|custom (custom uses start/end as YYYY-MM-DD).
    Alcohol is shown in standard drinks; everything else as total dose per substance."""
    s, e = span(period, start, end)
    with connect() as con:
        who = person_row(con, person)
        rows = con.execute(
            "select substance_key, route, time, dose, unit from ingestions where deleted=0 and person_id=? and time>=? and time<? order by time",
            (who["id"], to_s(s), to_s(e))).fetchall()
    last_day = e - timedelta(seconds=1)
    if not rows:
        return f"{who['name']}: nothing logged from {s:%b %d} to {last_day:%b %d}."
    out = [f"{who['name']}, {s:%b %d} to {last_day:%b %d}:"]
    alc = [r for r in rows if r["substance_key"] == "alcohol"]
    if alc:
        days: dict[str, float] = {}
        for r in alc:
            d = from_s(r["time"]).strftime("%Y-%m-%d")
            days[d] = days.get(d, 0) + (r["dose"] or 0) / STANDARD_DRINK_G
        total = sum(days.values())
        busiest = max(days, key=days.get)
        out.append(f"Alcohol: {total:.1f} standard drinks over {len(days)} day(s), {total / len(days):.1f} per drinking day, "
                   f"most on {busiest} ({days[busiest]:.1f}). Last drink {from_s(alc[-1]['time']):%b %d %I:%M %p}.")
        if len(days) <= 10:
            out.append("  " + "; ".join(f"{d[5:]}: {v:.1f}" for d, v in sorted(days.items())))
    others: dict[tuple, list] = {}
    for r in rows:
        if r["substance_key"] != "alcohol":
            others.setdefault((r["substance_key"], r["unit"] or ""), []).append(r)
    for (sub, unit), rs in sorted(others.items()):
        total = sum(r["dose"] or 0 for r in rs)
        out.append(f"{sub}: {len(rs)} dose(s), {total:g} {unit} total, last {from_s(rs[-1]['time']):%b %d %I:%M %p}.")
    return "\n".join(out)


if __name__ == "__main__":
    mcp.run()
