"""Substance Journal MCP server: voice/AI logging, notes, status and reports for the Flutter app's database.

Tools an AI gets:
  read-only   how_to_ask, current_status, recent, report, list_people, list_presets,
              prepare_dose, prepare_drink, prepare_preset, prepare_note (these write nothing)
  writes      confirm_log (adds what was prepared, after the person's clear yes),
              undo_last (removes only the assistant's own entries from the last few minutes, if untouched)
There is no tool that edits or deletes anything else. See sj_guard.py for how that is enforced.

It works through the open app's voice assistant link when the person has switched it on (Settings > Voice assistant), which is
how it reaches an encrypted journal; otherwise directly on an unencrypted journal file.
"""
from __future__ import annotations

import functools
import json
import os
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from mcp.server.mcpserver import MCPServer as FastMCP  # mcp 2.x
except ImportError:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x
from mcp.types import ToolAnnotations

import sj_guard
from sj_guard import Guard, JournalError, from_s, to_s

HOW_TO_ASK = """How to ask (say it like this):
- A dose:  "Log 100 micrograms of LSD, under the tongue."   -> substance, amount, unit, and how it was taken.
- A drink: "Log a beer."  or  "Log two beers."               -> a drink preset by name, and how many.
- A saved preset: "Log my usual tab."                       -> any preset you saved in the app, by name.
- A past time: add "20 minutes ago" or "an hour ago". Without it, the time is now.
- Someone else: add "for Alex" (otherwise it is the default person).
- A note:  "Add a note: feeling anxious, drank some water." -> goes on the timeline of your current session.
- Undo:    "Undo that."  (only what the assistant just added, in the last few minutes; never entries you made in the app).
- Check:   "What's active right now?", "What did I log today?" or "Report for this week."
I save it right away and tell you exactly what I saved, so you can say "undo that". The one exception: a dose above the reference's strong
range (or a note that sounds like an emergency) is read back first and saved only after you say yes."""

INSTRUCTIONS = (
    "Logs doses, drinks and notes to the user's Substance Journal and reads it back. When the person asks to log something, call "
    "log_dose, log_drink, log_preset or log_note: it saves straight away, with no yes/no step. Then SAY what was saved (the "
    "'told_to_user' text) and mention they can say 'undo that'. If the result has held_for_yes (a dose above the reference's "
    "strong range, or a note that sounds like an emergency) it saved NOTHING: read the read_back_to_user and warnings aloud, ask "
    "yes or no, and only after their answer call confirm_log with the proposal_id and their exact words; never confirm on your own "
    "and never invent their reply. "
    "Undo (undo_last) only when the person asks. The first time you use this server with someone, call how_to_ask and read it out. "
    "Times and phases are estimates from reference data, not measurements: say 'estimated'. Never say a dose, mix or plan "
    "is safe and never recommend an amount. If someone has severe symptoms (trouble breathing, chest pain, seizure, "
    "confusion, very high temperature, cannot be woken), tell them to get urgent medical help now (call emergency services) "
    "instead of logging or analysing."
)

mcp = FastMCP("substance-journal", instructions=INSTRUCTIONS)

READ = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)
PREPARE = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=False, openWorldHint=False)
ADD = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=False)
REMOVE = ToolAnnotations(readOnlyHint=False, destructiveHint=True, idempotentHint=False, openWorldHint=False)

FL_OZ_ML = 29.5735
ETHANOL_G_PER_FL_OZ = 23.36  # matches the app (Alcohol Tracker's density)
STANDARD_DRINK_G = 0.6 * ETHANOL_G_PER_FL_OZ
SHOT_OZ = 1.5
ALCOHOL_CLEARED_PER_HOUR = 1.0  # standard drinks; a rough average used only for the "estimated" status line

URGENT = ("If anyone has trouble breathing, chest pain, a seizure, confusion, a very high temperature, or cannot be woken, "
          "get urgent medical help now: call emergency services.")
_URGENT_WORDS = re.compile(
    r"\b(can'?t breathe|cannot breathe|trouble breathing|not breathing|struggling to breathe|chest pain|seiz|convuls|"
    r"unresponsive|won'?t wake|can'?t wake|cannot wake|passed out|unconscious|overheat|very hot|collapsed|blue lips|overdos)",
    re.I,
)

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
ROUTE_SPOKEN = {
    "oral": "by mouth", "sublingual": "under the tongue", "buccal": "in the cheek", "smoked": "smoked", "inhaled": "inhaled",
    "insufflated": "snorted", "rectal": "rectally", "intravenous": "injected (IV)", "intramuscular": "injected (IM)",
    "transdermal": "on the skin",
}
UNIT_WORDS = {
    "mg": "mg", "milligram": "mg", "milligrams": "mg",
    "g": "g", "gram": "g", "grams": "g",
    "ug": "µg", "µg": "µg", "mcg": "µg", "microgram": "µg", "micrograms": "µg",
    "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
}
UNIT_SPOKEN = {"µg": "micrograms", "mg": "milligrams", "g": "grams", "ml": "millilitres"}
TO_MG = {"mg": 1.0, "g": 1000.0, "µg": 0.001}


