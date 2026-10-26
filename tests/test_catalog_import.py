import unittest
from datetime import date

from substance_journal.core.catalog_import import (
    build_extra_catalog,
    cross_tolerance_group,
    normalize_substance,
    normalize_unit,
    slugify,
)

DIAZEPAM = {
    "name": "Diazepam",
    "url": "https://psychonautwiki.org/wiki/Diazepam",
    "commonNames": ["Valium"],
    "summary": "Diazepam is a benzodiazepine.",
    "class": {"chemical": ["Benzodiazepines"], "psychoactive": ["Depressant"]},
    "roas": [
        {
            "name": "oral",
            "dose": {
                "units": "mg",
                "threshold": 2,
                "light": {"min": 5, "max": 10},
                "common": {"min": 10, "max": 20},
                "strong": {"min": 20, "max": 40},
                "heavy": 40,
            },
            "duration": {"onset": {"min": 15, "max": 45, "units": "minutes"}, "total": {"min": 6, "max": 8, "units": "hours"}},
        }
    ],
    "tolerance": {"full": "with prolonged use", "half": "1 - 2 weeks", "zero": "2 - 4 weeks"},
    "crossTolerances": ["benzodiazepines", "gabaergic"],
    "addictionPotential": "moderately addictive",
    "dangerousInteractions": [{"name": "Alcohol"}],
    "unsafeInteractions": [],
    "uncertainInteractions": [],
}


class CatalogImportTest(unittest.TestCase):
    def test_slugify_keeps_existing_keys(self):
        self.assertEqual(slugify("2C-B"), "2c-b")
        self.assertEqual(slugify("Psilocybin mushrooms"), "psilocybin_mushrooms")

    def test_unit_normalising(self):
        self.assertEqual(normalize_unit("μg"), "µg")
        self.assertEqual(normalize_unit("mg/kg (body weight)"), "mg/kg")
        self.assertEqual(normalize_unit(None), "")

    def test_cross_tolerance(self):
        self.assertEqual(cross_tolerance_group(["Gabaergic"]), "gaba")
        self.assertIsNone(cross_tolerance_group(["something odd"]))

    def test_normalize_diazepam(self):
        item = normalize_substance(DIAZEPAM, date(2026, 1, 2))
        assert item is not None
        self.assertEqual(item["key"], "diazepam")
        self.assertFalse(item["audited"])
        self.assertEqual(item["tolerance_group"], "benzodiazepines")
        self.assertEqual(item["roas"][0]["dose_common"], {"min": 10, "max": 20})
        self.assertEqual(item["fetched"], "2026-01-02")
        self.assertIn("not independently checked", item["safety_notes"][0])

    def test_transposed_range_is_swapped(self):
        raw = {"name": "X", "roas": [{"name": "insufflated", "dose": {"units": "mg", "light": {"min": 40, "max": 20}}}]}
        item = normalize_substance(raw)
        assert item is not None
        self.assertEqual(item["roas"][0]["dose_light"], {"min": 20, "max": 40})

    def test_no_loggable_routes_is_skipped(self):
        self.assertIsNone(normalize_substance({"name": "2C-x", "roas": []}))
        self.assertIsNone(normalize_substance({"name": "Plant", "roas": [{"name": "oral", "dose": {}, "duration": {}}]}))

    def test_placeholder_summary_dropped(self):
        raw = {**DIAZEPAM, "summary": "Summary sheet: Diazepam"}
        item = normalize_substance(raw)
        assert item is not None
        self.assertEqual(item["summary"], "")

    def test_catalog_excludes_audited_and_dedupes_keys(self):
        a = {**DIAZEPAM, "name": "Foo Bar"}
        b = {**DIAZEPAM, "name": "Foo-Bar"}
        audited = {**DIAZEPAM, "name": "LSD"}
        keys = [s["key"] for s in build_extra_catalog([a, b, audited])]
        self.assertEqual(len(keys), 2)
        self.assertEqual(len(set(keys)), 2)
        self.assertNotIn("lsd", keys)


if __name__ == "__main__":
    unittest.main()
