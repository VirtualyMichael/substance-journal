"""Export golden test vectors from the Python reference implementation.

The Dart port in app/packages/sj_core must reproduce these numbers, which is how we prove
the rewrite did not change behaviour. Re-run after changing core/tolerance.py or the data:

    python scripts/export_golden.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from substance_journal.core.database import Store  # noqa: E402
from substance_journal.core.models import Ingestion  # noqa: E402
from substance_journal.core.tolerance import (  # noqa: E402
    current_tolerance_level,
    half_life_days,
    tolerance_track_key,
)

OUT = ROOT / "app" / "packages" / "sj_core" / "test" / "golden"
BASE = datetime(2026, 7, 1, 20, 0, 0)

SCENARIOS = {
    "single_lsd": [("lsd", 0)],
    "lsd_then_psilocybin": [("lsd", 0), ("psilocybin_mushrooms", 36)],
    "daily_cannabis_week": [("cannabis", h) for h in range(0, 24 * 7, 24)],
    "ketamine_twice": [("ketamine", 0), ("ketamine", 24 * 3)],
    "mdma_and_alcohol": [("mdma", 0), ("alcohol", 5), ("alcohol", 30)],
    "two_cb_and_lsd": [("2c-b", 0), ("lsd", 1)],
    "dmt_only": [("dmt", 0)],
}
OFFSET_HOURS = [0.02, 1, 12, 24, 72, 24 * 7, 24 * 14, 24 * 28, 24 * 60]


def main() -> None:
    db = Path(tempfile.gettempdir()) / f"golden_{os.getpid()}.db"
    store = Store(db)
    try:
        substances = store.list_substances()
        by_key = {s.key: s for s in substances}

        half_lives = {s.key: half_life_days(s) for s in substances if s.has_tolerance}
        tracks = {s.key: tolerance_track_key(s) for s in substances if s.has_tolerance}
        cases = []
        for name, events in SCENARIOS.items():
            ingestions = [
                Ingestion(
                    id=None,
                    session_id=1,
                    substance_key=key,
                    roa_id=by_key[key].roas[0].id,
                    amount=1,
                    unit=by_key[key].roas[0].unit,
                    occurred_at=BASE + timedelta(hours=h),
                    consumer="Me",
                )
                for key, h in events
            ]
            track_keys = sorted({tolerance_track_key(by_key[k]) for k, _ in events if by_key[k].has_tolerance})
            samples = []
            for offset in OFFSET_HOURS:
                at = BASE + timedelta(hours=offset)
                samples.append(
                    {
                        "at": at.isoformat(),
                        "levels": {t: current_tolerance_level(ingestions, by_key, t, at) for t in track_keys},
                    }
                )
            cases.append(
                {
                    "name": name,
                    "events": [{"substance": k, "at": (BASE + timedelta(hours=h)).isoformat()} for k, h in events],
                    "samples": samples,
                }
            )
    finally:
        if db.exists():
            db.unlink()

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "tolerance.json").write_text(
        json.dumps({"half_life_days": half_lives, "tracks": tracks, "cases": cases}, indent=2),
        encoding="utf-8",
    )
    print(f"Wrote {OUT / 'tolerance.json'} ({len(cases)} scenarios)")


if __name__ == "__main__":
    main()