# ---- reference data and parsing -----------------------------------------------------------------------------------
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
        _load_dose_audit(out)
        _catalog = out
    return _catalog


# id(route dict) -> (audited High max, audited Heavy) from dose_audit.json, used only by dose_warning.
_audited_edges: dict[int, tuple[float | None, float | None]] = {}


def _load_dose_audit(subs: list[dict]) -> None:
    """The app's cross-checked dose bands (dose_audit.json). Missing or unreadable: the catalog's bands stand."""
    _audited_edges.clear()
    try:
        audit = json.loads((data_dir() / "dose_audit.json").read_text(encoding="utf-8")).get("substances")
    except (OSError, ValueError, AttributeError):
        return
    if not isinstance(audit, dict):
        return

    def unit(u):
        return str(u or "").strip().replace("μ", "µ").replace("mcg", "µg").replace("ug", "µg")

    def num(v):
        return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0 else None

    for s in subs:
        routes = audit.get(s.get("key"))
        if not isinstance(routes, dict):
            continue
        for r in s.get("roas", []):
            a = routes.get(r.get("route"))
            if not isinstance(a, dict) or unit(a.get("unit")) != unit(r.get("unit")):
                continue
            high = a.get("high")
            _audited_edges[id(r)] = (num(high.get("max")) if isinstance(high, dict) else None, num(a.get("heavy")))


def by_key(key: str) -> dict | None:
    return next((s for s in catalog() if s["key"] == key), None)


def display_name(key: str) -> str:
    s = by_key(key)
    return s["name"] if s else key.replace("_", " ")


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9µ ]+", "", s.lower().replace("_", " ")).strip()


def resolve_substance(text: str) -> dict:
    t = _norm(text)
    if not t:
        raise ValueError("Which substance? Say its name, for example 'LSD' or 'cannabis'.")
    subs = catalog()
    exact = [s for s in subs if t in {_norm(s["key"]), _norm(s["name"]), *(_norm(c) for c in s.get("common_names", []))}]
    if exact:
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
    audited = _audited_edges.get(id(roa))
    if audited:  # the cross-checked High and Heavy edges win; a gap in them falls back to the catalog
        top = audited[0] if audited[0] is not None else top
        heavy = audited[1] if audited[1] is not None else heavy
    unit = spoken_unit(roa.get("unit", ""))
    if heavy and dose >= heavy:
        return f"That is at or above the heavy dose in the reference ({heavy:g} {unit}). Check the number and unit."
    if top and dose > top:
        return f"That is above the strong range in the reference (up to {top:g} {unit}). Check the number and unit."
    return ""


def spoken_unit(unit: str) -> str:
    return UNIT_SPOKEN.get(unit or "", unit or "")


def spoken_amount(dose, unit) -> str:
    if dose is None:
        return "an unrecorded amount"
    return f"{dose:g} {spoken_unit(unit)}".strip()


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


_FILLER = {"a", "an", "the", "of", "some", "my", "please", "one", "usual"}
_NUMBER_WORDS = {"two", "three", "four", "five", "six"}


