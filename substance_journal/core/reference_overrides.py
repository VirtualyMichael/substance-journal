"""Audited corrections layered on top of the PsychonautWiki/TripSit sync.

scripts/sync_substance_data.py pulls raw reference data; apply_overrides() then
applies every correction found in the 2026-10 data audit (docs/data-audit/), so a
re-sync can never silently revert them. Each substance records what was changed in
its "overrides" list and where the numbers come from in "sources". apply_overrides is
idempotent: running it twice gives the same result as running it once.
"""
from __future__ import annotations

import copy
import re

_DAYS_PER_UNIT = {
    "hour": 1 / 24, "hours": 1 / 24, "day": 1.0, "days": 1.0, "week": 7.0, "weeks": 7.0, "month": 30.0, "months": 30.0,
}
_TOLERANCE_DAYS_RE = re.compile(
    r"(?P<lo>\d+(?:\.\d+)?)\s*(?:-\s*(?P<hi>\d+(?:\.\d+)?)\s*)?(?P<unit>hours|hour|days|day|weeks|week|months|month)"
)


def parse_tolerance_days(text: str | None) -> float | None:
    """Midpoint of a PsychonautWiki tolerance string such as "3 - 7 days" or "1 month"."""
    if not text:
        return None
    match = _TOLERANCE_DAYS_RE.search(text.lower())
    if not match:
        return None
    lo = float(match.group("lo"))
    hi = float(match.group("hi")) if match.group("hi") else lo
    return ((lo + hi) / 2) * _DAYS_PER_UNIT[match.group("unit")]


def _span(lo: float, hi: float, units: str) -> dict:
    return {"min": lo, "max": hi, "units": units}


# Original one-line descriptions replacing PsychonautWiki's placeholder summaries
# ("Summary sheet: LSD LSD") and off-topic warnings.
SUMMARIES = {
    "alcohol": (
        "Ethanol, the legal depressant in beer, wine and spirits. Effects follow blood alcohol "
        "concentration, and the body clears it at a roughly constant rate, so heavy sessions take "
        "many hours to wear off. Combining it with other depressants is especially dangerous."
    ),
    "nicotine": (
        "The main stimulant in tobacco, also delivered by vapes, pouches, gum and lozenges. Effects "
        "are brief but dependence and tolerance develop quickly. The dose you absorb depends heavily "
        "on the product and how it is used."
    ),
    "cannabis": (
        "Plant containing THC and CBD, used smoked, vaporised, as edibles or as tinctures. Smoked "
        "effects arrive within minutes and last a few hours; edibles are slower, stronger per mg "
        "absorbed and last much longer. Potency and absorbed dose vary widely between products."
    ),
    "psilocybin_mushrooms": (
        "Mushrooms containing psilocybin, which the body converts to the psychedelic psilocin. "
        "Potency varies between species and batches. Never eat wild mushrooms you cannot identify "
        "with certainty, because poisonous look-alikes exist."
    ),
    "lsd": (
        "A potent synthetic psychedelic dosed in micrograms, usually on blotter paper. A trip lasts "
        "roughly 8-12 hours and longer at higher doses. Tolerance builds within hours and resets in "
        "about five days."
    ),
    "dmt": (
        "A short-acting, very intense psychedelic, usually vaporised. Effects start within seconds, "
        "peak within minutes and are largely over in 20 minutes. A sober sitter is recommended."
    ),
    "mdma": (
        "An entactogen-stimulant that raises serotonin, dopamine and noradrenaline. Risks include "
        "overheating, hyponatremia and serotonin syndrome, and tolerance builds quickly. Blood "
        "levels rise faster than the dose, so larger doses are disproportionately stronger."
    ),
    "2c-b": (
        "A phenethylamine psychedelic with a stimulating, visual character, taken orally or "
        "insufflated. Oral doses take up to 90 minutes to peak. Effects last 4-7 hours."
    ),
    "ketamine": (
        "A dissociative anaesthetic that causes sedation, numbness and detachment. Effects are brief "
        "when insufflated and slower to start when swallowed. Frequent use is linked to severe "
        "bladder damage and long-lasting tolerance."
    ),
}

CATEGORY_OVERRIDES = {"cannabis": "Cannabinoid", "nicotine": "Stimulant"}

