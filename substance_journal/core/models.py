from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass(frozen=True)
class DoseRange:
    min: float | None
    max: float | None


@dataclass(frozen=True)
class DurationPhase:
    phase: str  # onset, comeup, peak, offset, total, afterglow
    min_minutes: float | None
    max_minutes: float | None


@dataclass(frozen=True)
class RouteOfAdministration:
    id: int | None
    substance_key: str
    route: str
    unit: str
    dose_threshold: float | None
    dose_light: DoseRange | None
    dose_common: DoseRange | None
    dose_strong: DoseRange | None
    dose_heavy: float | None
    durations: tuple[DurationPhase, ...] = field(default_factory=tuple)

    def duration(self, phase: str) -> DurationPhase | None:
        return next((d for d in self.durations if d.phase == phase), None)


@dataclass(frozen=True)
class Substance:
    key: str
    name: str
    common_names: tuple[str, ...]
    category: str
    chemical_class: str
    summary: str | None
    wiki_url: str | None
    has_tolerance: bool
    tolerance_group: str | None
    tolerance_zero_days: float | None
    addiction_potential: str | None
    roas: tuple[RouteOfAdministration, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class Interaction:
    substance_a: str
    substance_b: str
    risk_level: str
    note: str | None


@dataclass(frozen=True)
class SubjectiveEffect:
    id: int | None
    name: str
    category: str
    subcategory: str | None
    description: str | None
    wiki_url: str | None


@dataclass(frozen=True)
class Session:
    id: int | None
    consumer: str
    started_at: datetime
    ended_at: datetime | None
    notes: str = ""


@dataclass(frozen=True)
class Ingestion:
    id: int | None
    session_id: int
    substance_key: str
    roa_id: int
    amount: float
    unit: str
    occurred_at: datetime
    consumer: str
    notes: str = ""


@dataclass(frozen=True)
class EffectLog:
    id: int | None
    session_id: int
    effect_id: int
    occurred_at: datetime
    intensity: str | None = None  # light, common, strong
    notes: str = ""


@dataclass(frozen=True)
class SubstancePreset:
    id: int | None
    substance_key: str
    roa_id: int
    name: str
    amount: float
