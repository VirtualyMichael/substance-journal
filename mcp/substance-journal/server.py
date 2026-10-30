"""Substance Journal MCP server: voice/AI logging, notes and reports for the Flutter app's database.

Safe by design: it only ever adds rows (stamped like any other device so sync carries them) and
can soft-delete only entries it created itself. Every write asks for a read-back and a yes first.
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path

try:
    from mcp.server.mcpserver import MCPServer as FastMCP  # mcp 2.x
except ImportError:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x

HOW_TO_ASK = """How to ask (say it like this):
- A dose:  "Log 100 micrograms of LSD, under the tongue."   -> substance, amount, unit, and how it was taken.
- A drink: "Log a beer."  or  "Log two shots of vodka."     -> a drink preset by name, and how many.
- A saved preset: "Log my usual tab."                       -> any preset you saved in the app, by name.
- A past time: add "20 minutes ago" or "an hour ago". Without it, the time is now.
- Someone else: add "for Alex" (otherwise it is the default person).
- A note:  "Add a note: feeling anxious, drank some water." -> goes on the timeline of your current session.
- Undo:    "Undo that."  (only removes what the assistant added, never entries you made in the app).
- Check:   "What did I log today?"  or  "Report for this week."
I will read it back and wait for you to say yes before anything is saved."""

mcp = FastMCP(
    "substance-journal",
    instructions=(
        "Logs doses and notes to the user's Substance Journal. Always read the read-back to the user and "
        "only confirm after a clear yes. The first time you use this server with someone, tell them the "
        "request format by calling how_to_ask and reading it out. Never say a dose is safe or advise on amounts."
    ),
)

FL_OZ_ML = 29.5735
ETHANOL_G_PER_FL_OZ = 23.36  # matches the app (Alcohol Tracker's density)
STANDARD_DRINK_G = 0.6 * ETHANOL_G_PER_FL_OZ
SHOT_OZ = 1.5

# What people say, mapped to the route names the app uses.
ROUTE_WORDS = {
    "oral": "oral", "orally": "oral", "swallowed": "oral", "swallow": "oral", "by mouth": "oral", "pill": "oral",
    "eaten": "oral", "ate": "oral", "drank": "oral", "drink": "oral", "capsule": "oral", "edible": "oral",
    "sublingual": "sublingual", "sublingually": "sublingual", "under the tongue": "sublingual", "under tongue": "sublingual",
    "buccal": "buccal", "cheek": "buccal",
    "smoked": "smoked", "smoke": "smoked", "smoking": "smoked", "joint": "smoked",
    "inhaled": "inhaled", "vaped": "inhaled", "vape": "inhaled", "vaporized": "inhaled", "vaporised": "inhaled", "dabbed": "inhaled",
    "insufflated": "insufflated", "snorted": "insufflated", "snort": "insufflated", "nasal": "insufflated", "intranasal": "insufflated",
    "rectal": "rectal", "plugged": "rectal",
    "intravenous": "intravenous", "iv": "intravenous", "intramuscular": "intramuscular", "im": "intramuscular",
    "transdermal": "transdermal", "patch": "transdermal",
}
UNIT_WORDS = {
    "mg": "mg", "milligram": "mg", "milligrams": "mg",
    "g": "g", "gram": "g", "grams": "g",
    "ug": "µg", "µg": "µg", "mcg": "µg", "microgram": "µg", "micrograms": "µg",
    "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
}
TO_MG = {"mg": 1.0, "g": 1000.0, "µg": 0.001}


def data_dir() -> Path:
    env = os.environ.get("SUBSTANCE_JOURNAL_DATA")
    return Path(env) if env else Path(__file__).resolve().parents[2] / "app" / "assets" / "data"


_catalog: list[dict] | None = None


def catalog() -> list[dict]:
    """The reference compounds the app ships with (audited ones and the wider list)."""
    global _catalog
    if _catalog is None:
        out: list[dict] = []
        for name in ("substances.json", "substances_extra.json"):
            p = data_dir() / name
            if p.exists():
                out += json.loads(p.read_text(encoding="utf-8"))
        _catalog = out
    return _catalog


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9µ ]+", "", s.lower().replace("_", " ")).strip()


def resolve_substance(text: str) -> dict:
    t = _norm(text)
    if not t:
        raise ValueError("Which substance? Say its name, for example 'LSD' or 'cannabis'.")
    subs = catalog()
    exact = [s for s in subs if t in {_norm(s["key"]), _norm(s["name"]), *(_norm(c) for c in s.get("common_names", []))}]
    if len(exact) >= 1:
        return exact[0]
    hits = [s for s in subs if t in _norm(s["name"]) or any(t in _norm(c) for c in s.get("common_names", []))]
    if len(hits) == 1:
        return hits[0]
    if hits:
        raise ValueError("More than one match: " + ", ".join(h["name"] for h in hits[:6]) + ". Which one?")
    raise ValueError(f"I do not know '{text}'. Say the compound's usual name, or add it in the app first.")


def resolve_route(sub: dict, route: str) -> dict:
    roas = sub.get("roas", [])
    if not roas:
        raise ValueError(f"{sub['name']} has no routes in the app's reference.")
    names = [r["route"] for r in roas]
    if not route.strip():
        if len(roas) == 1:
            return roas[0]
        raise ValueError(f"How was the {sub['name']} taken? Options: {', '.join(names)}.")
    want = ROUTE_WORDS.get(_norm(route), _norm(route))
    for r in roas:
        if r["route"] == want:
            return r
    raise ValueError(f"{sub['name']} is not listed for '{route}' in the app. Options: {', '.join(names)}.")


def convert_dose(dose: float, unit: str, roa: dict) -> tuple[float, str]:
    """The dose in the route's own unit (so it lines up with the reference ranges)."""
    target = roa.get("unit", "")
    given = UNIT_WORDS.get(_norm(unit)) if unit.strip() else target
    if given is None:
        raise ValueError(f"I do not know the unit '{unit}'. Use mg, g, micrograms or ml.")
    if given == target or not target:
        return dose, given or target
    if given in TO_MG and target in TO_MG:
        return dose * TO_MG[given] / TO_MG[target], target
    raise ValueError(f"{roa['route']} doses for this are in {target}, not {unit}.")


