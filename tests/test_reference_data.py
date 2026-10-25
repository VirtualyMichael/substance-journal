import os
import sqlite3
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

from substance_journal.core.reference_data import load_interactions, load_substances
from substance_journal.core.reference_overrides import apply_overrides, parse_tolerance_days

_PHASES = ("onset", "comeup", "peak", "offset", "total", "afterglow")
_UNIT_MINUTES = {"seconds": 1 / 60, "minutes": 1.0, "hours": 60.0}
_TIERS = ("dangerous", "unsafe", "uncertain")


def _minutes(span: dict | None) -> tuple[float, float] | None:
    if not span or span.get("min") is None or span.get("max") is None:
        return None
    factor = _UNIT_MINUTES[span["units"]]
    return span["min"] * factor, span["max"] * factor


class ReferenceDataConsistencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.substances = load_substances()
        self.by_key = {s["key"]: s for s in self.substances}

    def test_dose_bands_are_ordered(self) -> None:
        for s in self.substances:
            for roa in s["roas"]:
                where = f"{s['key']}:{roa['route']}"
                previous_max = None
                for band in ("dose_light", "dose_common", "dose_strong"):
                    rng = roa[band]
                    if not rng:
                        continue
                    self.assertLessEqual(rng["min"], rng["max"], f"{where} {band}")
                    if previous_max is not None:
                        self.assertGreaterEqual(rng["min"], previous_max - 1e-9, f"{where} {band} overlaps previous band")
                    previous_max = rng["max"]
                if roa["dose_heavy"] is not None and previous_max is not None:
                    self.assertGreaterEqual(roa["dose_heavy"], previous_max - 1e-9, where)

    def test_durations_have_sane_ranges(self) -> None:
        for s in self.substances:
            for roa in s["roas"]:
                where = f"{s['key']}:{roa['route']}"
                for phase in _PHASES:
                    span = _minutes(roa["duration"].get(phase))
                    if span:
                        self.assertLessEqual(span[0], span[1], f"{where} {phase}")
                total = _minutes(roa["duration"].get("total"))
                onset = _minutes(roa["duration"].get("onset"))
                if total and onset:
                    self.assertLess(onset[0], total[1], f"{where} onset vs total")

    def test_no_placeholder_or_empty_summaries(self) -> None:
        for s in self.substances:
            self.assertTrue(s["summary"], s["key"])
            self.assertNotIn("Summary sheet", s["summary"], s["key"])
            self.assertGreater(len(s["summary"]), 60, s["key"])

    def test_every_substance_has_a_category_and_sources(self) -> None:
        for s in self.substances:
            self.assertTrue(s["category"], s["key"])
            self.assertTrue(any("psychonautwiki.org" in url for url in s["sources"]), s["key"])
            self.assertTrue(s["safety_notes"], s["key"])

    def test_tolerance_half_never_exceeds_zero(self) -> None:
        for s in self.substances:
            half, zero = s["tolerance_half_days"], s["tolerance_zero_days"]
            if half is not None and zero is not None:
                self.assertLessEqual(half, zero, s["key"])
            if not s["has_tolerance"]:
                self.assertIsNone(half, s["key"])

    def test_interaction_tiers_do_not_overlap(self) -> None:
        for s in self.substances:
            seen: dict[str, str] = {}
            for tier in _TIERS:
                for name in s[f"{tier}_interactions"]:
                    self.assertNotIn(name, seen, f"{s['key']}: {name} in {seen.get(name)} and {tier}")
                    seen[name] = tier

    def test_lithium_is_dangerous_for_every_psychedelic(self) -> None:
        for key in ("lsd", "dmt", "2c-b", "psilocybin_mushrooms"):
            self.assertIn("Lithium", self.by_key[key]["dangerous_interactions"], key)

    def test_interactions_use_known_substances_and_each_pair_once(self) -> None:
        pairs = set()
        for i in load_interactions():
            self.assertIn(i["substance_a"], self.by_key)
            self.assertIn(i["substance_b"], self.by_key)
            pair = frozenset((i["substance_a"], i["substance_b"]))
            self.assertNotIn(pair, pairs)
            pairs.add(pair)


