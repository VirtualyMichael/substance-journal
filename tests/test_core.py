import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path


class ScaffoldTests(unittest.TestCase):
    def test_package_imports(self) -> None:
        from substance_journal.core.paths import default_db_path

        path = default_db_path()
        self.assertTrue(str(path).endswith("substance_journal.db"))


class ReferenceDataTests(unittest.TestCase):
    def test_load_substances_covers_all_nine_target_substances(self) -> None:
        from substance_journal.core.reference_data import load_substances

        substances = load_substances()
        keys = {s["key"] for s in substances}
        self.assertEqual(
            keys,
            {
                "alcohol",
                "nicotine",
                "cannabis",
                "psilocybin_mushrooms",
                "lsd",
                "dmt",
                "mdma",
                "2c-b",
                "ketamine",
            },
        )
        for substance in substances:
            self.assertTrue(substance["roas"], f"{substance['key']} has no routes of administration")

    def test_dmt_has_no_tolerance(self) -> None:
        from substance_journal.core.reference_data import load_substances

        dmt = next(s for s in load_substances() if s["key"] == "dmt")
        self.assertFalse(dmt["has_tolerance"])

    def test_psychedelics_share_a_tolerance_group(self) -> None:
        from substance_journal.core.reference_data import load_substances

        by_key = {s["key"]: s for s in load_substances()}
        self.assertEqual(by_key["lsd"]["tolerance_group"], by_key["psilocybin_mushrooms"]["tolerance_group"])
        self.assertEqual(by_key["lsd"]["tolerance_group"], by_key["2c-b"]["tolerance_group"])

    def test_load_effects_returns_full_subjective_effect_index(self) -> None:
        from substance_journal.core.reference_data import load_effects

        effects = load_effects()
        self.assertGreater(len(effects), 200)
        names = {e["name"] for e in effects}
        self.assertIn("Color enhancement", names)
        categories = {e["category"] for e in effects}
        self.assertIn("Visual effects", categories)
        self.assertIn("Cognitive effects", categories)

    def test_load_interactions_covers_known_dangerous_combo(self) -> None:
        from substance_journal.core.reference_data import load_interactions

        interactions = load_interactions()
        alcohol_ketamine = next(
            i
            for i in interactions
            if {i["substance_a"], i["substance_b"]} == {"alcohol", "ketamine"}
        )
        self.assertEqual(alcohol_ketamine["risk_level"], "Dangerous")


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        from substance_journal.core.database import Store

        db_path = Path(tempfile.gettempdir()) / f"substance_journal_test_{os.getpid()}_{id(self)}.db"
        if db_path.exists():
            db_path.unlink()
        self.db_path = db_path
        self.store = Store(db_path)

    def tearDown(self) -> None:
        if self.db_path.exists():
            self.db_path.unlink()

    def test_reference_data_is_seeded_and_queryable(self) -> None:
        substances = self.store.list_substances()
        self.assertEqual(len(substances), 9)

        lsd = self.store.get_substance("lsd")
        self.assertIsNotNone(lsd)
        self.assertEqual(lsd.tolerance_group, "psychedelics")
        sublingual = next(r for r in lsd.roas if r.route == "sublingual")
        self.assertIsNotNone(sublingual.dose_common)
        self.assertIsNotNone(sublingual.duration("onset"))

        dmt = self.store.get_substance("dmt")
        self.assertFalse(dmt.has_tolerance)

        effects = self.store.list_effects()
        self.assertGreater(len(effects), 200)

        interaction = self.store.lookup_interaction("ketamine", "alcohol")
        self.assertIsNotNone(interaction)
        self.assertEqual(interaction.risk_level, "Dangerous")

    def test_reseeding_on_reopen_does_not_duplicate_reference_rows(self) -> None:
        from substance_journal.core.database import Store

        Store(self.db_path)
        substances = self.store.list_substances()
        self.assertEqual(len(substances), 9)
        effects = self.store.list_effects()
        self.assertLess(len(effects), 500)

    def test_session_lifecycle(self) -> None:
        self.assertIsNone(self.store.get_open_session("Me"))

        started = datetime(2026, 7, 27, 20, 0, 0)
        session_id = self.store.start_session("Me", started)
        open_session = self.store.get_open_session("Me")
        self.assertIsNotNone(open_session)
        self.assertEqual(open_session.id, session_id)
        self.assertIsNone(open_session.ended_at)

        self.store.end_session(session_id, datetime(2026, 7, 28, 4, 0, 0))
        self.assertIsNone(self.store.get_open_session("Me"))
        closed = self.store.get_session(session_id)
        self.assertIsNotNone(closed.ended_at)

    def test_ingestion_and_effect_log_round_trip(self) -> None:
        from substance_journal.core.models import EffectLog, Ingestion

        session_id = self.store.start_session("Me", datetime(2026, 7, 27, 20, 0, 0))
        lsd = self.store.get_substance("lsd")
        roa = lsd.roas[0]

        ingestion_id = self.store.add_ingestion(
            Ingestion(
                id=None,
                session_id=session_id,
                substance_key="lsd",
                roa_id=roa.id,
                amount=100.0,
                unit=roa.unit,
                occurred_at=datetime(2026, 7, 27, 20, 5, 0),
                consumer="Me",
            )
        )
        ingestions = self.store.list_ingestions_for_session(session_id)
        self.assertEqual(len(ingestions), 1)
        self.assertEqual(ingestions[0].id, ingestion_id)

        color_enhancement = next(e for e in self.store.list_effects() if e.name == "Color enhancement")
        self.store.add_effect_log(
            EffectLog(
                id=None,
                session_id=session_id,
                effect_id=color_enhancement.id,
                occurred_at=datetime(2026, 7, 27, 21, 0, 0),
                intensity="common",
            )
        )
        logs = self.store.list_effect_logs_for_session(session_id)
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].effect_id, color_enhancement.id)

    def test_substance_preset_round_trip(self) -> None:
        from substance_journal.core.models import SubstancePreset

        cannabis = self.store.get_substance("cannabis")
        roa = cannabis.roas[0]
        preset_id = self.store.save_preset(
            SubstancePreset(id=None, substance_key="cannabis", roa_id=roa.id, name="Usual bowl", amount=5.0)
        )
        presets = self.store.list_presets("cannabis")
        self.assertEqual(len(presets), 1)
        self.assertEqual(presets[0].id, preset_id)

        self.store.delete_preset(preset_id)
        self.assertEqual(self.store.list_presets("cannabis"), [])


