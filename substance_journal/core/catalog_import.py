"""Turn PsychonautWiki API records into the app's substance JSON shape.

scripts/sync_substance_data.py --extra fetches every substance from PsychonautWiki's API and
runs each through normalize_substance(). The result (data/substances_extra.json) is the broad
catalog; the nine audited substances in data/substances.json take precedence and are never
touched by it.

Content from PsychonautWiki is available under CC BY-SA 4.0 (https://psychonautwiki.org).
"""
from __future__ import annotations

import re
from datetime import date

from substance_journal.core.reference_overrides import parse_tolerance_days

LICENSE_NOTE = "PsychonautWiki, CC BY-SA 4.0"

# The nine substances with hand-audited data (data/substances.json).
AUDITED_NAMES = {
    "alcohol", "nicotine", "cannabis", "psilocybin mushrooms", "lsd", "dmt", "mdma", "2c-b", "ketamine",
}

# PsychonautWiki cross-tolerance labels are free text; fold the common spellings into one group
# so substances that really cross-tolerate share a tolerance track.
_CROSS_TOLERANCE_GROUPS = {
    "psychedelic": "psychedelics",
    "psychedelics": "psychedelics",
    "stimulant": "stimulants",
    "stimulants": "stimulants",
    "dopamine": "dopaminergic",
    "dopaminergic": "dopaminergic",
    "dissociative": "dissociative",
    "dissociatives": "dissociative",
    "opioids": "opioids",
    "opioid": "opioids",
    "benzodiazepines": "benzodiazepines",
    "benzodiazepine": "benzodiazepines",
    "thienodiazepine": "benzodiazepines",
    "gaba": "gaba",
    "gabaergic": "gaba",
    "depressants": "gaba",
    "cannabinoids": "cannabinoids",
    "nootropic": "nootropic",
    "nootropics": "nootropic",
    "racetam": "racetam",
    "serotonin": "serotonergic",
    "serotonergic": "serotonergic",
    "deliriant": "deliriant",
    "entactogens": "entactogens",
}

_UNIT_FIXES = {"μg": "µg", "ug": "µg", "mL": "ml", "ML": "ml"}

_SLUG_RE = re.compile(r"[^a-z0-9_-]+")


def slugify(name: str) -> str:
    """Stable key for a substance name. The nine audited substances keep the keys they already
    have ("2C-B" is "2c-b", "Psilocybin mushrooms" is "psilocybin_mushrooms")."""
    key = _SLUG_RE.sub("_", name.strip().lower().replace(" ", "_"))
    return re.sub(r"_+", "_", key).strip("_")


def normalize_unit(unit: str | None) -> str:
    if not unit:
        return ""
    unit = unit.strip()
    if unit.startswith("mg/kg"):
        return "mg/kg"
    return _UNIT_FIXES.get(unit, unit)


def cross_tolerance_group(cross: list[str] | None) -> str | None:
    for label in cross or []:
        for part in re.split(r"[|,]", label):
            group = _CROSS_TOLERANCE_GROUPS.get(part.strip().lower())
            if group:
                return group
    return None


def _clean_range(value: dict | None) -> dict | None:
    if not value:
        return None
    lo, hi = value.get("min"), value.get("max")
    if lo is None and hi is None:
        return None
    if lo is not None and hi is not None and lo > hi:
        lo, hi = hi, lo  # the wiki has the odd transposed range (HXE insufflated light: 40-20)
    return {"min": lo, "max": hi}


def _normalize_route(raw: dict) -> dict | None:
    dose = raw.get("dose") or {}
    duration = raw.get("duration") or {}
    route = {
        "route": raw["name"],
        "unit": normalize_unit(dose.get("units")),
        "dose_threshold": dose.get("threshold"),
        "dose_light": _clean_range(dose.get("light")),
        "dose_common": _clean_range(dose.get("common")),
        "dose_strong": _clean_range(dose.get("strong")),
        "dose_heavy": dose.get("heavy"),
        "duration": {
            phase: (
                {"min": span.get("min"), "max": span.get("max"), "units": span.get("units")}
                if (span := duration.get(phase)) and (span.get("min") is not None or span.get("max") is not None)
                else None
            )
            for phase in ("onset", "comeup", "peak", "offset", "total", "afterglow")
        },
    }
    has_dose = any(
        route[k] is not None
        for k in ("dose_threshold", "dose_light", "dose_common", "dose_strong", "dose_heavy")
    )
    has_duration = any(v for v in route["duration"].values())
    return route if has_dose or has_duration else None


def _names(items: list[dict] | None) -> list[str]:
    return [i["name"] for i in items or [] if i.get("name")]


def normalize_substance(raw: dict, fetched: date | None = None) -> dict | None:
    """One PsychonautWiki API record in the app's shape, or None if it has nothing loggable
    (class pages such as "2C-x", or plants without dosing). Never raises on missing fields."""
    name = (raw.get("name") or "").strip()
    if not name:
        return None
    routes = [r for r in (_normalize_route(x) for x in raw.get("roas") or []) if r]
    if not routes:
        return None

    tolerance = raw.get("tolerance") or {}
    full, half, zero = tolerance.get("full"), tolerance.get("half"), tolerance.get("zero")
    texts = " ".join(t for t in (full, half, zero) if t)
    has_tolerance = bool(texts) and "does not appear to occur" not in texts.lower()
    klass = raw.get("class") or {}
    summary = (raw.get("summary") or "").strip()
    if summary.startswith("Summary sheet"):
        summary = ""  # PsychonautWiki's placeholder; the app shows the substance class instead

    return {
        "key": slugify(name),
        "name": name,
        "common_names": [n for n in raw.get("commonNames") or [] if n],
        "category": ", ".join(klass.get("psychoactive") or []),
        "chemical_class": ", ".join(klass.get("chemical") or []),
        "summary": summary,
        "wiki_url": raw.get("url"),
        "has_tolerance": has_tolerance,
        "tolerance_group": cross_tolerance_group(raw.get("crossTolerances")) if has_tolerance else None,
        "tolerance_full": full,
        "tolerance_half": half,
        "tolerance_zero": zero,
        "tolerance_zero_days": parse_tolerance_days(zero) if has_tolerance else None,
        "tolerance_half_days": parse_tolerance_days(half) if has_tolerance else None,
        "addiction_potential": raw.get("addictionPotential"),
        "roas": routes,
        "dangerous_interactions": _names(raw.get("dangerousInteractions")),
        "unsafe_interactions": _names(raw.get("unsafeInteractions")),
        "uncertain_interactions": _names(raw.get("uncertainInteractions")),
        "audited": False,
        "sources": [raw.get("url") or "https://psychonautwiki.org"],
        "safety_notes": [
            "Copied from PsychonautWiki and not independently checked. Compare with the wiki page and other sources before relying on it."
        ],
        "license": LICENSE_NOTE,
        "fetched": (fetched or date.today()).isoformat(),
    }


def build_extra_catalog(raw_substances: list[dict], fetched: date | None = None) -> list[dict]:
    """Normalize every record except the audited nine, sorted by name, with unique keys."""
    result: list[dict] = []
    seen: set[str] = set()
    for raw in sorted(raw_substances, key=lambda r: (r.get("name") or "").lower()):
        if (raw.get("name") or "").strip().lower() in AUDITED_NAMES:
            continue
        item = normalize_substance(raw, fetched)
        if item is None:
            continue
        key = item["key"]
        suffix = 2
        while key in seen:  # two names that slugify the same
            key = f"{item['key']}_{suffix}"
            suffix += 1
        item["key"] = key
        seen.add(key)
        result.append(item)
    return result
