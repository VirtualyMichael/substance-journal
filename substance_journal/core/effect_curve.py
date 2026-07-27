from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from substance_journal.core.models import Ingestion, RouteOfAdministration, Substance

# Used when a route's duration_phases data is missing/incomplete, so the timeline
# still renders a reasonable curve instead of a flat line.
_DEFAULT_ONSET_MINUTES = 15.0
_DEFAULT_COMEUP_MINUTES = 30.0
_DEFAULT_PEAK_MINUTES = 60.0
_DEFAULT_OFFSET_MINUTES = 60.0

# Caps how much a single ingestion's dose (relative to the "common" reference dose)
# can scale its peak intensity, so one heavy dose doesn't visually swamp the graph.
_MAX_DOSE_FACTOR = 3.0


def _phase_minutes(roa: RouteOfAdministration, phase: str, default: float) -> float:
    d = roa.duration(phase)
    if d is None:
        return default
    if d.max_minutes is not None:
        return d.max_minutes
    if d.min_minutes is not None:
        return d.min_minutes
    return default


def _dose_factor(ingestion: Ingestion, roa: RouteOfAdministration) -> float:
    if not roa.dose_common or not roa.dose_common.min or roa.dose_common.min <= 0:
        return 1.0
    factor = ingestion.amount / roa.dose_common.min
    return max(0.1, min(factor, _MAX_DOSE_FACTOR))


@dataclass(frozen=True)
class _IngestionCurve:
    ramp_end: datetime
    peak_end: datetime
    offset_end: datetime
    occurred_at: datetime
    peak_intensity: float

    def intensity(self, at: datetime) -> float:
        if at <= self.occurred_at:
            return 0.0
        if at <= self.ramp_end:
            span = (self.ramp_end - self.occurred_at).total_seconds()
            if span <= 0:
                return self.peak_intensity
            return self.peak_intensity * (at - self.occurred_at).total_seconds() / span
        if at <= self.peak_end:
            return self.peak_intensity
        if at <= self.offset_end:
            span = (self.offset_end - self.peak_end).total_seconds()
            if span <= 0:
                return 0.0
            remaining = (self.offset_end - at).total_seconds() / span
            return self.peak_intensity * max(remaining, 0.0)
        return 0.0


def _build_curve(ingestion: Ingestion, roa: RouteOfAdministration) -> _IngestionCurve:
    onset = _phase_minutes(roa, "onset", _DEFAULT_ONSET_MINUTES)
    comeup = _phase_minutes(roa, "comeup", _DEFAULT_COMEUP_MINUTES)
    peak = _phase_minutes(roa, "peak", _DEFAULT_PEAK_MINUTES)
    offset = _phase_minutes(roa, "offset", _DEFAULT_OFFSET_MINUTES)

    ramp_end = ingestion.occurred_at + timedelta(minutes=onset + comeup)
    peak_end = ramp_end + timedelta(minutes=peak)
    offset_end = peak_end + timedelta(minutes=offset)

    return _IngestionCurve(
        ramp_end=ramp_end,
        peak_end=peak_end,
        offset_end=offset_end,
        occurred_at=ingestion.occurred_at,
        peak_intensity=_dose_factor(ingestion, roa),
    )


def session_effect_series(
    ingestions: list[Ingestion],
    substances_by_key: dict[str, Substance],
    points_per_hour: int = 12,
) -> list[tuple[datetime, float]]:
    """Stacked intensity curve (roughly "how strong do you feel right now", summed
    across every ingestion in the session) from each ingestion's onset/comeup/peak/
    offset duration phases. This is an approximation for visualizing where you are
    in a session's timeline, not a pharmacokinetic model."""
    if not ingestions:
        return []

    curves = []
    for ingestion in ingestions:
        substance = substances_by_key.get(ingestion.substance_key)
        if substance is None:
            continue
        roa = next((r for r in substance.roas if r.id == ingestion.roa_id), None)
        if roa is None:
            continue
        curves.append(_build_curve(ingestion, roa))

    if not curves:
        return []

    start = min(c.occurred_at for c in curves)
    natural_end = max(c.offset_end for c in curves)
    now = datetime.now()
    # Extend the range a little past the curve's natural end so the "Now" marker
    # is visible while a session is still winding down - but never stretch the
    # timeline out to "today" for an old/historical session, which would squash
    # the actual curve into an invisible sliver at the left edge.
    if start <= now <= natural_end + timedelta(hours=6):
        end = max(natural_end, now)
    else:
        end = natural_end

    step = timedelta(hours=1 / points_per_hour)
    points = []
    t = start
    while t <= end:
        points.append((t, sum(c.intensity(t) for c in curves)))
        t += step
    points.append((end, sum(c.intensity(end) for c in curves)))
    return points