def dose_warning(roa: dict, dose: float) -> str:
    heavy = roa.get("dose_heavy")
    strong = roa.get("dose_strong") or {}
    top = strong.get("max") if isinstance(strong, dict) else None
    if heavy and dose >= heavy:
        return f" That is at or above the heavy dose in the reference ({heavy:g} {roa.get('unit', '')}). Check the number and unit."
    if top and dose > top:
        return f" That is above the strong range in the reference (up to {top:g} {roa.get('unit', '')}). Check the number and unit."
    return ""


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
    if not rows:
        raise ValueError("The journal has no people yet. Open the app once first.")
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


def _intro(con) -> str:
    """The request format, once: the first time anything is used, and never again unprompted."""
    row = con.execute("select value from settings where key='mcpIntroShown'").fetchone()
    if row:
        return ""
    con.execute(
        "insert or replace into settings(key,value,hlc,shared) values('mcpIntroShown','1',?,0)", (hlc(),)
    )
    con.commit()
    return "\n\nFirst time here, so: " + HOW_TO_ASK


def _minutes(minutes_ago: int) -> datetime:
    if minutes_ago < 0:
        raise ValueError("minutes_ago cannot be negative.")
    return datetime.now() - timedelta(minutes=minutes_ago)


@mcp.tool()
def how_to_ask() -> str:
    """How the user should phrase requests (doses, drinks, presets, notes, undo, reports). Read this out
    to the user the first time they use voice logging."""
    return HOW_TO_ASK


@mcp.tool()
def list_people() -> str:
    """Names of the people tracked in the journal."""
    with connect() as con:
        return ", ".join(r["name"] for r in con.execute("select name from people where deleted=0"))