class AuditedValueTests(unittest.TestCase):
    def setUp(self) -> None:
        self.by_key = {s["key"]: s for s in load_substances()}

    def route(self, key: str, route: str) -> dict:
        return next(r for r in self.by_key[key]["roas"] if r["route"] == route)

    def test_ketamine_tolerance_matches_psychonautwiki(self) -> None:
        ketamine = self.by_key["ketamine"]
        self.assertEqual(ketamine["tolerance_half_days"], 14.0)
        self.assertEqual(ketamine["tolerance_zero_days"], 28.0)

    def test_published_half_times_are_parsed(self) -> None:
        self.assertEqual(self.by_key["alcohol"]["tolerance_half_days"], 5.0)
        self.assertEqual(self.by_key["cannabis"]["tolerance_half_days"], 10.5)
        self.assertEqual(self.by_key["mdma"]["tolerance_half_days"], 30.0)
        self.assertEqual(parse_tolerance_days("3 - 7 days"), 5.0)
        self.assertEqual(parse_tolerance_days("2.5 months"), 75.0)
        self.assertIsNone(parse_tolerance_days(None))

    def test_two_cb_has_its_own_tolerance_track(self) -> None:
        self.assertIsNone(self.by_key["2c-b"]["tolerance_group"])
        self.assertTrue(self.by_key["2c-b"]["has_tolerance"])
        self.assertIsNone(self.by_key["dmt"]["tolerance_group"])

    def test_ketamine_oral_active_effects_are_short(self) -> None:
        duration = self.route("ketamine", "oral")["duration"]
        self.assertLessEqual(_minutes(duration["offset"])[1], 120)
        self.assertLessEqual(_minutes(duration["total"])[1], 180)

    def test_nicotine_smoked_active_effect_is_minutes_not_hours(self) -> None:
        duration = self.route("nicotine", "smoked")["duration"]
        self.assertEqual(_minutes(duration["total"]), (10.0, 30.0))
        self.assertGreaterEqual(_minutes(duration["afterglow"])[0], 60)

    def test_cannabis_has_sublingual_and_wider_oral_timing(self) -> None:
        routes = {r["route"] for r in self.by_key["cannabis"]["roas"]}
        self.assertEqual(routes, {"oral", "smoked", "sublingual"})
        oral = self.route("cannabis", "oral")["duration"]
        self.assertEqual(_minutes(oral["onset"]), (20.0, 120.0))
        self.assertEqual(_minutes(oral["peak"]), (60.0, 180.0))

    def test_widened_onsets(self) -> None:
        self.assertEqual(_minutes(self.route("mdma", "oral")["duration"]["onset"]), (20.0, 70.0))
        self.assertEqual(_minutes(self.route("dmt", "smoked")["duration"]["onset"]), (0.25, 1.0))
        self.assertEqual(_minutes(self.route("ketamine", "insufflated")["duration"]["onset"]), (1.0, 15.0))

    def test_raised_interaction_tiers(self) -> None:
        mdma = self.by_key["mdma"]
        for name in ("Protease Inhibitors", "GHB", "GBL"):
            self.assertIn(name, mdma["unsafe_interactions"])
        self.assertIn("Benzodiazepines", self.by_key["ketamine"]["unsafe_interactions"])
        self.assertIn("MAOIs", self.by_key["dmt"]["unsafe_interactions"])

    def test_alcohol_dose_bands_match_psychonautwiki(self) -> None:
        oral = self.route("alcohol", "oral")
        self.assertEqual(oral["unit"], "g")
        self.assertEqual((oral["dose_common"]["min"], oral["dose_common"]["max"]), (20.0, 30.0))