SOURCES = {
    "alcohol": [
        "https://psychonautwiki.org/wiki/Alcohol",
        "https://pubmed.ncbi.nlm.nih.gov/17064864/",
    ],
    "nicotine": [
        "https://psychonautwiki.org/wiki/Nicotine",
        "https://erowid.org/chemicals/nicotine/nicotine_dose.shtml",
        "https://cancercontrol.cancer.gov/brp/tcrb/monographs/7/m7_7.pdf",
    ],
    "cannabis": [
        "https://psychonautwiki.org/wiki/Cannabis",
        "https://www.erowid.org/plants/cannabis/cannabis_dose.shtml",
        "https://erowid.org/references/refs_view.php?ID=6617",
    ],
    "psilocybin_mushrooms": [
        "https://psychonautwiki.org/wiki/Psilocybin_mushrooms",
        "https://erowid.org/plants/mushrooms/mushrooms_dose.shtml",
        "https://pubmed.ncbi.nlm.nih.gov/39812743/",
    ],
    "lsd": [
        "https://psychonautwiki.org/wiki/LSD",
        "https://erowid.org/chemicals/lsd/lsd_dose.shtml",
        "https://edoc.unibas.ch/56155",
    ],
    "dmt": [
        "https://psychonautwiki.org/wiki/DMT",
        "https://erowid.org/chemicals/dmt/dmt_dose.shtml",
    ],
    "mdma": [
        "https://psychonautwiki.org/wiki/MDMA",
        "https://erowid.org/chemicals/mdma/mdma_dose.shtml",
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC2014905",
    ],
    "2c-b": [
        "https://psychonautwiki.org/wiki/2C-B",
        "https://erowid.org/chemicals/2cb/2cb_dose.shtml",
    ],
    "ketamine": [
        "https://psychonautwiki.org/wiki/Ketamine",
        "https://erowid.org/chemicals/ketamine/ketamine_dose.shtml",
        "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10479106/",
    ],
}

SAFETY_NOTES = {
    "alcohol": [
        "PsychonautWiki doses are grams of ethanol with a 10 g standard drink; the US standard drink is 14 g.",
    ],
    "nicotine": [
        "Doses are mg absorbed, not mg in the product. A cigarette delivers roughly 1-2 mg (range about 0.4-3.5), "
        "while a pouch or gum lists its content, of which only part is absorbed.",
    ],
    "cannabis": [
        "Doses are mg of THC reaching you, not mg of THC in the flower. Only about 10-35% of smoked THC and "
        "4-20% of oral THC is absorbed.",
        "New users: Erowid's strong oral range starts at 4 mg and PsychonautWiki's at 10 mg. Start with 2.5 mg and wait.",
    ],
    "psilocybin_mushrooms": [
        "Dried P. cubensis holds roughly 6-12 mg psilocybin per gram and varies up to 10x between batches.",
        "Erowid puts heavy at 35 mg+ (PsychonautWiki 50 mg+).",
    ],
    "lsd": [
        "Blotter is often NBOMe sold as LSD; reagent test it.",
        "Duration scales with dose: about 8 h at 100 ug and 12 h at 200 ug (Dolder 2017).",
        "SSRIs and antipsychotics can blunt LSD, which may lead to dangerous redosing.",
        "Cannabis with LSD has a strong, unpredictable synergy that can cause anxiety, paranoia and panic.",
    ],
    "dmt": [
        "Residue left in a pipe can add up to ~20 mg to the next load.",
        "Changa (DMT on an MAOI herb blend) needs lower doses and lasts longer.",
        "Cannabis with DMT has a strong, unpredictable synergy.",
    ],
    "mdma": [
        "Blood levels rise more than proportionally with dose (de la Torre 2000); do not scale doses linearly.",
        "Wait 1-3 months between uses. Avoid redosing, overheating, and more than ~3 L of water in a few hours.",
        "Erowid puts strong at 150-200 mg (PsychonautWiki 120-150 mg).",
    ],
    "2c-b": [
        "Pills are frequently under- or mis-dosed.",
        "Oral 2C-B can take up to 90 minutes to peak; do not redose early.",
    ],
    "ketamine": [
        "Erowid's k-hole range begins around 100 mg insufflated (PsychonautWiki heavy is 150 mg).",
        "Frequent use risks severe bladder and liver injury, and long-lasting tolerance.",
        "Grapefruit can double oral exposure.",
    ],
}


def _find_route(substance: dict, route: str) -> dict | None:
    return next((r for r in substance["roas"] if r["route"] == route), None)


def _move_interaction(substance: dict, name: str, to: str) -> None:
    """Place `name` in exactly one tier: to in {"dangerous", "unsafe", "uncertain"}."""
    for tier in ("dangerous", "unsafe", "uncertain"):
        key = f"{tier}_interactions"
        if tier != to and name in substance[key]:
            substance[key].remove(name)
    key = f"{to}_interactions"
    if name not in substance[key]:
        substance[key].append(name)