@mcp.tool()
def list_presets() -> str:
    """Presets that can be logged by name: drinks, and any dose preset saved in the app."""
    with connect() as con:
        rows = con.execute("select name, substance_key, amount, unit from presets where deleted=0 order by substance_key, name").fetchall()
    return "\n".join(f"{r['name']} ({r['substance_key']}, {r['amount']:g} {r['unit']})" for r in rows) or "No presets."


def find_preset(con, text: str, alcohol: bool | None = None):
    sql = "select * from presets where deleted=0"
    if alcohol is True:
        sql += " and substance_key='alcohol'"
    elif alcohol is False:
        sql += " and substance_key!='alcohol'"
    rows = con.execute(sql).fetchall()
    t = text.lower().strip()
    exact = [r for r in rows if r["name"].lower() == t]
    hits = exact or [r for r in rows if t in r["name"].lower()]
    if not hits:
        raise ValueError(f"No preset matching '{text}'. Try list_presets.")
    if len(hits) > 1 and not exact:
        raise ValueError("More than one match: " + ", ".join(r["name"] for r in hits))
    return hits[0]


def _experience_near(con, person, at):
    """The person's experience within 12 hours of `at`, as the app joins them."""
    lo, hi = to_s(at - timedelta(hours=12)), to_s(at + timedelta(hours=12))
    return con.execute(
        "select experience_id from ingestions where person_id=? and deleted=0 and time between ? and ? order by abs(time-?) limit 1",
        (person["id"], lo, hi, to_s(at)),
    ).fetchone()


def _insert(con, person, at, substance, route, dose, unit, details, notes=""):
    near = _experience_near(con, person, at)
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
    """Log a drink preset (for example "beer" or "shot of vodka"). First call with confirmed=false to get a
    read-back, read it to the user, and only call again with confirmed=true after they say yes."""
    if count < 1 or count > 20:
        return "How many drinks? Give a number from 1 to 20."
    with connect() as con:
        p = find_preset(con, preset, alcohol=True)
        who = person_row(con, person)
        abv = json.loads(p["details_json"]).get("abv", 0)
        at = _minutes(minutes_ago)
        g = grams(p["amount"], p["unit"], abv)
        std = g / STANDARD_DRINK_G
        line = f"{count} x {p['name']} for {who['name']} at {at:%I:%M %p} ({std * count:.1f} standard drinks)"
        if not confirmed:
            return f"Ready to log {line}. Ask the user to confirm, then call again with confirmed=true."
        for _ in range(count):
            _insert(con, who, at, "alcohol", "oral", g, "g",
                    {"drink": p["name"], "volume": p["amount"], "volumeUnit": p["unit"], "abv": abv})
        con.commit()
        return f"Logged {line}." + _intro(con)


@mcp.tool()
def log_dose(substance: str, dose: float, unit: str = "", route: str = "", person: str | None = None,
             minutes_ago: int = 0, notes: str = "", confirmed: bool = False) -> str:
    """Log a dose of any compound, for example substance 'LSD', dose 100, unit 'micrograms', route 'sublingual'.
    The name, unit and route are matched to the app's reference (so 'molly', 'mcg' and 'under the tongue' work).
    Same two-step confirmation as log_drink: read the read-back to the user and wait for a yes."""
    if dose <= 0:
        return "The dose must be more than zero."
    sub = resolve_substance(substance)
    if sub["key"] == "alcohol":
        return "For alcohol, use log_drink with a preset (for example 'beer'). Use list_presets to see them."
    roa = resolve_route(sub, route)
    value, unit_used = convert_dose(dose, unit, roa)
    with connect() as con:
        who = person_row(con, person)
        at = _minutes(minutes_ago)
        line = f"{value:g} {unit_used} of {sub['name']} ({roa['route']}) for {who['name']} at {at:%I:%M %p}"
        warning = dose_warning(roa, value)
        if not confirmed:
            return f"Ready to log {line}.{warning} Ask the user to confirm, then call again with confirmed=true."
        _insert(con, who, at, sub["key"], roa["route"], value, unit_used, {}, notes.strip())
        con.commit()
        return f"Logged {line}." + _intro(con)


