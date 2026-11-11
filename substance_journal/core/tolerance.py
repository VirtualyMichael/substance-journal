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


# Mirrors app/packages/sj_core/lib/src/tolerance.dart (the golden tests compare the two).
# Doses of one track less than this apart are one session.
_CLUSTER_GAP = timedelta(hours=6)
# The most one session adds (in common doses), and the ceiling tolerance can approach.
_MAX_SESSION_CONTRIBUTION = 3.0
_TOLERANCE_CEILING = 3.0


def current_tolerance_level(
    ingestions: list[Ingestion], substances_by_key: dict[str, Substance], track_key: str, at: datetime
) -> float:
    """Pooled tolerance score for track_key at `at`.

    Doses less than six hours apart form one session, which adds sqrt(number of doses) (capped at 3),
    scaled by the room left under the ceiling of 3 when it started, halving every half-life from its
    first dose. Each dose counts as one common dose here; the app also weights doses by size."""
    mine = []
    for ingestion in ingestions:
        substance = substances_by_key.get(ingestion.substance_key)
        if substance is None or not substance.has_tolerance or tolerance_track_key(substance) != track_key:
            continue
        mine.append((ingestion.occurred_at, half_life_days(substance)))
    mine.sort(key=lambda x: x[0])

    sessions: list[dict] = []
    last = None
    for occurred_at, half_life in mine:
        if last is None or occurred_at - last >= _CLUSTER_GAP:
            sessions.append({"start": occurred_at, "doses": [], "weight": 0.0, "hl_weighted": 0.0, "headroom": 1.0})
        session = sessions[-1]
        session["weight"] += 1.0
        session["hl_weighted"] += half_life
        session["doses"].append((occurred_at, session["weight"]))
        last = occurred_at

    def days(delta: timedelta) -> float:
        return delta.total_seconds() / 86400.0

    for i, session in enumerate(sessions):
        before = 0.0
        for previous in sessions[:i]:
            half_life = previous["hl_weighted"] / previous["weight"]
            before += (
                min(previous["weight"] ** 0.5, _MAX_SESSION_CONTRIBUTION)
                * previous["headroom"]
                * 2 ** (-days(session["start"] - previous["start"]) / half_life)
            )
        session["headroom"] = max(0.0, 1.0 - before / _TOLERANCE_CEILING)

    score = 0.0
    for session in sessions:
        if session["start"] > at:
            break
        weight = 0.0
        for occurred_at, cumulative in session["doses"]:
            if occurred_at > at:
                break
            weight = cumulative
        if weight <= 0:
            continue
        half_life = session["hl_weighted"] / session["weight"]
        score += (
            min(weight**0.5, _MAX_SESSION_CONTRIBUTION)
            * session["headroom"]
            * 2 ** (-days(at - session["start"]) / half_life)
        )
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