def _words(text: str) -> list[str]:
    out = []
    for w in re.findall(r"[a-z]+|\d+(?:\.\d+)?", text.lower()):
        out.append(w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") else w)
    return out


def find_preset(rows, text: str):
    """Match what was said to exactly one preset: exact name, else every spoken word in the name (plurals and 'a', 'my'
    ignored), preferring names that start with it. More than one equally good match is a question, not a guess."""
    t = text.strip().lower()
    if not t:
        raise ValueError("Which preset? Try list_presets.")
    exact = [r for r in rows if r["name"].lower() == t]
    if exact:
        return exact[0]
    q = [w for w in _words(t) if w not in _FILLER]
    if len(q) > 1:
        q = [w for w in q if w not in _NUMBER_WORDS]
    q = q or _words(t)
    scored = []
    for r in rows:
        words = _words(r["name"])
        if q and all(w in words for w in q):
            starts = words[: len(q)] == q
            scored.append(((1 if starts else 0), -len(words), r))
    if not scored:
        raise ValueError(f"No preset matching '{text}'. Presets: {', '.join(r['name'] for r in rows) or 'none'}.")
    scored.sort(key=lambda s: (s[0], s[1]), reverse=True)
    best = [s for s in scored if s[:2] == scored[0][:2]]
    if len(best) > 1:
        raise ValueError("More than one match: " + ", ".join(s[2]["name"] for s in best) + ". Which one?")
    return scored[0][2]


# ---- time words --------------------------------------------------------------------------------------------------
def clock(dt: datetime) -> str:
    return dt.strftime("%I:%M %p").lstrip("0")


def day_word(dt: datetime, now: datetime) -> str:
    d = (now.date() - dt.date()).days
    if d == 0:
        return "today"
    if d == 1:
        return "yesterday"
    if 1 < d < 7:
        return dt.strftime("%A")
    return dt.strftime("%b %d").replace(" 0", " ")


def when_words(at: datetime, now: datetime) -> str:
    if abs((now - at).total_seconds()) < 90:
        return "now"
    return f"at {clock(at)}" + ("" if at.date() == now.date() else f" {day_word(at, now)}")


def ago(m: float) -> str:
    return "just now" if m < 1 else f"{_minutes(m)} ago"


def _minutes(m: float) -> str:
    m = int(round(m))
    if m < 60:
        return f"{m} minute{'s' if m != 1 else ''}"
    h, r = divmod(m, 60)
    return f"{h} hour{'s' if h != 1 else ''}" + (f" {r} min" if r else "")


# ---- the guard ---------------------------------------------------------------------------------------------------
_guard: Guard | None = None


def guard() -> Guard:
    global _guard
    if _guard is None:
        g = Guard()
        try:
            g.backup("daily")
        except Exception:  # a failed daily backup must not stop reads
            pass
        _guard = g
    return _guard


def _json(obj) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False, default=str)


def _safe(fn):
    @functools.wraps(fn)
    def wrapper(*a, **k):
        try:
            return fn(*a, **k)
        except (JournalError, ValueError) as e:
            return f"Not done: {e}"

    return wrapper


def _prepared(p) -> str:
    return _json({
        "proposal_id": p.id,
        "read_back_to_user": f"{p.readback}?",
        "warnings_to_say_aloud": p.warnings,
        "next": "Read this to the person and ask yes or no. Call confirm_log with their exact answer only after they reply.",
    })


# ---- tools: reading ----------------------------------------------------------------------------------------------
@mcp.tool(annotations=READ)
def how_to_ask() -> str:
    """How the person should phrase requests (doses, drinks, presets, notes, undo, status, reports), and which journal
    file is in use. Read the request format out the first time someone uses voice logging."""
    try:
        where = guard().backend().describe()
    except JournalError as e:
        where = f"Journal not available: {e}"
    lim = sj_guard.Limits() if _guard is None else _guard.limits()
    return (f"{HOW_TO_ASK}\n\n{where}\nLimits: entries up to {lim.max_backdate_hours:g} hours back and never in the future, at most "
            f"{lim.max_entries_per_hour} assistant entries an hour, {lim.max_drinks_per_log} drinks per log, undo within "
            f"{lim.undo_window_minutes} minutes.")


@mcp.tool(annotations=READ)
@_safe
def list_people() -> str:
    """Names of the people tracked in the journal (the first is the default)."""
    rows = sorted(guard().backend().people(), key=lambda r: (not r["is_default"], r["name"]))
    return ", ".join(r["name"] for r in rows) or "No people yet."


@mcp.tool(annotations=READ)
@_safe
def list_presets() -> str:
    """Presets that can be logged by name: drinks, and any dose preset saved in the app."""
    b = guard().backend()
    rows = sorted([*b.presets(drinks=True), *b.presets(drinks=False)], key=lambda r: (r["substance_key"], r["name"]))
    return "\n".join(f"{r['name']} ({display_name(r['substance_key'])}, {r['amount']:g} {r['unit']})" for r in rows) or "No presets."


def _span_minutes(d: dict | None) -> tuple[float, float] | None:
    if not d:
        return None
    k = {"seconds": 1 / 60, "minutes": 1, "hours": 60, "days": 1440}.get(d.get("units", "minutes"), 1)
    return d["min"] * k, d["max"] * k


