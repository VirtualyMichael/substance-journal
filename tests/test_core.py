import os
import tempfile
import unittest
from datetime import datetime
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


if __name__ == "__main__":
    unittest.main()
