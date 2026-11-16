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
        "roughly 8-12 hours and longer at higher doses. Tolerance builds over the day after a dose, "
        "when a repeat dose feels about half as strong, and is gone within about 3 to 6 days."
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
        "https://pubmed.ncbi.nlm.nih.gov/38220293/",
        "https://doi.org/10.3390/jof12070486",
        "https://pubmed.ncbi.nlm.nih.gov/33119971/",
    ],
    "lsd": [
        "https://psychonautwiki.org/wiki/LSD",
        "https://erowid.org/chemicals/lsd/lsd_dose.shtml",
        "https://edoc.unibas.ch/56155",
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC5591798/",
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC8027607/",
        "https://bibliography.maps.org/resources/download/12096",
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
        "Doses are grams of DRIED mushrooms (P. cubensis), the way they are weighed. Dried P. cubensis in published analyses "
        "ranges from under 2 to about 28 mg psilocybin + psilocin per gram (Rodriguez 2025; Galdino 2025; Sharchaton 2026), with "
        "lab-grown batches often near 9-14 mg/g (Goff 2024). The app assumes 10 mg/g when nothing better is known.",
        "Fresh mushrooms are about 90% water, so a dried dose is roughly 10 times heavier fresh: a common 1-2.5 g dried dose is about 10-25 g fresh. Never use dried numbers for fresh weight.",
        "Other species (azurescens, cyanescens and others) can be several times stronger by weight than P. cubensis. The bands are for P. cubensis.",
        "Erowid puts heavy at 3.5 g+ dried (PsychonautWiki 5 g+). A scale reading to 0.1 g or better matters here.",
    ],
    "lsd": [
        "Blotter is often NBOMe sold as LSD; reagent test it.",
        "Duration scales with dose: about 8 h at 100 ug and 12 h at 200 ug (Dolder 2017).",
        "After 100 ug by mouth, effects began 0.8 +/- 0.4 h and peaked 2.8 +/- 0.8 h after the dose (Dolder 2017, oral "
        "solution). No controlled sublingual data were found; the timeline uses these oral figures.",
        "In the 1950s studies a second dose a day later was about half as strong, and during daily dosing even 2-4 times "
        "the dose did not bring the full effect back (Isbell 1956, reviewed by Buchborn 2016).",
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


_BUCHBORN_2016 = (
    "Buchborn T, Grecksch G, Dieterich DC, Hoellt V (2016). Tolerance to lysergic acid diethylamide: overview, "
    "correlates, and clinical implications. Neuropathology of Drug Addictions and Substance Misuse, Vol. 2, "
    "ch. 79, pp. 846-858. https://bibliography.maps.org/resources/download/12096"
)
_ISBELL_1956 = (
    "Isbell H, Belleville RE, Fraser HF, Wikler A, Logan CR (1956). Studies on LSD-25. I. Effects in former morphine "
    "addicts and development of tolerance during chronic intoxication. AMA Arch Neurol Psychiatry 76:468-478 "
    "(as reviewed by Buchborn 2016)"
)
_ISBELL_1961 = (
    "Isbell H, Wolbach AB, Wikler A, Miner EJ (1961). Cross tolerance between LSD and psilocybin. "
    "Psychopharmacologia 2:147-159. PMID 13717955. https://doi.org/10.1007/BF00407974"
)
_WOLBACH_1962 = (
    "Wolbach AB, Isbell H, Miner EJ (1962). Cross tolerance between mescaline and LSD-25. Psychopharmacologia 3:1-14 "
    "(as reviewed by Buchborn 2016)"
)
_BALESTRIERI_1959 = (
    "Balestrieri A, Fontanari D (1959). Acquired and crossed tolerance to mescaline, LSD-25, and BOL-148. "
    "Arch Gen Psychiatry 1:279-282 (as reviewed by Buchborn 2016)"
)
_CHOLDEN_1955 = (
    "Cholden LS, Kurland A, Savage C (1955). Clinical reactions and tolerance to LSD in chronic schizophrenia. "
    "J Nerv Ment Dis 122:211-221; Hoffer A, Osmond H (1967). The hallucinogens (both as reviewed by Buchborn 2016)"
)
_GRESCH_2005 = (
    "Gresch PJ, Smith RL, Barrett RJ, Sanders-Bush E (2005). Behavioral tolerance to lysergic acid diethylamide is "
    "associated with reduced serotonin-2A receptor signaling in rat cortex. Neuropsychopharmacology 30:1693-1702. "
    "PMID 15756304"
)

_LSD_TIME_COURSE = {
    "rise_start_hours": {
        "expected": 6, "low": 6, "high": 3,
        "note": "Two 200 ug doses 6 h apart gave almost the same response (2 patients); a second dose 3 h after the "
                "first added less than its own effect. Anecdotal reports only.",
        "sources": [_BALESTRIERI_1959, "Freedman DX (1984), as reviewed by Buchborn 2016"],
    },
    "peak_hours": {
        "expected": 24,
        "note": "Tolerance to the mental effects is substantial 24 h after one dose (tachyphylaxis).",
        "sources": [_BUCHBORN_2016],
    },
    "single_dose_loss": {
        "expected": 0.52,
        "note": "Self-rated effects of the second daily dose were 52% lower than of the first (daily doses averaging "
                "138 ug, about 10 people). One small 1950s study; the true figure may differ.",
        "sources": [_ISBELL_1956, _BUCHBORN_2016],
    },
    "max_loss": {
        "expected": 0.88,
        "note": "With daily dosing tolerance was near its maximum by day 3-4: on average about 78% less effect, "
                "up to 88% on the physician's rating.",
        "sources": [_ISBELL_1956, _BUCHBORN_2016],
    },
    "recovery_days": {
        "expected": 5, "low": 3, "high": 6,
        "note": "3 days without LSD was enough for full recovery after 14 and 84 days of daily use (Isbell 1956); "
                "other reports give 3-6 days; the review concludes about 5 days to reverse completely.",
        "sources": [_ISBELL_1956, _CHOLDEN_1955, _BUCHBORN_2016],
    },
    "dose_exponent": {
        "expected": 0.5, "low": 1.0, "high": 0.0,
        "note": "No human study measured how tolerance depends on dose size (the studies used about 75-150 ug a day). "
                "The app assumes square-root scaling below a common dose and no extra tolerance above it; the band "
                "runs from proportional scaling to no dependence. This is an app assumption, not a published figure.",
        "sources": [],
    },
}

TOLERANCE_PROFILES = {
    "lsd": {
        **_LSD_TIME_COURSE,
        "summary": "Estimated loss of effect for a same-size dose. Tolerance to LSD is small for the first hours after "
                   "a dose, largest about a day later (a repeat dose then felt about half as strong), builds to about "
                   "80% less effect with daily use for 3-4 days, and is gone within about 3 to 6 days. The route "
                   "(sublingual or swallowed) does not change this.",
        "limits": "From small 1950s-60s studies (mostly 4-11 people, often patients, older questionnaires); no modern "
                  "controlled study of repeated LSD doses was found. Rats show the same pattern with reduced cortical "
                  "5-HT2A signalling (Gresch 2005). Treat the percent as a rough estimate.",
        "cross_tolerance": [
            {"substance": "psilocybin_mushrooms", "factor": 1.0,
             "note": "Cross-tolerance in both directions on most measures; the papers give no single percentage, "
                     "so the app counts a mushroom dose like an LSD dose of the same strength band (an assumption).",
             "sources": [_ISBELL_1961, _BUCHBORN_2016]},
            {"substance": "psilocin", "factor": 1.0,
             "note": "Psilocin is the active form of psilocybin; counted as psilocybin (assumption).",
             "sources": [_ISBELL_1961]},
            {"substance": "mescaline", "factor": 1.0,
             "note": "Cross-tolerance in both directions; no single percentage published, counted fully (assumption).",
             "sources": [_WOLBACH_1962, _BUCHBORN_2016]},
        ],
        "sources": [_BUCHBORN_2016, _GRESCH_2005],
    },
    "psilocybin_mushrooms": {
        **_LSD_TIME_COURSE,
        "recovery_days": {
            "expected": 5, "low": 3, "high": 7,
            "note": "No human time course for psilocybin was found. The LSD figures are used because the two are "
                    "cross-tolerant both ways; the upper end is PsychonautWiki's 7 days for mushrooms.",
            "sources": [_ISBELL_1961, _BUCHBORN_2016, "https://psychonautwiki.org/wiki/Psilocybin_mushrooms"],
        },
        "summary": "Estimated loss of effect for a same-size dose, using LSD's measured time course: no human study "
                   "measured how tolerance to psilocybin builds and fades over days. LSD and psilocybin are "
                   "cross-tolerant both ways, and direct tolerance to psilocybin was reported weaker than to LSD, "
                   "so this may overstate it.",
        "limits": "Borrowed from 1950s LSD studies plus one small 1961 cross-tolerance study; treat it as a rough "
                  "estimate.",
        "cross_tolerance": [
            {"substance": "lsd", "factor": 1.0,
             "note": "Cross-tolerance in both directions; counted fully (assumption, no single percentage published).",
             "sources": [_ISBELL_1961, _BUCHBORN_2016]},
            {"substance": "psilocin", "factor": 1.0, "note": "The active form of psilocybin.", "sources": [_ISBELL_1961]},
            {"substance": "mescaline", "factor": 1.0,
             "note": "Mescaline is cross-tolerant with LSD; with psilocybin by extension (assumption).",
             "sources": [_WOLBACH_1962, _BUCHBORN_2016]},
        ],
        "sources": [_ISBELL_1961, _BUCHBORN_2016],
    },
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

    # Cannabis: PsychonautWiki gives half "1 - 2 weeks" and zero "2 - 3 weeks"; the midpoint of the
    # half time (10.5 days) cannot reach zero in 2-3 weeks. Use the low end, 7 days, which matches
    # PET studies of daily users: CB1 receptors start recovering within 2 days and are back to
    # normal in about 4 weeks (Hirvonen et al. 2012, D'Souza et al. 2016).
    by_key["cannabis"]["tolerance_half_days"] = 7.0
    note("cannabis", "Tolerance half-life 7 days (low end of 1-2 weeks), consistent with CB1 recovery in about 4 weeks.")

    # --- psilocybin: people weigh dried mushrooms, not pure psilocybin ---
    # The published bands were in mg of psilocybin; PsychonautWiki's dried P. cubensis table is the
    # same numbers over about 10 mg psilocybin per gram (2.5 mg = 0.25 g, 25 mg = 2.5 g, 50 mg = 5 g).
    # Only convert data still in mg, so re-running the overrides never converts twice.
    oral = _find_route(by_key["psilocybin_mushrooms"], "oral")
    if oral is not None and oral.get("unit") == "mg":
        oral["unit"] = "g"
        for band in ("dose_threshold", "dose_heavy"):
            if oral.get(band) is not None:
                oral[band] = round(oral[band] / 10, 4)
        for band in ("dose_light", "dose_common", "dose_strong"):
            if oral.get(band):
                oral[band] = {k: (round(v / 10, 4) if v is not None else None) for k, v in oral[band].items()}

    note("psilocybin_mushrooms", "Doses now in grams of dried mushrooms (about 10 mg psilocybin per gram) instead of mg of pure psilocybin.")

    # --- LSD and psilocybin: tolerance profiles from human studies (the Flutter app reads them;
    # substances without one keep the generic half-life model) ---
    for key, profile in TOLERANCE_PROFILES.items():
        by_key[key]["tolerance_profile"] = copy.deepcopy(profile)
        by_key[key]["tolerance_full"] = "builds over the first day after a dose; largest about 24 hours later"
        note(key, "Tolerance profile added (time course, size and cross-tolerance, with sources); 'full' tolerance "
                  "timing corrected from 'almost immediately' (Buchborn 2016).")

    # LSD onset: 0.8 +/- 0.4 h after 100 ug by mouth (Dolder 2017), not 15-30 min.
    lsd_route = _find_route(by_key["lsd"], "sublingual")
    if lsd_route is not None:
        lsd_route["duration"]["onset"] = _span(24.0, 72.0, "minutes")
        note("lsd", "Onset 24-72 min (mean +/- SD 0.8 +/- 0.4 h after 100 ug oral, Dolder 2017); was 15-30 min.")

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