def phase_of(roa: dict | None, elapsed_min: float) -> tuple[str, float | None, float | None] | None:
    """(estimated phase, total min, total max) from the reference durations' midpoints, or None when over."""
    dur = (roa or {}).get("duration") or {}
    parts = {k: _span_minutes(dur.get(k)) for k in ("onset", "comeup", "peak", "offset", "total", "afterglow")}
    mid = {k: (v[0] + v[1]) / 2 for k, v in parts.items() if v}
    if not mid:
        return ("no duration data in the reference", None, None)
    total = parts.get("total")
    t1 = mid.get("onset", 0)
    t2 = t1 + mid.get("comeup", 0)
    t3 = t2 + mid.get("peak", 0)
    t4 = t3 + mid["offset"] if "offset" in mid else mid.get("total", t3)
    t5 = t4 + mid.get("afterglow", 0)
    lo, hi = (total if total else (t4, t4))
    if elapsed_min < t1:
        return ("probably not felt yet", lo, hi)
    if elapsed_min < t2:
        return ("coming up", lo, hi)
    if elapsed_min < t3:
        return ("around the peak", lo, hi)
    if elapsed_min < t4:
        return ("coming down", lo, hi)
    if elapsed_min < t5:
        return ("in the after-effects", lo, hi)
    return None


def _alcohol_line(drinks: list[tuple[datetime, float]], now: datetime) -> str:
    """Standard drinks today and a rough 'still being processed' estimate from (time, grams) pairs, oldest first."""
    if not drinks:
        return ""
    remaining, last_t = 0.0, None
    for t, grams_ in drinks:
        if last_t is not None:
            remaining = max(0.0, remaining - (t - last_t).total_seconds() / 3600 * ALCOHOL_CLEARED_PER_HOUR)
        remaining += grams_ / STANDARD_DRINK_G
        last_t = t
    remaining = max(0.0, remaining - (now - last_t).total_seconds() / 3600 * ALCOHOL_CLEARED_PER_HOUR)
    today = sum(g for t, g in drinks if t.date() == now.date()) / STANDARD_DRINK_G
    if remaining > 0.05:
        done_at = now + timedelta(hours=remaining / ALCOHOL_CLEARED_PER_HOUR)
        return (f"Alcohol: about {remaining:.1f} standard drinks estimated still being processed, last drink {ago((now - last_t).total_seconds() / 60)}; "
                f"rough estimate it is processed by about {clock(done_at)} (not a measure of whether it is safe to drive). {today:.1f} standard drinks today.")
    if today > 0:
        return f"Alcohol: {today:.1f} standard drinks today; by a rough estimate nothing is still being processed."
    return ""


def _status_from_link(active: dict, who: dict, now: datetime) -> str:
    """current_status from the app's own Active now, through the link."""
    lines: list[str] = []
    drinks = sorted((datetime.fromisoformat(d["at"]), float(d.get("grams") or 0)) for d in active.get("alcohol", {}).get("drinks_last_24h", []))
    line = _alcohol_line(drinks, now)
    if line:
        lines.append(line)
    for x in active.get("substances", []):
        last = datetime.fromisoformat(x["last_at"])
        elapsed = (now - last).total_seconds() / 60
        count = f" ({x['doses']} doses still working)" if x.get("doses", 1) > 1 else ""
        line = (f"{x.get('name') or display_name(x['substance'])}, {ROUTE_SPOKEN.get(x['route'], x['route'])}: last "
                f"{spoken_amount(x.get('last_dose'), x.get('unit'))} {ago(elapsed)}, estimated {x.get('phase_label', '').lower()}")
        end, linger = x.get("main_effects_end_at"), x.get("linger_ends_at")
        if end:
            line += f"; the main effects should be over by about {clock(datetime.fromisoformat(end))}"
            if linger and linger != end:
                line += f", lighter after-effects until about {clock(datetime.fromisoformat(linger))}"
        lines.append(line + count + ".")
    if not lines:
        return f"{who['name']}: nothing active by the reference durations (nothing logged in the last 2 days is still within its usual duration)."
    return (f"{who['name']}, right now (estimated from the reference durations, not a measurement; everyone differs):\n- "
            + "\n- ".join(lines))


