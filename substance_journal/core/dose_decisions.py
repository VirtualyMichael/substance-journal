"""Dose-band decisions made by the app's owner where sources disagree (2026-11 review).

PsychonautWiki (the base data) and TripSit disagree on many common substances. The owner chose:
  * prescription drugs: use the LOWER of the two sources for every band, and add what the drug label says
  * stimulants (cocaine, amphetamine, caffeine): use TripSit's HIGHER figures
  * kratom and 5-MeO-DMT: use TripSit's lower figures

Each decision lists the band minimums (a band runs up to the next band's minimum, so the ladder never has gaps).
apply_decisions() is idempotent and runs last in apply_crosschecks(), so a re-import can never undo it.
"""
from __future__ import annotations

DECISION_PREFIX = "Decision: "
CROSSCHECK_PREFIX = "Cross-check: "

# (key, route) -> band minimums. A missing band keeps its current value.
BANDS = {
    ("zolpidem", "oral"): {"threshold": 2.5, "light": 2.5, "common": 5, "strong": 10, "heavy": 20},
    ("methylphenidate", "oral"): {"threshold": 5, "light": 5, "common": 10, "strong": 20, "heavy": 40},
    ("morphine", "oral"): {"threshold": 5, "light": 5},
    ("heroin", "smoked"): {"heavy": 30},
    ("kratom", "oral"): {"threshold": 0.5, "light": 0.5, "common": 1.5, "strong": 3, "heavy": 6},
    ("5-meo-dmt", "insufflated"): {"threshold": 3, "light": 3, "common": 5, "strong": 8, "heavy": 15},
    ("cocaine", "insufflated"): {"light": 20, "common": 50, "strong": 100, "heavy": 150},
    ("amphetamine", "oral"): {"light": 10, "common": 20, "strong": 50, "heavy": 70},
    ("caffeine", "oral"): {"strong": 250},
}

NOTES = {
    "zolpidem": [
        "Bands use TripSit's lower figures. The prescribing label recommends 5 mg (women) or 5-10 mg (men) at bedtime and says not to exceed 10 mg a night; PsychonautWiki's common 20 mg is double that.",
    ],
    "methylphenidate": [
        "Oral bands use TripSit's lower figures. Reference sources give adult daily doses around 20-30 mg in divided doses, with 60 mg a day as the usual ceiling for immediate release.",
    ],
    "morphine": [
        "Light starts at TripSit's lower figure (5 mg). Opioid-naive people should start at the bottom of the range; tolerance changes this a lot.",
    ],
    "heroin": [
        "The heavy line uses TripSit's lower figure (30 mg smoked). Purity varies widely and there is no label to compare with.",
    ],
    "methadone": [
        "PsychonautWiki's bands are already lower than TripSit's, so they are kept. The prescribing label starts opioid-naive adults at 2.5 mg every 8-12 hours; methadone's half-life is 8-59 hours and it accumulates over 3-5 days, so peak breathing depression comes later and lasts longer than the high.",
    ],
    "lorazepam": [
        "PsychonautWiki's bands are already lower than TripSit's, so they are kept. The label gives a usual 2-6 mg a day in divided doses (older labels) and a half-life of about 12 hours.",
    ],
    "pregabalin": [
        "PsychonautWiki's bands are already lower than TripSit's, so they are kept. The label's therapeutic range is 150-600 mg a day (300 mg a day for diabetic nerve pain) with a half-life of about 6 hours.",
    ],
    "tramadol": [
        "PsychonautWiki's bands are already lower than TripSit's, so they are kept. The label gives 50-100 mg every 4-6 hours, at most 400 mg a day (300 mg over 75), and seizure and serotonin-syndrome risk rise with higher doses.",
    ],
    "kratom": [
        "Bands use TripSit's lower figures (light 0.5-1.5 g, common 1.5-3 g, strong 3-6 g). Leaf potency varies a lot between batches and extracts are far stronger.",
    ],
    "5-meo-dmt": [
        "Insufflated bands use TripSit's lower figures (light 3-5 mg, common 5-10 mg, strong 8-15 mg). Potency per dose is very steep, so measure with a milligram scale.",
    ],
    "cocaine": [
        "Insufflated bands use TripSit's higher figures; PsychonautWiki lists light 10 mg, common 30 mg, strong 60 mg, heavy 90 mg. Both are for pure cocaine and street purity varies, and fentanyl contamination is a known risk.",
    ],
    "amphetamine": [
        "Oral bands use TripSit's higher figures; PsychonautWiki lists light 5 mg, common 10 mg, strong 25 mg. Clinical doses start at 5-10 mg.",
    ],
    "caffeine": [
        "The strong line uses TripSit's 250 mg; PsychonautWiki lists 150 mg. Health agencies treat up to about 400 mg a day as safe for most adults.",
    ],
}

SOURCES = {
    "zolpidem": ["https://drugs.com/pro/zolpidem.html"],
    "methylphenidate": ["https://Drugs.com/pro/methylphenidate-chewable-tablets.html"],
    "methadone": ["https://drugs.com/dosage/methadone.html"],
    "lorazepam": ["https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=45e31a87-a8db-4dda-b94b-83535b62e8e2"],
    "pregabalin": ["https://www.accessdata.fda.gov/drugsatfda_docs/label/2025/021446s046%2C022488s022lbl.pdf"],
    "tramadol": ["https://www.accessdata.fda.gov/drugsatfda_docs/label/2023/020281s040lbl.pdf"],
}


def _ladder(roa: dict, mins: dict) -> None:
    def cur(band):
        if band == "threshold":
            return roa.get("dose_threshold")
        value = roa.get(f"dose_{band}")
        return value["min"] if isinstance(value, dict) else value

    vals = {b: mins.get(b, cur(b)) for b in ("threshold", "light", "common", "strong", "heavy")}
    roa["dose_threshold"] = vals["threshold"]
    order = ["light", "common", "strong", "heavy"]
    for i, band in enumerate(order[:-1]):
        nxt = vals[order[i + 1]]
        if vals[band] is not None and nxt is not None:
            roa[f"dose_{band}"] = {"min": float(vals[band]), "max": float(nxt)}
    roa["dose_heavy"] = float(vals["heavy"]) if vals["heavy"] is not None else None


def apply_decisions(items: list[dict]) -> list[dict]:
    by_key = {i["key"]: i for i in items}
    for (key, route), mins in BANDS.items():
        item = by_key.get(key)
        if item is None:
            continue
        for roa in item.get("roas", []):
            if roa["route"] == route:
                _ladder(roa, mins)
    for key in set(NOTES) | {k for k, _ in BANDS}:
        item = by_key.get(key)
        if item is None:
            continue
        notes = [n for n in item.get("safety_notes", []) if not n.startswith(DECISION_PREFIX)]
        if (key, "oral") in BANDS or any(k == key for k, _ in BANDS):
            # The sources were reconciled by the owner, so the "start with the lower figure" notes no longer apply.
            notes = [n for n in notes if not n.startswith(CROSSCHECK_PREFIX) or "agree" in n]
        notes += [DECISION_PREFIX + n for n in NOTES.get(key, [])]
        item["safety_notes"] = notes
        for url in SOURCES.get(key, []):
            if url not in item.setdefault("sources", []):
                item["sources"].append(url)
    return items
