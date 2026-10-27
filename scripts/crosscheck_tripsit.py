"""Cross-check the PsychonautWiki-derived catalog against TripSit's open drug dataset.

For every compound both sources cover, compare dose bands and durations route by route:
  agrees     every comparable dose threshold is within 1.5x and timings overlap
  conflicts  at least one comparable threshold differs by more than 1.5x
  no_data    nothing comparable (different routes or units, or a band one source omits)

Results go to data/crosscheck_tripsit.json (applied to the catalog by catalog_import) and a readable
report in docs/data-audit/crosscheck.md. TripSit's data is licensed CC BY-SA 4.0; only the verdict and
the conflicting numbers are kept, with a link to their page.

  python scripts/crosscheck_tripsit.py [path/to/drugs.json]   # downloads it when no path is given
"""
from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRIPSIT_URL = "https://raw.githubusercontent.com/TripSit/drugs/main/drugs.json"
RATIO = 1.5

UNIT_TO_MG = {"mg": 1.0, "g": 1000.0, "ug": 0.001, "µg": 0.001, "μg": 0.001, "mcg": 0.001}


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def parse_amount(text: str):
    """'75mg-250mg', '100-150ug', '400mg+', '1.5ml+', '2g' -> (low, high_or_None, unit) or None."""
    s = text.strip().lower().replace("µ", "u").replace("μ", "u").replace(" ", "")
    m = re.fullmatch(r"([\d.]+)([a-z]*)(?:-([\d.]+)([a-z]*))?(\+?)", s)
    if not m:
        return None
    lo, unit1, hi, unit2, plus = m.groups()
    unit = unit2 or unit1
    if not unit:
        return None
    try:
        low = float(lo)
        high = float(hi) if hi else None
    except ValueError:
        return None
    if plus:
        high = None
    elif high is None:
        high = low
    return low, high, unit


def to_base(value: float, unit: str):
    """(value in mg or ml, 'mg' | 'ml') or None for units that cannot be compared."""
    u = unit.replace("µ", "u").replace("μ", "u")
    if u in UNIT_TO_MG:
        return value * UNIT_TO_MG[u], "mg"
    if u == "ml":
        return value, "ml"
    return None


def our_bands(roa: dict):
    """Lower bounds of each band, in the route's own unit."""
    bands = {}
    if roa.get("dose_threshold") is not None:
        bands["Threshold"] = roa["dose_threshold"]
    for ours, theirs in (("dose_light", "Light"), ("dose_common", "Common"), ("dose_strong", "Strong")):
        if roa.get(ours) and roa[ours].get("min") is not None:
            bands[theirs] = roa[ours]["min"]
    if roa.get("dose_heavy") is not None:
        bands["Heavy"] = roa["dose_heavy"]
    return bands


def duration_range(block, to_hours: float):
    if not block:
        return None
    lo, hi = block.get("min"), block.get("max")
    if lo is None and hi is None:
        return None
    return (lo if lo is not None else hi) * to_hours, (hi if hi is not None else lo) * to_hours


def minutes_factor(units: str) -> float:
    return {"seconds": 1 / 60, "minutes": 1.0, "hours": 60.0, "days": 1440.0}.get(units, 1.0)


def our_total_minutes(roa: dict):
    d = (roa.get("duration") or {}).get("total")
    if not d:
        return None
    f = minutes_factor(d.get("units", "minutes"))
    lo, hi = d.get("min"), d.get("max")
    if lo is None and hi is None:
        return None
    return (lo if lo is not None else hi) * f, (hi if hi is not None else lo) * f


def their_total_minutes(entry: dict):
    block = entry.get("formatted_duration")
    if not isinstance(block, dict) or not block.get("value"):
        return None
    m = re.fullmatch(r"\s*([\d.]+)\s*(?:-\s*([\d.]+))?\s*\+?\s*", str(block["value"]))
    if not m:
        return None
    lo = float(m.group(1))
    hi = float(m.group(2)) if m.group(2) else lo
    f = minutes_factor(block.get("_unit", "hours"))
    return lo * f, hi * f


def compare_route(roa: dict, trip_bands: dict) -> dict:
    ours = our_bands(roa)
    unit_ours = roa.get("unit", "")
    base_ours = to_base(1.0, unit_ours)
    compared, conflicts = 0, []
    for band, their_text in trip_bands.items():
        if band not in ours or base_ours is None:
            continue
        parsed = parse_amount(their_text)
        if not parsed:
            continue
        theirs = to_base(parsed[0], parse_amount(their_text)[2])
        if theirs is None or theirs[1] != base_ours[1]:
            continue
        mine = ours[band] * base_ours[0]
        if mine <= 0 or theirs[0] <= 0:
            continue
        compared += 1
        ratio = max(mine, theirs[0]) / min(mine, theirs[0])
        if ratio > RATIO:
            conflicts.append({
                "route": roa["route"],
                "band": band,
                "psychonautwiki": f"{ours[band]:g} {unit_ours}",
                "tripsit": their_text,
                "tripsit_is_lower": theirs[0] < mine,
            })
    return {"route": roa["route"], "compared": compared, "conflicts": conflicts}