@mcp.tool(annotations=READ)
@_safe
def current_status(person: str = "") -> str:
    """What is active right now for the person: each compound taken in the last 2 days that is still within its usual
    duration, with an ESTIMATED phase (coming up, around the peak, coming down, after-effects) from the reference
    durations, and alcohol in standard drinks with a rough estimate of how much is still being processed."""
    g = guard()
    b = g.backend()
    now = g.now()
    who = g.person(person or None, b)
    if isinstance(b, sj_guard.LinkBackend):
        return _status_from_link(b.active(who), who, now)
    rows = g.query(
        "select substance_key, route, time, dose, unit from ingestions where deleted=0 and person_id=? and time>=? and time<=? order by time",
        (who["id"], to_s(now - timedelta(hours=48)), to_s(now) + 60),
    )
    lines: list[str] = []
    line = _alcohol_line([(from_s(r["time"]), r["dose"] or 0) for r in rows if r["substance_key"] == "alcohol"], now)
    if line:
        lines.append(line)
    latest: dict[tuple, list] = {}
    for r in rows:
        if r["substance_key"] != "alcohol":
            latest.setdefault((r["substance_key"], r["route"]), []).append(r)
    for (key, route), rs in latest.items():
        last = rs[-1]
        at = from_s(last["time"])
        elapsed = (now - at).total_seconds() / 60
        sub = by_key(key)
        roa = next((x for x in (sub or {}).get("roas", []) if x["route"] == route), None)
        ph = phase_of(roa, elapsed)
        if ph is None:
            continue
        phase, lo, hi = ph
        count = f" ({len(rs)} doses in the last 2 days)" if len(rs) > 1 else ""
        line = f"{display_name(key)}, {ROUTE_SPOKEN.get(route, route)}: last {spoken_amount(last['dose'], last['unit'])} {ago(elapsed)}, estimated {phase}"
        if lo is not None and hi is not None:
            line += f"; usually lasts {lo / 60:g} to {hi / 60:g} hours, so it should fade between about {clock(at + timedelta(minutes=lo))} and {clock(at + timedelta(minutes=hi))}"
        lines.append(line + count + ".")
    if not lines:
        return f"{who['name']}: nothing active by the reference durations (nothing logged in the last 2 days is still within its usual duration)."
    return (f"{who['name']}, right now (estimated from the reference durations, not a measurement; everyone differs):\n- "
            + "\n- ".join(lines))


def _describe(r, ai: set[str], now: datetime, with_day: bool = True) -> str:
    at = from_s(r["time"])
    head = f"{day_word(at, now).capitalize()} {clock(at)}" if with_day else clock(at)
    if r["kind"] == "note":
        text = f"note, {r['note']}"
    elif r["substance_key"] == "alcohol":
        try:
            drink = json.loads(r["details_json"] or "{}").get("drink")
        except ValueError:
            drink = None
        text = f"{drink or 'a drink'}, about {(r['dose'] or 0) / STANDARD_DRINK_G:.1f} standard drinks"
    else:
        text = f"{spoken_amount(r['dose'], r['unit'])} of {display_name(r['substance_key'])}, {ROUTE_SPOKEN.get(r['route'], r['route'])}"
    mine = " (added by the assistant)" if r["id"] in ai else ""
    return f"{head}: {text}{mine}."


@mcp.tool(annotations=READ)
@_safe
def recent(limit: int = 5, person: str = "") -> str:
    """The last few doses, drinks and notes, newest first, as short sentences that read well aloud. Entries the assistant
    added are marked, so the person can check what was saved."""
    g = guard()
    b = g.backend()
    limit = max(1, min(int(limit), 20))
    who = g.person(person or None, b)
    items, ai = b.recent(who, limit)
    if not items:
        return f"{who['name']}: nothing logged yet."
    now = g.now()
    return f"{who['name']}, latest first:\n" + "\n".join(_describe(r, ai, now) for r in items)


def span(period: str, start, end, now: datetime):
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    period = (period or "week").lower().strip()
    if period == "custom" or start:
        if not start:
            raise ValueError("For a custom report give start (and optionally end) as YYYY-MM-DD.")
        s = datetime.fromisoformat(start)
        e = datetime.fromisoformat(end) + timedelta(days=1) if end else now + timedelta(seconds=1)
        return s, e, f"from {s:%b %d} to {(e - timedelta(seconds=1)):%b %d}"
    if period == "yesterday":
        return midnight - timedelta(days=1), midnight, "yesterday"
    days = {"today": 0, "week": 6, "month": 29, "year": 364}.get(period)
    if days is None:
        raise ValueError("period must be today, yesterday, week, month, year or custom")
    label = {"today": "today", "week": "in the last 7 days", "month": "in the last 30 days", "year": "in the last year"}[period]
    return midnight - timedelta(days=days), now + timedelta(seconds=1), label


def _times(n: int) -> str:
    return {1: "once", 2: "twice"}.get(n, f"{n} times")


