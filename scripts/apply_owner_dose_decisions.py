"""Puts the owner's own dose decisions back into app/assets/data/dose_audit.json.

The owner decided (commit 6c7a7ec, 2026-11-11) which figures to use where PsychonautWiki and TripSit disagree: stimulants use TripSit's higher figures,
prescription drugs and kratom use the lower ones. Those figures live in app/assets/data/substances_extra.json. The dose audit (build_dose_audit.py) would
otherwise replace them, so run this AFTER build_dose_audit.py: for each route listed in OWNER_DECIDED, the audited bands are set to the catalog's bands and the
entry says so. The audit's sources stay, so the page still shows what each source published.

    python scripts/apply_owner_dose_decisions.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "app" / "assets" / "data"
OWNER_DECIDED = [
    ("5-meo-dmt", "insufflated"), ("amphetamine", "oral"), ("caffeine", "oral"), ("cocaine", "insufflated"),
    ("heroin", "smoked"), ("kratom", "oral"), ("methylphenidate", "oral"), ("morphine", "oral"),
]
NOTE = "Owner decision (2026-11-11): these bands are the owner's chosen figures where the sources disagree, not the audit's median."


def band(b):
    return {"min": b["min"], "max": b["max"]} if isinstance(b, dict) and b.get("min") is not None else None


def main() -> None:
    cat = json.loads((DATA / "substances_extra.json").read_text(encoding="utf-8"))
    items = cat if isinstance(cat, list) else cat.get("substances", cat)
    items = items if isinstance(items, list) else list(items.values())
    by_key = {s["key"]: s for s in items}
    path = DATA / "dose_audit.json"
    audit = json.loads(path.read_text(encoding="utf-8"))
    n = 0
    for key, route in OWNER_DECIDED:
        entry = audit["substances"].get(key, {}).get(route)
        roa = next((r for r in by_key.get(key, {}).get("roas", []) if r["route"] == route), None)
        if entry is None or roa is None:
            continue
        entry["threshold"] = roa.get("dose_threshold")
        entry["low"], entry["common"], entry["high"] = band(roa.get("dose_light")), band(roa.get("dose_common")), band(roa.get("dose_strong"))
        entry["heavy"] = roa.get("dose_heavy")
        entry["note"] = (entry.get("note", "") + " " + NOTE).strip() if NOTE not in entry.get("note", "") else entry["note"]
        n += 1
    path.write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"applied the owner's decisions to {n} routes")


if __name__ == "__main__":
    main()