class InteractionCheckerTests(unittest.TestCase):
    def setUp(self) -> None:
        from substance_journal.core.database import Store

        db_path = Path(tempfile.gettempdir()) / f"substance_journal_test_ix_{os.getpid()}_{id(self)}.db"
        if db_path.exists():
            db_path.unlink()
        self.db_path = db_path
        self.store = Store(db_path)

    def tearDown(self) -> None:
        if self.db_path.exists():
            self.db_path.unlink()

    def _log(self, session_id: int, substance_key: str, when: datetime) -> None:
        from substance_journal.core.models import Ingestion

        substance = self.store.get_substance(substance_key)
        roa = substance.roas[0]
        self.store.add_ingestion(
            Ingestion(
                id=None,
                session_id=session_id,
                substance_key=substance_key,
                roa_id=roa.id,
                amount=roa.dose_common.min if roa.dose_common else 1.0,
                unit=roa.unit,
                occurred_at=when,
                consumer="Me",
            )
        )

    def test_no_warnings_with_no_open_session(self) -> None:
        from substance_journal.core.interactions import check_new_ingestion

        self.assertEqual(check_new_ingestion(self.store, "Me", "alcohol"), [])

    def test_dangerous_combo_is_flagged(self) -> None:
        from substance_journal.core.interactions import check_new_ingestion

        session_id = self.store.start_session("Me", datetime(2026, 7, 27, 22, 0, 0))
        self._log(session_id, "ketamine", datetime(2026, 7, 27, 22, 0, 0))

        warnings = check_new_ingestion(self.store, "Me", "alcohol")
        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0].other_substance_key, "ketamine")
        self.assertEqual(warnings[0].interaction.risk_level, "Dangerous")

    def test_low_risk_combo_is_not_flagged(self) -> None:
        from substance_journal.core.interactions import check_new_ingestion

        session_id = self.store.start_session("Me", datetime(2026, 7, 27, 22, 0, 0))
        self._log(session_id, "alcohol", datetime(2026, 7, 27, 22, 0, 0))

        warnings = check_new_ingestion(self.store, "Me", "lsd")
        self.assertEqual(warnings, [])

    def test_closed_session_does_not_leak_into_a_new_session(self) -> None:
        from substance_journal.core.interactions import check_new_ingestion

        session_id = self.store.start_session("Me", datetime(2026, 7, 27, 20, 0, 0))
        self._log(session_id, "ketamine", datetime(2026, 7, 27, 20, 0, 0))
        self.store.end_session(session_id, datetime(2026, 7, 28, 2, 0, 0))

        warnings = check_new_ingestion(self.store, "Me", "alcohol")
        self.assertEqual(warnings, [])


