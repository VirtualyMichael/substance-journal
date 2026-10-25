from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from substance_journal.core.models import Ingestion, Substance

# Used only when a substance has tolerance but PsychonautWiki (and our manual
# overrides in scripts/sync_substance_data.py) have no zero-tolerance timeline data.
_DEFAULT_HALF_LIFE_DAYS = 3.0


def tolerance_track_key(substance: Substance) -> str:
    """Substances sharing a tolerance_group (e.g. LSD/Psilocybin/2C-B all share
    "psychedelics" 5-HT2A cross-tolerance) contribute to one pooled track; substances
    without a group get their own track keyed by substance key."""
    return substance.tolerance_group or substance.key


def half_life_days(substance: Substance) -> float:
    """Decay half-life in days. PsychonautWiki's published "half tolerance" time is used
    directly when it exists. Otherwise the "time to zero tolerance" estimate is treated
    as ~4 half-lives (93.75% decayed), a rule of thumb for an exponential decay curve
    reaching "back to baseline" by that point."""
    if substance.tolerance_half_days:
        return max(substance.tolerance_half_days, 0.25)
    if substance.tolerance_zero_days:
        return max(substance.tolerance_zero_days / 4.0, 0.25)
    return _DEFAULT_HALF_LIFE_DAYS


def tolerance_tracks(substances: list[Substance]) -> dict[str, list[Substance]]:
    tracks: dict[str, list[Substance]] = {}
    for substance in substances:
        if not substance.has_tolerance:
            continue
        tracks.setdefault(tolerance_track_key(substance), []).append(substance)
    return tracks


@dataclass(frozen=True)
class TolerancePoint:
    at: datetime
    value: float


def current_tolerance_level(
    ingestions: list[Ingestion], substances_by_key: dict[str, Substance], track_key: str, at: datetime
) -> float:
    score = 0.0
    for ingestion in ingestions:
        substance = substances_by_key.get(ingestion.substance_key)
        if substance is None or not substance.has_tolerance:
            continue
        if tolerance_track_key(substance) != track_key:
            continue
        if ingestion.occurred_at > at:
            continue
        elapsed_days = (at - ingestion.occurred_at).total_seconds() / 86400.0
        score += 2 ** (-elapsed_days / half_life_days(substance))
    return score


def tolerance_series(
    ingestions: list[Ingestion],
    substances_by_key: dict[str, Substance],
    track_key: str,
    end: datetime,
    days_back: int = 30,
    points_per_day: int = 4,
) -> list[TolerancePoint]:
    start = end - timedelta(days=days_back)
    step = timedelta(days=1 / points_per_day)
    points = []
    t = start
    while t <= end:
        points.append(TolerancePoint(at=t, value=current_tolerance_level(ingestions, substances_by_key, track_key, t)))
        t += step
    # The fixed step above won't generally land exactly on `end` (e.g. every 6
    # hours from `start` may fall short of "now" by up to 6 hours) - always add an
    # exact point at `end` so a graph ending "now" actually has a point there for
    # the Now marker to align with, instead of silently not drawing it.
    if not points or points[-1].at < end:
        points.append(TolerancePoint(at=end, value=current_tolerance_level(ingestions, substances_by_key, track_key, end)))
    return points
