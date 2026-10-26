"""Export golden vectors from Alcohol Tracker's Python estimation model.

app/packages/sj_core/lib/src/alcohol.dart is a port of alcohol_tracker/core/calculations.py.
This script runs the original Python code on fixed scenarios and writes inputs and outputs to
app/packages/sj_core/test/golden/alcohol.json, which the Dart tests must reproduce.

    python scripts/export_alcohol_golden.py [path/to/Alcohol-Tracker-checkout]

The Alcohol Tracker checkout defaults to the sibling folder "Alcohol ingestion marking app".
PySide6 is stubbed because the model only needs it for saving settings, not for the maths.
"""
from __future__ import annotations

import json
import sys
import types
from dataclasses import asdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TRACKER = ROOT.parent / "Alcohol ingestion marking app"
OUT = ROOT / "app" / "packages" / "sj_core" / "test" / "golden" / "alcohol.json"


def _stub_pyside() -> None:
    for name in ("PySide6", "PySide6.QtCore", "PySide6.QtGui"):
        module = types.ModuleType(name)
        module.QSettings = object
        module.QColor = object
        sys.modules[name] = module


def main() -> None:
    tracker = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACKER
    if not (tracker / "alcohol_tracker" / "core" / "calculations.py").exists():
        raise SystemExit(f"Alcohol Tracker checkout not found at {tracker}")
    _stub_pyside()
    sys.path.insert(0, str(tracker))

    from alcohol_tracker.core import calculations as calc
    from alcohol_tracker.core.settings import EstimateSettings

    t0 = datetime(2026, 7, 3, 20, 0, 0)

    def drink(minutes: float, amount: float, unit: str, abv: float, duration: float = 0.0, label: str = "d") -> calc.Ingestion:
        return calc.Ingestion(
            id=None,
            occurred_at=t0 + timedelta(minutes=minutes),
            amount=amount,
            unit=unit,
            abv_percent=abv,
            label=label,
            duration_minutes=duration,
        )

    scenarios = {
        "empty": [],
        "one_shot": [drink(0, 1, "shots", 40)],
        "sipped_beers": [drink(0, 12, "oz", 5, 45), drink(50, 12, "oz", 5, 60)],
        "night_out": [
            drink(0, 1, "shots", 40),
            drink(25, 12, "oz", 5, 30),
            drink(70, 2, "shots", 40),
            drink(130, 5, "oz", 12, 20),
            drink(180, 12, "oz", 5, 40),
            drink(240, 1.5, "shots", 40),
            drink(300, 16, "oz", 6, 60),
            drink(330, 1, "shots", 40),
        ],
        "three_nights": [
            drink(0, 1, "shots", 40),
            drink(30, 12, "oz", 5, 30),
            drink(60, 12, "oz", 5, 30),
            drink(100, 1.5, "shots", 40),
            drink(5 * 24 * 60, 12, "oz", 5, 30),
            drink(5 * 24 * 60 + 40, 2, "shots", 40),
            drink(12 * 24 * 60, 1, "shots", 40),
            drink(12 * 24 * 60 + 20, 12, "oz", 7, 30),
            drink(12 * 24 * 60 + 60, 3, "shots", 40),
            drink(12 * 24 * 60 + 90, 12, "oz", 5, 30),
            drink(12 * 24 * 60 + 150, 2, "shots", 40),
            drink(12 * 24 * 60 + 200, 12, "oz", 5, 30),
        ],
    }

    settings_variants = {
        "default": EstimateSettings(),
        "female_widmark": EstimateSettings(user_gender="F", bac_model="widmark", user_weight_lbs=130.0),
        "tall_heavy": EstimateSettings(user_weight_lbs=220.0, user_height_cm=190.0, user_age_years=45.0),
        "other_gender_fast": EstimateSettings(
            user_gender="X",
            absorption_minutes=20,
            absorption_lag_minutes=5.0,
            elimination_standard_drinks_per_hour=1.0,
        ),
        "tuned_tolerance": EstimateSettings(
            tolerance_half_life_days=3.0,
            tolerance_max_extra_dose=1.5,
            tolerance_half_saturation_exposure=1.0,
            standard_drink_volume_oz=1.5,
            standard_drink_abv_percent=40.0,
        ),
    }

    def iso(t: datetime | None) -> str | None:
        return t.isoformat() if t else None

    cases = []
    for sname, settings in settings_variants.items():
        for gname, ingestions in scenarios.items():
            case: dict = {"settings": sname, "scenario": gname}
            case["standard_drinks"] = [i.standard_drinks(settings) for i in ingestions]
            case["pure_grams"] = [i.pure_alcohol_grams(settings) for i in ingestions]

            series = calc.effect_series(ingestions, t0, settings)
            case["effect_series"] = [[iso(t), v] for t, v in series]
            peak_t, peak_v = calc.peak_value(series)
            case["peak"] = [iso(peak_t), peak_v]
            case["clear_time"] = iso(calc.estimated_clear_time([(t, calc.estimate_bac(v, settings)) for t, v in series]))

            probes = [t0 + timedelta(minutes=m) for m in (10, 40, 95, 200, 400, 800)]
            case["probes"] = [
                {
                    "at": iso(p),
                    "active": calc.estimate_active_standard_drinks(ingestions, p, settings),
                    "unabsorbed": calc.estimate_unabsorbed_standard_drinks(ingestions, p, settings),
                    "in_body": calc.estimate_alcohol_in_body(ingestions, p, settings),
                }
                for p in probes
            ]

            sessions = calc.group_into_sessions(ingestions, settings)
            order = {id(item): n for n, item in enumerate(ingestions)}
            case["sessions"] = [[order[id(item)] for item in session] for session in sessions]
            case["exposures"] = []
            for session in sessions:
                e = calc.session_exposure(session, settings)
                case["exposures"].append(
                    {"start": iso(e.start), "peak_bac": e.peak_bac, "peak_at": iso(e.peak_at), "exposure": e.exposure_bac_hours}
                )

            loads = calc.daily_tolerance_load(ingestions, settings)
            case["daily_load"] = [[iso(d), v] for d, v in loads.items()]
            end_day = (max((i.occurred_at for i in ingestions), default=t0) + timedelta(days=2)).replace(hour=0, minute=0)
            case["tolerance_end_day"] = iso(end_day)
            tol = calc.tolerance_series(loads, end_day, settings)
            case["tolerance_series"] = [[iso(t), v] for t, v in tol]
            case["multiplier_series"] = [[iso(t), v] for t, v in calc.tolerance_multiplier_series(loads, end_day, settings)]
            cases.append(case)

    body = {}
    for sname, settings in settings_variants.items():
        body[sname] = {
            "settings": asdict(settings),
            "total_body_water": calc.total_body_water_litres(settings),
            "distribution_ratio": calc.body_water_distribution_ratio(settings),
            "bac": {str(d): calc.estimate_bac(d, settings) for d in (0.0, 0.5, 1.0, 3.5, 8.0, 12.0)},
            "multiplier": {str(s): calc.tolerance_multiplier(s, settings) for s in (0.0, 0.5, 3.0, 20.0)},
        }

    scenario_inputs = {
        gname: [
            {
                "at": iso(i.occurred_at),
                "amount": i.amount,
                "unit": i.unit,
                "abv": i.abv_percent,
                "duration": i.duration_minutes,
            }
            for i in items
        ]
        for gname, items in scenarios.items()
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps({"t0": iso(t0), "scenarios": scenario_inputs, "body": body, "cases": cases}),
        encoding="utf-8",
    )
    print(f"Wrote {OUT} ({len(cases)} cases, {OUT.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
