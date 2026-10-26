"""Export golden vectors for the generic effect timeline (core/effect_curve.py).

The Dart port in app/packages/sj_core/lib/src/effect_curve.dart must reproduce these series
(with its route-specific cannabis model switched off). Re-run after changing effect_curve.py
or the reference data:

    python scripts/export_effect_golden.py
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

from substance_journal.core import effect_curve  # noqa: E402
from substance_journal.core.database import Store  # noqa: E402
from substance_journal.core.models import Ingestion  # noqa: E402

OUT = ROOT / "app" / "packages" / "sj_core" / "test" / "golden" / "effect_curve.json"
T0 = datetime(2026, 7, 3, 20, 0, 0)

# (substance, route, amount, minutes after T0)
SCENARIOS = {
    "lsd": [("lsd", "sublingual", 100, 0)],
    "lsd_heavy_is_capped": [("lsd", "sublingual", 1000, 0)],
    "lsd_tiny_is_floored": [("lsd", "sublingual", 1, 0)],
    "mdma": [("mdma", "oral", 100, 0)],
    "mdma_redose": [("mdma", "oral", 80, 0), ("mdma", "oral", 40, 120)],
    "ketamine_insufflated": [("ketamine", "insufflated", 50, 0)],
    "ketamine_oral": [("ketamine", "oral", 200, 0)],
    "dmt": [("dmt", "smoked", 30, 0)],
    "two_cb_oral": [("2c-b", "oral", 20, 0)],
    "nicotine_smoked": [("nicotine", "smoked", 1, 0)],
    "alcohol": [("alcohol", "oral", 25, 0), ("alcohol", "oral", 25, 90)],
    "cannabis_smoked_generic": [("cannabis", "smoked", 3, 0)],
    "cannabis_oral_generic": [("cannabis", "oral", 10, 0)],
    "cannabis_sublingual_no_bands": [("cannabis", "sublingual", 5, 0)],
    "mixed_session": [("mdma", "oral", 100, 0), ("alcohol", "oral", 25, 60), ("nicotine", "smoked", 1, 90)],
}
# Where "now" falls relative to the first dose.
NOW_OFFSETS_MINUTES = {"during": 60, "after_end": 60 * 24 * 10, "before_start": -120}


def main() -> None:
    db = Path(tempfile.gettempdir()) / f"effect_golden_{os.getpid()}.db"
    store = Store(db)
    try:
        by_key = {s.key: s for s in store.list_substances()}
    finally:
        pass

    cases = []
    try:
        for name, doses in SCENARIOS.items():
            ingestions = []
            for key, route, amount, minutes in doses:
                roa = next(r for r in by_key[key].roas if r.route == route)
                ingestions.append(
                    Ingestion(
                        id=None,
                        session_id=1,
                        substance_key=key,
                        roa_id=roa.id,
                        amount=amount,
                        unit=roa.unit,
                        occurred_at=T0 + timedelta(minutes=minutes),
                        consumer="Me",
                    )
                )
            for label, offset in NOW_OFFSETS_MINUTES.items():
                fixed = T0 + timedelta(minutes=offset)

                class FixedNow(datetime):
                    @classmethod
                    def now(cls, tz=None, _fixed=fixed):
                        return _fixed

                original = effect_curve.datetime
                effect_curve.datetime = FixedNow
                try:
                    series = effect_curve.session_effect_series(ingestions, by_key)
                finally:
                    effect_curve.datetime = original
                cases.append(
                    {
                        "name": name,
                        "now_label": label,
                        "now": fixed.isoformat(),
                        "doses": [
                            {"substance": k, "roa": f"{k}:{r}", "amount": a, "at": (T0 + timedelta(minutes=m)).isoformat()}
                            for k, r, a, m in doses
                        ],
                        "series": [[t.isoformat(), v] for t, v in series],
                    }
                )
    finally:
        if db.exists():
            db.unlink()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"cases": cases}), encoding="utf-8")
    print(f"Wrote {OUT} ({len(cases)} cases, {OUT.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