@mcp.tool(annotations=READ)
@_safe
def report(period: str = "week", person: str = "", start: str = "", end: str = "") -> str:
    """Report of what was taken: period today|yesterday|week|month|year|custom (custom uses start/end as YYYY-MM-DD).
    The first line is one sentence ready to read aloud; offer the details after. Alcohol is in standard drinks,
    everything else as doses and total amount per compound."""
    g = guard()
    b = g.backend()
    if isinstance(b, sj_guard.LinkBackend):
        raise JournalError("Reports are not available through the app's voice assistant link, which cannot read the whole journal. "
                           "Use Insights in the app, or ask what is active now or what was logged recently.")
    now = g.now()
    s, e, label = span(period, start or None, end or None, now)
    who = g.person(person or None, b)
    rows = g.query(
        "select substance_key, route, time, dose, unit from ingestions where deleted=0 and person_id=? and time>=? and time<? order by time",
        (who["id"], to_s(s), to_s(e)))
    last_day = e - timedelta(seconds=1)
    if not rows:
        return f"Spoken summary: {'You' if who['is_default'] else who['name']} logged nothing {label}."
    out: list[str] = []
    spoken: list[str] = []
    alc = [r for r in rows if r["substance_key"] == "alcohol"]
    if alc:
        days: dict[str, float] = {}
        for r in alc:
            d = from_s(r["time"]).strftime("%Y-%m-%d")
            days[d] = days.get(d, 0) + (r["dose"] or 0) / STANDARD_DRINK_G
        total = sum(days.values())
        busiest = max(days, key=days.get)
        spoken.append(f"{total:.1f} standard drinks over {len(days)} day{'s' if len(days) != 1 else ''}")
        out.append(f"Alcohol: {total:.1f} standard drinks over {len(days)} day(s), {total / len(days):.1f} per drinking day, "
                   f"most on {busiest} ({days[busiest]:.1f}). Last drink {from_s(alc[-1]['time']):%b %d} {clock(from_s(alc[-1]['time']))}.")
        if len(days) <= 10:
            out.append("  " + "; ".join(f"{d[5:]}: {v:.1f}" for d, v in sorted(days.items())))
    others: dict[tuple, list] = {}
    for r in rows:
        if r["substance_key"] != "alcohol":
            others.setdefault((r["substance_key"], r["unit"] or ""), []).append(r)
    for (sub, unit), rs in sorted(others.items(), key=lambda kv: -len(kv[1])):
        total = sum(r["dose"] or 0 for r in rs)
        name = display_name(sub)
        spoken.append(f"{name} {_times(len(rs))}" + (f" ({total:g} {spoken_unit(unit)} in all)" if total else ""))
        last = from_s(rs[-1]["time"])
        out.append(f"{name}: {len(rs)} dose(s), {total:g} {unit} total, last {last:%b %d} {clock(last)}.")
    if len(spoken) > 1:
        said = ", ".join(spoken[:-1]) + " and " + spoken[-1]
    else:
        said = spoken[0]
    subject = "you" if who["is_default"] else who["name"]
    head = f"Spoken summary: {label[0].upper() + label[1:]}, {subject} logged {said}."
    return head + f"\n\nDetails, {s:%b %d} to {last_day:%b %d}:\n" + "\n".join(out)


# ---- builders (shared by prepare_* and log_*); prepare_* are plain functions, NOT tools: a small model picked them instead of log_* and asked for a yes ----------------------------------------------------------------------
def _build_dose(substance: str, dose: float, unit: str = "", route: str = "", person: str = "", minutes_ago: float = 0, notes: str = "") -> str:
    """Step 1 of logging a dose of any compound, for example substance 'LSD', dose 100, unit 'micrograms', route 'under the
    tongue'. Names, units and routes are matched to the app's reference ('molly', 'mcg', 'snorted' work). Writes NOTHING:
    returns a read-back and a proposal_id. Read it to the person, ask yes or no, then call confirm_log."""
    g = guard()
    if not isinstance(dose, (int, float)) or dose <= 0:
        raise ValueError("The dose must be a number more than zero.")
    sub = resolve_substance(substance)
    if sub["key"] == "alcohol":
        raise ValueError("For alcohol, use log_drink with a preset (for example 'beer'). list_presets shows them.")
    roa = resolve_route(sub, route)
    value, unit_used = convert_dose(float(dose), unit, roa)
    notes = (notes or "").strip()
    if len(notes) > sj_guard.NOTE_MAX_CHARS:
        raise ValueError(f"That note is too long; keep it under {sj_guard.NOTE_MAX_CHARS} characters.")
    b = g.backend()
    who = g.person(person or None, b)
    at = g.when(minutes_ago)
    readback = f"Log {spoken_amount(value, unit_used)} of {sub['name']}, {ROUTE_SPOKEN.get(roa['route'], roa['route'])}, for {who['name']}, {when_words(at, g.now())}"
    warnings = [w for w in (dose_warning(roa, value),) if w]
    item = {"substance_key": sub["key"], "route": roa["route"], "dose": value, "unit": unit_used, "notes": notes, "details": {}}
    return g.propose("dose", who, at, readback, [item], warnings, b)