def apply_overrides(substances: list[dict]) -> list[dict]:
    result = copy.deepcopy(substances)
    by_key = {s["key"]: s for s in result}
    notes: dict[str, list[str]] = {key: [] for key in by_key}

    def note(key: str, text: str) -> None:
        notes[key].append(text)

    for key, substance in by_key.items():
        if key in SUMMARIES:
            substance["summary"] = SUMMARIES[key]
            note(key, "Replaced placeholder or off-topic summary.")
        if key in CATEGORY_OVERRIDES:
            substance["category"] = CATEGORY_OVERRIDES[key]
            note(key, "Set category.")
        substance["audited"] = True
        substance["sources"] = SOURCES.get(key, [])
        substance["safety_notes"] = SAFETY_NOTES.get(key, [])

    # --- tolerance (PsychonautWiki publishes half and zero times; use the half time directly) ---
    ketamine = by_key["ketamine"]
    ketamine["tolerance_half"] = "2 weeks"
    ketamine["tolerance_zero"] = "4 weeks"
    ketamine["tolerance_zero_days"] = 28.0
    note("ketamine", "Tolerance: 14 days is the half time, baseline is 28 days (was stored as 14).")

    for substance in result:
        if substance["has_tolerance"]:
            substance["tolerance_half_days"] = parse_tolerance_days(substance.get("tolerance_half"))
        else:
            substance["tolerance_half_days"] = None

    by_key["2c-b"]["tolerance_group"] = None
    note("2c-b", "Own tolerance track: PsychonautWiki reports no cross-tolerance with other serotonergic psychedelics.")
    by_key["dmt"]["tolerance_group"] = None

    # --- interactions ---
    _move_interaction(by_key["psilocybin_mushrooms"], "Lithium", "dangerous")
    note("psilocybin_mushrooms", "Lithium moved to dangerous, matching LSD/DMT/2C-B (PsychonautWiki: strictly avoid).")
    _move_interaction(by_key["mdma"], "Protease Inhibitors", "unsafe")
    _move_interaction(by_key["mdma"], "GHB", "unsafe")
    _move_interaction(by_key["mdma"], "GBL", "unsafe")
    note("mdma", "Protease inhibitors, GHB and GBL raised to unsafe (slowed clearance; unconsciousness risk).")
    _move_interaction(by_key["ketamine"], "Benzodiazepines", "unsafe")
    note("ketamine", "Benzodiazepines raised to unsafe (potentiated sedation, unexpected unconsciousness).")
    _move_interaction(by_key["dmt"], "MAOIs", "unsafe")
    note("dmt", "Added MAOIs as unsafe: an unplanned MAOI drastically changes dose and duration.")
    _move_interaction(by_key["lsd"], "SSRIs", "uncertain")
    _move_interaction(by_key["lsd"], "MDMA", "uncertain")
    note("lsd", "Added SSRIs and MDMA as uncertain.")

    # --- durations ---
    cannabis = by_key["cannabis"]
    oral = _find_route(cannabis, "oral")
    oral["duration"]["onset"] = _span(20.0, 120.0, "minutes")
    oral["duration"]["peak"] = _span(1.0, 3.0, "hours")
    note("cannabis", "Oral onset widened to 20-120 min and peak to 1-3 h (Erowid, Grotenhermen).")
    note("cannabis", "Sublingual route present (PsychonautWiki durations; it publishes no dose table).")
    if _find_route(cannabis, "sublingual") is None:
        cannabis["roas"].append(
            {
                "route": "sublingual",
                "unit": "mg",
                "dose_threshold": None,
                "dose_light": None,
                "dose_common": None,
                "dose_strong": None,
                "dose_heavy": None,
                "duration": {
                    "onset": _span(1.0, 10.0, "minutes"),
                    "comeup": _span(15.0, 30.0, "minutes"),
                    "peak": _span(30.0, 60.0, "minutes"),
                    "offset": _span(4.0, 6.0, "hours"),
                    "total": _span(3.0, 7.0, "hours"),
                    "afterglow": None,
                },
            }
        )

    _find_route(by_key["mdma"], "oral")["duration"]["onset"] = _span(20.0, 70.0, "minutes")
    note("mdma", "Onset widened to 20-70 min (Erowid).")
    _find_route(by_key["dmt"], "smoked")["duration"]["onset"] = _span(15.0, 60.0, "seconds")
    note("dmt", "Onset widened to 15-60 s (Erowid).")

    k_insufflated = _find_route(ketamine, "insufflated")
    k_insufflated["duration"]["onset"] = _span(1.0, 15.0, "minutes")
    k_insufflated["duration"]["total"] = _span(45.0, 120.0, "minutes")
    note("ketamine", "Insufflated onset widened to 1-15 min and total to 45-120 min (Erowid: 5-15 min, 45-60 min).")
    k_oral = _find_route(ketamine, "oral")
    k_oral["duration"]["onset"] = _span(5.0, 30.0, "minutes")
    k_oral["duration"]["offset"] = _span(1.0, 2.0, "hours")
    k_oral["duration"]["total"] = _span(1.5, 3.0, "hours")
    note("ketamine", "Oral active effects shortened: offset 1-2 h (was 3-6 h), total 1.5-3 h; Erowid gives ~90 min.")

    nicotine_smoked = _find_route(by_key["nicotine"], "smoked")
    nicotine_smoked["duration"]["total"] = _span(10.0, 30.0, "minutes")
    nicotine_smoked["duration"]["offset"] = _span(5.0, 20.0, "minutes")
    note("nicotine", "Smoked: active effect 10-30 min (total) with offset 5-20 min; the 1-3 h figure is the after-effect window.")

    for key, substance in by_key.items():
        substance["overrides"] = notes[key]
    return result
