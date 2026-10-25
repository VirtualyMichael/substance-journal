"""Refresh data/substances.json, data/effects.json, and data/interactions.json.

Pulls substance dosing/duration/tolerance/interaction data from PsychonautWiki's
Bifrost GraphQL API (api.psychonautwiki.org) and its MediaWiki API
(psychonautwiki.org/w/api.php), plus drug-combination safety data from TripSit's
open dataset (github.com/TripSit/drugs). The app itself only ever reads the bundled
JSON files this script produces - run this manually to pull fresh data.

Usage:
    .venv/Scripts/python.exe scripts/sync_substance_data.py     (Windows)
    .venv/bin/python scripts/sync_substance_data.py             (Linux)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import requests
except ImportError:  # only needed for the network fetch, not --overrides-only
    requests = None

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from substance_journal.core.reference_overrides import apply_overrides, parse_tolerance_days  # noqa: E402

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
PW_GRAPHQL_URL = "https://api.psychonautwiki.org/"
PW_MEDIAWIKI_URL = "https://psychonautwiki.org/w/api.php"
TRIPSIT_COMBOS_URL = "https://raw.githubusercontent.com/TripSit/drugs/main/combos.json"

# (our substance key, PsychonautWiki search name, [PW route names to keep])
# Cannabis intentionally collapses flower/concentrate onto the single "smoked" PW
# route (both are combusted/vaporized THC with materially the same onset/duration) -
# the ingestion UI distinguishes flower vs. concentrate as separate presets/units on
# top of this shared reference data, not as separate PsychonautWiki routes.
TARGET_SUBSTANCES = [
    ("alcohol", "Alcohol", ["oral"]),
    ("nicotine", "Nicotine", ["smoked", "buccal", "oral"]),
    ("cannabis", "Cannabis", ["smoked", "oral"]),
    ("psilocybin_mushrooms", "Psilocybin mushrooms", ["oral"]),
    ("lsd", "LSD", ["sublingual"]),
    ("dmt", "DMT", ["smoked"]),
    ("mdma", "MDMA", ["oral"]),
    ("2c-b", "2C-B", ["oral", "insufflated"]),
    ("ketamine", "Ketamine", ["insufflated", "oral", "sublingual"]),
]

# PsychonautWiki's `crossTolerances` field is free text and is missing for a few
# substances even where real-world pharmacology is well established (e.g. 2C-B is a
# classic 5-HT2A psychedelic with the same cross-tolerance as LSD/psilocybin, same as
# every other serotonergic psychedelic). These overrides normalize/fill that field
# into the tolerance_group used for pooled tolerance modeling.
# DMT is deliberately absent (no tolerance occurs) and so is 2C-B: PsychonautWiki reports
# no cross-tolerance between 2C-B and other serotonergic psychedelics, so it keeps its
# own track (see substance_journal/core/reference_overrides.py and docs/data-audit/).
TOLERANCE_GROUP_OVERRIDES = {
    "lsd": "psychedelics",
    "psilocybin_mushrooms": "psychedelics",
}

# PsychonautWiki's `tolerance.zero` field ("how long until tolerance resets") is
# free text and, like crossTolerances, is sometimes missing even for substances with
# well-established tolerance timelines. These are conservative fallback estimates
# (in days) used only when the field can't be parsed, sourced from general
# harm-reduction consensus for each drug class.
TOLERANCE_ZERO_DAYS_OVERRIDES = {
    "2c-b": 7.0,  # same class/timeline as other serotonergic psychedelics
    "ketamine": 28.0,  # PsychonautWiki: half 14 days, baseline 28 days
}


def _parse_tolerance_zero_days(text: str | None) -> float | None:
    return parse_tolerance_days(text)


# TripSit's combo chart keys are broad substance/family slugs, not every individual
# compound - 2C-B has no dedicated entry and is approximated by the "2c-x" family
# entry (2C-series phenethylamines). Nicotine has no combo-chart entry in TripSit's
# dataset at all, so it is intentionally left out of data/interactions.json.
TRIPSIT_KEY_BY_SUBSTANCE = {
    "alcohol": "alcohol",
    "cannabis": "cannabis",
    "psilocybin_mushrooms": "mushrooms",
    "lsd": "lsd",
    "dmt": "dmt",
    "mdma": "mdma",
    "2c-b": "2c-x",
    "ketamine": "ketamine",
}

SUBSTANCE_QUERY = """
query($q: String!) {
  substances(query: $q) {
    name
    url
    commonNames
    summary
    class { chemical psychoactive }
    tolerance { full half zero }
    crossTolerances
    addictionPotential
    roas {
      name
      dose {
        units
        threshold
        light { min max }
        common { min max }
        strong { min max }
        heavy
      }
      duration {
        onset { min max units }
        comeup { min max units }
        peak { min max units }
        offset { min max units }
        total { min max units }
        afterglow { min max units }
      }
    }
    uncertainInteractions { name }
    unsafeInteractions { name }
    dangerousInteractions { name }
  }
}
"""


def fetch_substances() -> list[dict]:
    substances = []
    for key, pw_name, keep_roas in TARGET_SUBSTANCES:
        response = requests.post(
            PW_GRAPHQL_URL, json={"query": SUBSTANCE_QUERY, "variables": {"q": pw_name}}, timeout=30
        )
        response.raise_for_status()
        payload = response.json()
        matches = payload.get("data", {}).get("substances") or []
        match = next((s for s in matches if s["name"] == pw_name), matches[0] if matches else None)
        if match is None:
            raise RuntimeError(f"PsychonautWiki returned no substance for {pw_name!r}")

        tolerance_full = (match["tolerance"] or {}).get("full") or ""
        has_tolerance = "does not appear to occur" not in tolerance_full.lower()
        cross = [c.lower() for c in (match["crossTolerances"] or [])]
        tolerance_group = TOLERANCE_GROUP_OVERRIDES.get(key)
        if tolerance_group is None and cross:
            tolerance_group = cross[0]

        roas = [roa for roa in match["roas"] if roa["name"] in keep_roas and roa.get("dose")]

        tolerance_zero = (match["tolerance"] or {}).get("zero")
        tolerance_zero_days = _parse_tolerance_zero_days(tolerance_zero) or (
            TOLERANCE_ZERO_DAYS_OVERRIDES.get(key) if has_tolerance else None
        )

        substances.append(
            {
                "key": key,
                "name": match["name"],
                "common_names": match["commonNames"] or [],
                "category": ", ".join((match["class"] or {}).get("psychoactive") or []),
                "chemical_class": ", ".join((match["class"] or {}).get("chemical") or []),
                "summary": match["summary"],
                "wiki_url": match["url"],
                "has_tolerance": has_tolerance,
                "tolerance_group": tolerance_group if has_tolerance else None,
                "tolerance_full": tolerance_full or None,
                "tolerance_half": (match["tolerance"] or {}).get("half"),
                "tolerance_zero": tolerance_zero,
                "tolerance_zero_days": tolerance_zero_days,
                "addiction_potential": match["addictionPotential"],
                "roas": [
                    {
                        "route": roa["name"],
                        "unit": roa["dose"]["units"],
                        "dose_threshold": roa["dose"]["threshold"],
                        "dose_light": roa["dose"]["light"],
                        "dose_common": roa["dose"]["common"],
                        "dose_strong": roa["dose"]["strong"],
                        "dose_heavy": roa["dose"]["heavy"],
                        "duration": roa["duration"],
                    }
                    for roa in roas
                ],
                "uncertain_interactions": [i["name"] for i in match["uncertainInteractions"] or []],
                "unsafe_interactions": [i["name"] for i in match["unsafeInteractions"] or []],
                "dangerous_interactions": [i["name"] for i in match["dangerousInteractions"] or []],
            }
        )
        print(f"  fetched {pw_name} ({len(roas)} routes)")
    return substances


_H3_RE = re.compile(r'<h3 class="panel-header">\[\[([^\]|]+)\]\]')
_H4_RE = re.compile(r'media-heading">\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]')
_BULLET_RE = re.compile(r'^(\*+)\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]')
_MARKUP_RE = re.compile(r"'''|<ref>.*?</ref>")


def _parse_effect_index() -> list[dict]:
    response = requests.get(
        PW_MEDIAWIKI_URL,
        params={"action": "parse", "page": "List/effects", "prop": "wikitext", "format": "json"},
        timeout=30,
    )
    response.raise_for_status()
    wikitext = response.json()["parse"]["wikitext"]["*"]

    parts = _H3_RE.split(wikitext)
    effects = []
    for i in range(1, len(parts), 2):
        category = parts[i].strip()
        block = parts[i + 1] if i + 1 < len(parts) else ""
        subcategory = None
        for line in block.splitlines():
            h4 = _H4_RE.search(line)
            if h4:
                subcategory = _MARKUP_RE.sub("", (h4.group(2) or h4.group(1))).strip()
                continue
            bullet = _BULLET_RE.match(line.strip())
            if bullet:
                target_page = bullet.group(2).strip()
                display = _MARKUP_RE.sub("", (bullet.group(3) or target_page)).strip()
                effects.append(
                    {
                        "name": display,
                        "target_page": target_page,
                        "category": category,
                        "subcategory": subcategory,
                    }
                )
    return effects


def _fetch_descriptions(target_pages: list[str]) -> dict[str, str]:
    descriptions: dict[str, str] = {}
    batch_size = 20
    for start in range(0, len(target_pages), batch_size):
        batch = target_pages[start : start + batch_size]
        response = requests.get(
            PW_MEDIAWIKI_URL,
            params={
                "action": "query",
                "prop": "extracts",
                "exintro": 1,
                "explaintext": 1,
                "exchars": 400,
                "titles": "|".join(batch),
                "format": "json",
            },
            timeout=30,
        )
        response.raise_for_status()
        pages = response.json()["query"]["pages"]
        for page in pages.values():
            title = page.get("title")
            extract = page.get("extract")
            if title and extract:
                descriptions[title] = extract.strip()
        print(f"  fetched descriptions {start + len(batch)}/{len(target_pages)}")
    return descriptions


def fetch_effects() -> list[dict]:
    effects = _parse_effect_index()
    unique_pages = sorted({e["target_page"] for e in effects})
    descriptions = _fetch_descriptions(unique_pages)
    for effect in effects:
        effect["description"] = descriptions.get(effect["target_page"])
        effect["wiki_url"] = "https://psychonautwiki.org/wiki/" + effect["target_page"].replace(" ", "_")
    return effects


def fetch_interactions() -> list[dict]:
    response = requests.get(TRIPSIT_COMBOS_URL, timeout=30)
    response.raise_for_status()
    combos = response.json()

    interactions = []
    keys = list(TRIPSIT_KEY_BY_SUBSTANCE.items())
    seen_pairs = set()
    for substance_a, tripsit_a in keys:
        entry = combos.get(tripsit_a, {})
        for substance_b, tripsit_b in keys:
            if substance_a == substance_b:
                continue
            pair = tuple(sorted((substance_a, substance_b)))
            if pair in seen_pairs:
                continue
            combo = entry.get(tripsit_b)
            if combo is None:
                continue
            seen_pairs.add(pair)
            interactions.append(
                {
                    "substance_a": pair[0],
                    "substance_b": pair[1],
                    "risk_level": combo.get("status"),
                    "note": combo.get("note"),
                }
            )
    return interactions


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overrides-only",
        action="store_true",
        help="re-apply the audited overrides to the existing data/substances.json without fetching anything",
    )
    args = parser.parse_args()

    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if args.overrides_only:
        path = DATA_DIR / "substances.json"
        substances = apply_overrides(json.loads(path.read_text(encoding="utf-8")))
        path.write_text(json.dumps(substances, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Applied overrides to data/substances.json ({len(substances)} substances)")
        return

    print("Fetching substances from PsychonautWiki...")
    substances = apply_overrides(fetch_substances())
    (DATA_DIR / "substances.json").write_text(
        json.dumps(substances, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote data/substances.json ({len(substances)} substances)")

    print("Fetching subjective effect index from PsychonautWiki...")
    effects = fetch_effects()
    (DATA_DIR / "effects.json").write_text(
        json.dumps(effects, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote data/effects.json ({len(effects)} effects)")

    print("Fetching drug combination data from TripSit...")
    interactions = fetch_interactions()
    (DATA_DIR / "interactions.json").write_text(
        json.dumps(interactions, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote data/interactions.json ({len(interactions)} interaction pairs)")


if __name__ == "__main__":
    main()