class OverrideFunctionTests(unittest.TestCase):
    def test_apply_overrides_is_idempotent(self) -> None:
        once = apply_overrides(load_substances())
        self.assertEqual(once, apply_overrides(once))

    def test_bundled_data_already_has_overrides_applied(self) -> None:
        self.assertEqual(apply_overrides(load_substances()), load_substances())

    def test_apply_overrides_does_not_mutate_its_input(self) -> None:
        original = load_substances()
        before = repr(original)
        apply_overrides(original)
        self.assertEqual(before, repr(original))


class ToleranceHalfLifeTests(unittest.TestCase):
    def setUp(self) -> None:
        from substance_journal.core.database import Store

        self.db_path = Path(tempfile.gettempdir()) / f"substance_journal_ref_{os.getpid()}_{id(self)}.db"
        if self.db_path.exists():
            self.db_path.unlink()
        self.store = Store(self.db_path)
        self.by_key = {s.key: s for s in self.store.list_substances()}

    def tearDown(self) -> None:
        if self.db_path.exists():
            self.db_path.unlink()

    def test_half_life_uses_published_half_time(self) -> None:
        from substance_journal.core.tolerance import half_life_days

        self.assertEqual(half_life_days(self.by_key["ketamine"]), 14.0)
        self.assertEqual(half_life_days(self.by_key["mdma"]), 30.0)
        self.assertEqual(half_life_days(self.by_key["alcohol"]), 5.0)

    def test_half_life_falls_back_to_zero_over_four(self) -> None:
        from substance_journal.core.tolerance import half_life_days

        lsd = self.by_key["lsd"]
        self.assertIsNone(lsd.tolerance_half_days)
        self.assertEqual(half_life_days(lsd), lsd.tolerance_zero_days / 4.0)

    def test_ketamine_tolerance_halves_after_14_days(self) -> None:
        from substance_journal.core.models import Ingestion
        from substance_journal.core.tolerance import current_tolerance_level

        ketamine = self.by_key["ketamine"]
        at = datetime(2026, 7, 1, 20, 0, 0)
        ingestions = [
            Ingestion(
                id=None, session_id=1, substance_key="ketamine", roa_id=ketamine.roas[0].id,
                amount=50, unit=ketamine.roas[0].unit, occurred_at=at, consumer="Me",
            )
        ]
        level = current_tolerance_level(ingestions, self.by_key, "dissociative", at + timedelta(days=14))
        self.assertAlmostEqual(level, 0.5, places=2)

    def test_store_exposes_sources_and_safety_notes(self) -> None:
        cannabis = self.by_key["cannabis"]
        self.assertTrue(any("psychonautwiki.org" in u for u in cannabis.sources))
        self.assertTrue(cannabis.safety_notes)
        self.assertEqual({r.route for r in cannabis.roas}, {"oral", "smoked", "sublingual"})
        sublingual = next(r for r in cannabis.roas if r.route == "sublingual")
        self.assertIsNone(sublingual.dose_common)
        self.assertIsNotNone(sublingual.duration("onset"))

    def test_existing_database_without_new_columns_is_upgraded(self) -> None:
        from substance_journal.core.database import Store

        legacy = Path(tempfile.gettempdir()) / f"substance_journal_legacy_{os.getpid()}_{id(self)}.db"
        if legacy.exists():
            legacy.unlink()
        connection = sqlite3.connect(legacy)
        connection.executescript(
            """
            CREATE TABLE substances (
                key TEXT PRIMARY KEY, name TEXT NOT NULL, common_names TEXT NOT NULL,
                category TEXT NOT NULL, chemical_class TEXT NOT NULL, summary TEXT, wiki_url TEXT,
                has_tolerance INTEGER NOT NULL, tolerance_group TEXT, tolerance_zero_days REAL,
                addiction_potential TEXT
            );
            """
        )
        connection.commit()
        connection.close()
        try:
            store = Store(legacy)
            self.assertEqual(len(store.list_substances()), 9)
            self.assertEqual(store.get_substance("ketamine").tolerance_half_days, 14.0)
        finally:
            if legacy.exists():
                legacy.unlink()


if __name__ == "__main__":
    unittest.main()
