import unittest


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


if __name__ == "__main__":
    unittest.main()