@mcp.tool()
def log_preset(preset: str, person: str | None = None, minutes_ago: int = 0, confirmed: bool = False) -> str:
    """Log a dose preset saved in the app (not a drink), by name, for example 'my usual tab'.
    Same two-step confirmation: read-back first, then confirmed=true after a yes."""
    with connect() as con:
        p = find_preset(con, preset, alcohol=False)
        who = person_row(con, person)
        at = _minutes(minutes_ago)
        line = f"{p['name']} ({p['amount']:g} {p['unit']} of {p['substance_key']}, {p['route']}) for {who['name']} at {at:%I:%M %p}"
        if not confirmed:
            return f"Ready to log {line}. Ask the user to confirm, then call again with confirmed=true."
        _insert(con, who, at, p["substance_key"], p["route"], p["amount"], p["unit"], {"preset": p["name"]})
        con.commit()
        return f"Logged {line}." + _intro(con)


@mcp.tool()
def add_note(text: str, minutes_ago: int = 0, person: str | None = None, confirmed: bool = False) -> str:
    """Add a timed note (for example 'feeling anxious', 'drank water', 'peaking') to the person's current
    session, so it shows on the timeline. Two steps: read-back first, then confirmed=true after a yes."""
    text = text.strip()
    if not text:
        return "What should the note say?"
    if len(text) > 500:
        return "That note is too long; keep it under 500 characters."
    with connect() as con:
        who = person_row(con, person)
        at = _minutes(minutes_ago)
        # Notes belong to a session: the one within the last 12 hours, never a brand new empty one.
        near = _experience_near(con, who, at)
        if near is None:
            return "There is no session in the last 12 hours to put a note on. Log a dose first."
        line = f"note \"{text}\" for {who['name']} at {at:%I:%M %p}"
        if not confirmed:
            return f"Ready to add {line}. Ask the user to confirm, then call again with confirmed=true."
        con.execute(
            "insert into timed_notes(id,hlc,deleted,experience_id,time,note,show_on_timeline) values(?,?,0,?,?,?,1)",
            (str(uuid.uuid4()), hlc(), near["experience_id"], to_s(at), text),
        )
        con.commit()
        return f"Added {line}." + _intro(con)


@mcp.tool()
def undo_last(count: int = 1, what: str = "dose") -> str:
    """Remove the most recent entries this server added: what='dose' (default) or what='note'.
    It never touches anything made in the app."""
    count = max(1, min(count, 20))
    with connect() as con:
        if what.lower().startswith("note"):
            rows = con.execute(
                "select id from timed_notes where deleted=0 and hlc like '%-mcp' order by time desc limit ?", (count,)
            ).fetchall()
            for r in rows:
                con.execute("update timed_notes set deleted=1, hlc=? where id=?", (hlc(), r["id"]))
            con.commit()
            return f"Removed {len(rows)} note(s)." if rows else "No notes of mine to undo."
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


@mcp.tool()
def recent(limit: int = 5, person: str | None = None) -> str:
    """The last few doses and notes, newest first, so the user can check what was saved."""
    limit = max(1, min(limit, 20))
    with connect() as con:
        who = person_row(con, person)
        doses = con.execute(
            "select time, substance_key, route, dose, unit from ingestions where deleted=0 and person_id=? order by time desc limit ?",
            (who["id"], limit)).fetchall()
        notes = con.execute(
            "select n.time, n.note from timed_notes n join experiences e on e.id=n.experience_id "
            "where n.deleted=0 and e.person_id=? order by n.time desc limit ?", (who["id"], limit)).fetchall()
    items = [(r["time"], f"{r['substance_key']} {r['dose'] if r['dose'] is not None else '?':g} {r['unit'] or ''} ({r['route']})".replace("  ", " "))
             if r["dose"] is not None else (r["time"], f"{r['substance_key']} ({r['route']}, no dose)") for r in doses]
    items += [(r["time"], f"note: {r['note']}") for r in notes]
    items.sort(reverse=True)
    if not items:
        return f"{who['name']}: nothing logged yet."
    return f"{who['name']}, latest first:\n" + "\n".join(f"{from_s(t):%b %d %I:%M %p}  {text}" for t, text in items[:limit])


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