class ToleranceTests(unittest.TestCase):
    def setUp(self) -> None:
        from substance_journal.core.database import Store

        db_path = Path(tempfile.gettempdir()) / f"substance_journal_test_tol_{os.getpid()}_{id(self)}.db"
        if db_path.exists():
            db_path.unlink()
        self.db_path = db_path
        self.store = Store(db_path)
        self.substances_by_key = {s.key: s for s in self.store.list_substances()}

    def tearDown(self) -> None:
        if self.db_path.exists():
            self.db_path.unlink()

    def test_dmt_has_no_tolerance_track(self) -> None:
        from substance_journal.core.tolerance import tolerance_tracks

        tracks = tolerance_tracks(self.store.list_substances())
        all_keys = {s.key for substances in tracks.values() for s in substances}
        self.assertNotIn("dmt", all_keys)

    def test_lsd_and_psilocybin_share_one_pooled_track(self) -> None:
        from substance_journal.core.tolerance import tolerance_tracks

        tracks = tolerance_tracks(self.store.list_substances())
        psychedelics_track = tracks["psychedelics"]
        keys = {s.key for s in psychedelics_track}
        self.assertIn("lsd", keys)
        self.assertIn("psilocybin_mushrooms", keys)

    def test_tolerance_decays_toward_zero_over_time(self) -> None:
        from substance_journal.core.models import Ingestion
        from substance_journal.core.tolerance import current_tolerance_level

        lsd = self.substances_by_key["lsd"]
        dosed_at = datetime(2026, 7, 1, 20, 0, 0)
        ingestions = [
            Ingestion(
                id=None,
                session_id=1,
                substance_key="lsd",
                roa_id=lsd.roas[0].id,
                amount=100,
                unit=lsd.roas[0].unit,
                occurred_at=dosed_at,
                consumer="Me",
            )
        ]

        just_after = current_tolerance_level(ingestions, self.substances_by_key, "psychedelics", dosed_at + timedelta(minutes=1))
        one_half_life_later = current_tolerance_level(
            ingestions, self.substances_by_key, "psychedelics", dosed_at + timedelta(days=lsd.tolerance_zero_days / 4)
        )
        long_after = current_tolerance_level(ingestions, self.substances_by_key, "psychedelics", dosed_at + timedelta(days=60))

        self.assertAlmostEqual(just_after, 1.0, places=2)
        self.assertAlmostEqual(one_half_life_later, 0.5, places=2)
        self.assertLess(long_after, 0.01)

    def test_pooled_group_combines_contributions_from_both_substances(self) -> None:
        from substance_journal.core.models import Ingestion
        from substance_journal.core.tolerance import current_tolerance_level

        lsd = self.substances_by_key["lsd"]
        psilocybin = self.substances_by_key["psilocybin_mushrooms"]
        at = datetime(2026, 7, 1, 20, 0, 0)
        ingestions = [
            Ingestion(
                id=None, session_id=1, substance_key="lsd", roa_id=lsd.roas[0].id,
                amount=100, unit=lsd.roas[0].unit, occurred_at=at, consumer="Me",
            ),
            Ingestion(
                id=None, session_id=1, substance_key="psilocybin_mushrooms", roa_id=psilocybin.roas[0].id,
                amount=2, unit=psilocybin.roas[0].unit, occurred_at=at, consumer="Me",
            ),
        ]
        level = current_tolerance_level(ingestions, self.substances_by_key, "psychedelics", at + timedelta(minutes=1))
        self.assertAlmostEqual(level, 2.0, places=2)