def tripsit_slug(key: str) -> str:
    return urllib.parse.quote(key, safe="")


def crosscheck(ours: list[dict], tripsit: dict) -> dict:
    index = {}
    for key, entry in tripsit.items():
        for name in [key, entry.get("pretty_name", ""), *entry.get("aliases", [])]:
            index.setdefault(norm(name), key)
    results = {}
    for s in ours:
        names = [s["name"], s["key"], *s.get("common_names", [])]
        match = next((index[norm(n)] for n in names if norm(n) in index), None)
        if match is None:
            results[s["key"]] = {"status": "not_covered"}
            continue
        entry = tripsit[match]
        trip_routes = {r.lower().replace("vapourized", "vaporized"): bands for r, bands in (entry.get("formatted_dose") or {}).items()}
        agrees, conflicts, compared = [], [], 0
        for roa in s["roas"]:
            bands = trip_routes.get(roa["route"].lower())
            if not bands:
                continue
            r = compare_route(roa, bands)
            compared += r["compared"]
            if r["compared"] >= 2 and not r["conflicts"]:
                agrees.append(r["route"])
            conflicts.extend(r["conflicts"])
        durations = None
        mine = next((our_total_minutes(r) for r in s["roas"] if our_total_minutes(r)), None)
        theirs = their_total_minutes(entry)
        if mine and theirs:
            durations = "overlap" if mine[0] <= theirs[1] and theirs[0] <= mine[1] else "differ"
        if conflicts:
            status = "conflicts"
        elif agrees and durations != "differ":
            status = "agrees"
        else:
            status = "no_data"
        results[s["key"]] = {
            "status": status,
            "tripsit_key": match,
            "url": f"https://tripsit.me/factsheets/{tripsit_slug(match)}",
            "agrees": agrees,
            "conflicts": conflicts,
            "durations": durations,
            "checked": date.today().isoformat(),
        }
    return results


def report(ours: list[dict], results: dict) -> str:
    by = {}
    for r in results.values():
        by[r["status"]] = by.get(r["status"], 0) + 1
    lines = [
        "# Cross-check against TripSit",
        "",
        f"Generated by `scripts/crosscheck_tripsit.py` on {date.today().isoformat()}. TripSit data: CC BY-SA 4.0, https://github.com/TripSit/drugs.",
        "",
        "Method: for each compound both sources cover, compare the lower bound of every dose band (threshold, light, common, strong, heavy) per route.",
        f"Within {RATIO}x counts as agreement. Conflicts list the numbers both sources give. Where TripSit is lower, the app adds a note to start with the lower figure.",
        "",
        f"- Agree (promoted to cross-checked): {by.get('agrees', 0)}",
        f"- Conflict (kept as not audited, with a note): {by.get('conflicts', 0)}",
        f"- Nothing comparable: {by.get('no_data', 0)}",
        f"- Not in TripSit's data: {by.get('not_covered', 0)}",
        "",
    ]
    names = {s["key"]: s["name"] for s in ours}
    lines += ["## Conflicts", ""]
    for key, r in sorted(results.items(), key=lambda kv: names.get(kv[0], kv[0])):
        if r["status"] != "conflicts":
            continue
        lines.append(f"### {names[key]}  ([TripSit]({r['url']}))")
        for c in r["conflicts"]:
            lines.append(f"- {c['route']}, {c['band']}: PsychonautWiki {c['psychonautwiki']}, TripSit {c['tripsit']}" + ("  (TripSit lower)" if c["tripsit_is_lower"] else ""))
        lines.append("")
    lines += ["## Agree", ""]
    lines += [f"- {names[k]}: {', '.join(r['agrees'])}" for k, r in sorted(results.items(), key=lambda kv: names.get(kv[0], kv[0])) if r["status"] == "agrees"]
    return "\n".join(lines) + "\n"


def main() -> None:
    ours = json.loads((ROOT / "data" / "substances_extra.json").read_text(encoding="utf-8"))
    if len(sys.argv) > 1:
        tripsit = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    else:
        with urllib.request.urlopen(TRIPSIT_URL, timeout=60) as resp:
            tripsit = json.loads(resp.read().decode("utf-8"))
    results = crosscheck(ours, tripsit)
    sys.path.insert(0, str(ROOT))
    from substance_journal.core.catalog_import import apply_crosschecks  # noqa: E402

    (ROOT / "data" / "substances_extra.json").write_text(
        json.dumps(apply_crosschecks(ours, results), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (ROOT / "data" / "crosscheck_tripsit.json").write_text(json.dumps(results, indent=1, ensure_ascii=False), encoding="utf-8")
    (ROOT / "docs" / "data-audit" / "crosscheck.md").write_text(report(ours, results), encoding="utf-8")
    counts = {}
    for r in results.values():
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print(counts)


if __name__ == "__main__":
    main()