def _build_drink(preset: str, count: int = 1, person: str = "", minutes_ago: float = 0) -> str:
    """Step 1 of logging drinks: a drink preset by name (for example 'beer' or 'shot of vodka') and how many. Writes
    NOTHING: returns a read-back with standard drinks and a proposal_id. Read it out, ask yes or no, then call confirm_log."""
    g = guard()
    cap = g.limits().max_drinks_per_log
    if isinstance(count, bool) or int(count) != count or not 1 <= int(count) <= cap:
        raise ValueError(f"How many drinks? Give a whole number from 1 to {cap}. For more, add them in the app.")
    count = int(count)
    b = g.backend()
    p = find_preset(b.presets(drinks=True), preset)
    who = g.person(person or None, b)
    at = g.when(minutes_ago)
    abv = float(json.loads(p["details_json"] or "{}").get("abv", 0))
    grams_each = grams(p["amount"], p["unit"], abv)
    std = grams_each / STANDARD_DRINK_G * count
    readback = f"Log {count} x {p['name']} for {who['name']}, {when_words(at, g.now())}, about {std:.1f} standard drinks"
    item = {"substance_key": "alcohol", "route": "oral", "dose": grams_each, "unit": "g", "notes": "",
            "details": {"drink": p["name"], "volume": p["amount"], "volumeUnit": p["unit"], "abv": abv}}
    return g.propose("drink", who, at, readback, [dict(item) for _ in range(count)], [], b)


def _build_preset(preset: str, person: str = "", minutes_ago: float = 0) -> str:
    """Step 1 of logging a dose preset saved in the app (not a drink), by name, for example 'my usual tab'. Writes NOTHING:
    returns a read-back and a proposal_id. Read it out, ask yes or no, then call confirm_log."""
    g = guard()
    b = g.backend()
    p = find_preset(b.presets(drinks=False), preset)
    who = g.person(person or None, b)
    at = g.when(minutes_ago)
    name = display_name(p["substance_key"])
    readback = (f"Log {p['name']}: {spoken_amount(p['amount'], p['unit'])} of {name}, {ROUTE_SPOKEN.get(p['route'], p['route'])}, "
                f"for {who['name']}, {when_words(at, g.now())}")
    sub = by_key(p["substance_key"])
    roa = next((x for x in (sub or {}).get("roas", []) if x["route"] == p["route"]), None)
    warnings = [w for w in ((dose_warning(roa, p["amount"]) if roa and roa.get("unit") == p["unit"] else ""),) if w]
    item = {"substance_key": p["substance_key"], "route": p["route"], "dose": p["amount"], "unit": p["unit"], "notes": "",
            "details": {"preset": p["name"]}}
    return g.propose("dose", who, at, readback, [item], warnings, b)


def _build_note(text: str, person: str = "", minutes_ago: float = 0) -> str:
    """Step 1 of adding a timed note (for example 'feeling anxious', 'drank water', 'peaking') to the person's current
    session so it shows on the timeline. Writes NOTHING: returns a read-back and a proposal_id. Read it out, ask yes or no,
    then call confirm_log."""
    g = guard()
    text = (text or "").strip()
    if not text:
        raise ValueError("What should the note say?")
    if len(text) > sj_guard.NOTE_MAX_CHARS:
        raise ValueError(f"That note is too long; keep it under {sj_guard.NOTE_MAX_CHARS} characters.")
    b = g.backend()
    who = g.person(person or None, b)
    at = g.when(minutes_ago)
    if b.session_near(who, at) is False:
        raise ValueError("There is no session in the 12 hours around then to put a note on. Log a dose first.")
    readback = f'Add the note "{text}" for {who["name"]}, {when_words(at, g.now())}'
    warnings = [URGENT] if _URGENT_WORDS.search(text) else []
    return g.propose("note", who, at, readback, [{"note": text}], warnings, b)


def _held(p) -> str:
    return _json({"held_for_yes": True, "saved": "nothing", "read_back_to_user": f"{p.readback}?", "warnings_to_say_aloud": p.warnings,
                  "proposal_id": p.id,
                  "next": "Read this and the warnings to the person and ask yes or no. Call confirm_log with their exact answer only after they reply."})


def _saved(g, p) -> str:
    result = g.log_now(p)
    out = {"told_to_user": f"Saved: {result['saved']}.", "entries": result["entries"], "undo": result["undo"]}
    if g.meta("intro_shown") is None:
        g.set_meta("intro_shown", g.now().isoformat(timespec="seconds"))
        out["first_time_read_this_out"] = HOW_TO_ASK
    return _json(out)


def _log(p) -> str:
    return _held(p) if p.warnings else _saved(guard(), p)