class AlcoholImportTests(unittest.TestCase):
    def setUp(self) -> None:
        from substance_journal.core.database import Store

        db_path = Path(tempfile.gettempdir()) / f"substance_journal_test_import_{os.getpid()}_{id(self)}.db"
        if db_path.exists():
            db_path.unlink()
        self.db_path = db_path
        self.store = Store(db_path)

        self.export_path = Path(tempfile.gettempdir()) / f"alcohol_tracker_export_{os.getpid()}_{id(self)}.json"
        export_rows = [
            {
                "occurred_at": "2026-06-01T20:00:00",
                "amount": 1.0,
                "unit": "shots",
                "abv_percent": 40.0,
                "label": "Shot - 40%",
                "notes": "",
                "duration_minutes": 0,
                "consumer": "Me",
            },
            {
                "occurred_at": "2026-06-01T22:00:00",
                "amount": 12.0,
                "unit": "fl_oz",
                "abv_percent": 5.0,
                "label": "Beer - 12 oz 5%",
                "notes": "with dinner",
                "duration_minutes": 0,
                "consumer": "Me",
            },
            {
                "occurred_at": "2026-06-03T19:00:00",
                "amount": 5.0,
                "unit": "fl_oz",
                "abv_percent": 12.0,
                "label": "Wine - 5 oz 12%",
                "notes": "",
                "duration_minutes": 0,
                "consumer": "Alex",
            },
        ]
        with open(self.export_path, "w", encoding="utf-8") as f:
            json.dump(export_rows, f)

    def tearDown(self) -> None:
        if self.db_path.exists():
            self.db_path.unlink()
        if self.export_path.exists():
            self.export_path.unlink()

    def test_import_creates_one_session_per_consumer_per_day(self) -> None:
        from substance_journal.core.alcohol_import import import_alcohol_tracker_data

        result = import_alcohol_tracker_data(self.store, self.export_path)
        self.assertEqual(result.imported, 3)
        self.assertEqual(result.sessions_created, 2)  # Me/June 1 and Alex/June 3
        self.assertEqual(result.skipped_duplicates, 0)

        me_sessions = self.store.list_sessions("Me")
        self.assertEqual(len(me_sessions), 1)
        ingestions = self.store.list_ingestions_for_session(me_sessions[0].id)
        self.assertEqual(len(ingestions), 2)
        self.assertTrue(all(i.substance_key == "alcohol" for i in ingestions))
        self.assertEqual(me_sessions[0].ended_at.isoformat(), "2026-06-01T22:00:00")

    def test_import_computes_pure_alcohol_grams_matching_alcohol_tracker_formula(self) -> None:
        from substance_journal.core.alcohol_import import import_alcohol_tracker_data

        import_alcohol_tracker_data(self.store, self.export_path)
        me_sessions = self.store.list_sessions("Me")
        ingestions = self.store.list_ingestions_for_session(me_sessions[0].id)
        shot = next(i for i in ingestions if "Shot" in i.notes)
        # 1 shot = 1.5 fl oz * 40% ABV * 23.36 g/fl oz pure alcohol
        expected_grams = round(1.5 * 0.40 * 23.36, 2)
        self.assertAlmostEqual(shot.amount, expected_grams, places=2)
        self.assertEqual(shot.unit, "g")

    def test_reimport_skips_duplicates(self) -> None:
        from substance_journal.core.alcohol_import import import_alcohol_tracker_data

        import_alcohol_tracker_data(self.store, self.export_path)
        second_result = import_alcohol_tracker_data(self.store, self.export_path)
        self.assertEqual(second_result.imported, 0)
        self.assertEqual(second_result.skipped_duplicates, 3)

    def test_import_reads_directly_from_alcohol_tracker_sqlite_db(self) -> None:
        import sqlite3

        from substance_journal.core.alcohol_import import import_alcohol_tracker_data

        db_path = Path(tempfile.gettempdir()) / f"alcohol_tracker_fake_{os.getpid()}_{id(self)}.db"
        if db_path.exists():
            db_path.unlink()
        connection = sqlite3.connect(db_path)
        connection.execute(
            """
            CREATE TABLE ingestions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                occurred_at TEXT NOT NULL,
                amount REAL NOT NULL,
                unit TEXT NOT NULL,
                abv_percent REAL NOT NULL,
                label TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                duration_minutes REAL NOT NULL DEFAULT 0,
                consumer TEXT NOT NULL DEFAULT 'Me',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            "INSERT INTO ingestions (occurred_at, amount, unit, abv_percent, label, notes, consumer, created_at, updated_at) "
            "VALUES ('2026-06-05T21:00:00', 12.0, 'fl_oz', 5.0, 'Beer - 12 oz 5%', '', 'Me', '2026-06-05T21:00:00', '2026-06-05T21:00:00')"
        )
        connection.commit()
        connection.close()

        try:
            result = import_alcohol_tracker_data(self.store, db_path)
            self.assertEqual(result.imported, 1)
            me_sessions = self.store.list_sessions("Me")
            self.assertEqual(len(me_sessions), 1)
        finally:
            db_path.unlink()

    def test_default_alcohol_tracker_db_path_matches_alcohol_tracker_own_layout(self) -> None:
        from substance_journal.core.alcohol_import import default_alcohol_tracker_db_path

        path = default_alcohol_tracker_db_path()
        self.assertEqual(path.name, "alcohol_tracker.db")
        self.assertIn("AlcoholTracker", path.parts)


if __name__ == "__main__":
    unittest.main()