@_safe
def prepare_dose(substance: str, dose: float, unit: str = "", route: str = "", person: str = "", minutes_ago: float = 0, notes: str = "") -> str:
    """Checks what logging a dose would do and writes NOTHING: returns a read-back and a proposal_id (for confirm_log). To actually log, use log_dose."""
    return _prepared(_build_dose(substance, dose, unit, route, person, minutes_ago, notes))


@_safe
def prepare_drink(preset: str, count: int = 1, person: str = "", minutes_ago: float = 0) -> str:
    """Checks what logging drinks would do and writes NOTHING: returns a read-back and a proposal_id (for confirm_log). To actually log, use log_drink."""
    return _prepared(_build_drink(preset, count, person, minutes_ago))


@_safe
def prepare_preset(preset: str, person: str = "", minutes_ago: float = 0) -> str:
    """Checks what logging a saved dose preset would do and writes NOTHING: returns a read-back and a proposal_id (for confirm_log). To actually log, use log_preset."""
    return _prepared(_build_preset(preset, person, minutes_ago))


@_safe
def prepare_note(text: str, person: str = "", minutes_ago: float = 0) -> str:
    """Checks what adding a note would do and writes NOTHING: returns a read-back and a proposal_id (for confirm_log). To actually add it, use log_note."""
    return _prepared(_build_note(text, person, minutes_ago))


# ---- tools: log now (saves immediately, tells the person what was saved) ---------------------------------------------
@mcp.tool(annotations=ADD)
@_safe
def log_dose(substance: str, dose: float, unit: str = "", route: str = "", person: str = "", minutes_ago: float = 0, notes: str = "") -> str:
    """Logs a dose of any compound RIGHT NOW with no yes/no step, for example substance 'LSD', dose 100, unit 'micrograms', route 'under the
    tongue'. Then tell the person exactly what was saved and that they can say 'undo that'. Names, units and routes are matched to the app's
    reference ('molly', 'mcg', 'snorted' work). A dose above the reference's strong range is NOT saved: it comes back held_for_yes. For alcohol use log_drink."""
    return _log(_build_dose(substance, dose, unit, route, person, minutes_ago, notes))


@mcp.tool(annotations=ADD)
@_safe
def log_drink(preset: str, count: int = 1, person: str = "", minutes_ago: float = 0) -> str:
    """Logs drinks RIGHT NOW with no yes/no step: a drink preset by name (for example 'beer' or 'shot of vodka') and how many. Then tell the
    person exactly what was saved, including the standard drinks, and that they can say 'undo that'."""
    return _log(_build_drink(preset, count, person, minutes_ago))


@mcp.tool(annotations=ADD)
@_safe
def log_preset(preset: str, person: str = "", minutes_ago: float = 0) -> str:
    """Logs a dose preset saved in the app (not a drink), by name, for example 'my usual tab', RIGHT NOW with no yes/no step. Then tell the person
    exactly what was saved and that they can say 'undo that'. A dose above the reference's strong range comes back held_for_yes."""
    return _log(_build_preset(preset, person, minutes_ago))


@mcp.tool(annotations=ADD)
@_safe
def log_note(text: str, person: str = "", minutes_ago: float = 0) -> str:
    """Adds a timed note (for example 'feeling anxious', 'drank water', 'peaking') to the person's current session RIGHT NOW with no yes/no step.
    Then tell the person what was saved. A note that sounds like an emergency comes back held_for_yes and the urgent-help line applies."""
    return _log(_build_note(text, person, minutes_ago))


# ---- tools: step 2, the only writes ------------------------------------------------------------------------------
@mcp.tool(annotations=ADD)
@_safe
def confirm_log(proposal_id: str, user_reply: str) -> str:
    """Saves an entry that was held for a yes (held_for_yes) after the person has heard the read-back and said yes. `user_reply` must be the person's actual spoken or typed answer to
    the read-back; it must be a clear yes. Each proposal can be confirmed once, and only within 5 minutes."""
    g = guard()
    result = g.confirm(proposal_id, user_reply)
    if g.meta("intro_shown") is None:
        g.set_meta("intro_shown", g.now().isoformat(timespec="seconds"))
        result["first_time_read_this_out"] = HOW_TO_ASK
    return _json(result)


@mcp.tool(annotations=REMOVE)
@_safe
def undo_last(user_reply: str) -> str:
    """Removes the entry (or drinks) the assistant itself added most recently, only within the undo window (10 minutes by
    default) and only if nobody changed it in the app since. Ask the person first; `user_reply` is their actual yes.
    It can never remove anything else."""
    return _json(guard().undo_last(user_reply))


if __name__ == "__main__":
    mcp.run()
