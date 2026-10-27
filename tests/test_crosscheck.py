import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

import crosscheck_tripsit as cc  # noqa: E402
from substance_journal.core.catalog_import import COPIED_NOTE, apply_crosschecks  # noqa: E402


def roa(route="oral", unit="mg", light=(10, 30), common=(30, 60), strong=(60, 100), heavy=100, total=(4, 6)):
    return {
        "route": route,
        "unit": unit,
        "dose_threshold": None,
        "dose_light": {"min": light[0], "max": light[1]},
        "dose_common": {"min": common[0], "max": common[1]},
        "dose_strong": {"min": strong[0], "max": strong[1]},
        "dose_heavy": heavy,
        "duration": {"total": {"min": total[0], "max": total[1], "units": "hours"}},
    }


def substance(key="x", name="X", roas=None):
    return {
        "key": key,
        "name": name,
        "common_names": [],
        "audited": False,
        "sources": ["https://psychonautwiki.org/wiki/X"],
        "safety_notes": [COPIED_NOTE],
        "roas": roas or [roa()],
    }


class ParseTests(unittest.TestCase):
    def test_formats_tripsit_uses(self):
        self.assertEqual(cc.parse_amount("75mg-250mg"), (75.0, 250.0, "mg"))
        self.assertEqual(cc.parse_amount("100-150ug"), (100.0, 150.0, "ug"))
        self.assertEqual(cc.parse_amount("400mg+"), (400.0, None, "mg"))
        self.assertEqual(cc.parse_amount("1.5 ml+"), (1.5, None, "ml"))
        self.assertEqual(cc.parse_amount("2g"), (2.0, 2.0, "g"))
        self.assertIsNone(cc.parse_amount("unknown"))
        self.assertEqual(cc.parse_amount("3 seeds-5"), (3.0, 5.0, "seeds"))  # parsed, but never compared: not a mass or volume

    def test_units_compare_in_one_scale(self):
        self.assertEqual(cc.to_base(0.1, "g"), (100.0, "mg"))
        self.assertEqual(cc.to_base(500, "ug"), (0.5, "mg"))
        self.assertEqual(cc.to_base(2, "ml"), (2, "ml"))
        self.assertIsNone(cc.to_base(3, "seeds"))


class CompareTests(unittest.TestCase):
    TRIP_AGREE = {"Light": "10-30mg", "Common": "30-60mg", "Strong": "60-100mg", "Heavy": "100mg+"}

    def run_check(self, ours, trip_dose, duration="4-6"):
        trip = {"x": {"pretty_name": "X", "aliases": [], "formatted_dose": {"Oral": trip_dose}, "formatted_duration": {"_unit": "hours", "value": duration}}}
        return cc.crosscheck([ours], trip)["x"]

    def test_same_numbers_agree_even_in_another_unit(self):
        res = self.run_check(substance(), {"Light": "0.01-0.03g", "Common": "0.03g-0.06g", "Strong": "60-100mg"})
        self.assertEqual(res["status"], "agrees")
        self.assertEqual(res["agrees"], ["oral"])

    def test_a_threshold_far_apart_is_a_conflict_and_records_which_is_lower(self):
        res = self.run_check(substance(), {"Light": "5-15mg", "Common": "15-30mg", "Strong": "30-50mg"})
        self.assertEqual(res["status"], "conflicts")
        self.assertTrue(all(c["tripsit_is_lower"] for c in res["conflicts"]))

    def test_durations_that_do_not_overlap_block_agreement(self):
        res = self.run_check(substance(), self.TRIP_AGREE, duration="24-48")
        self.assertEqual(res["status"], "no_data")

    def test_different_routes_or_units_are_not_compared(self):
        trip = {"x": {"pretty_name": "X", "formatted_dose": {"Insufflated": {"Light": "1-2mg", "Common": "2-4mg"}}}}
        self.assertEqual(cc.crosscheck([substance()], trip)["x"]["status"], "no_data")

    def test_unknown_compounds_are_reported_as_not_covered(self):
        self.assertEqual(cc.crosscheck([substance()], {})["x"]["status"], "not_covered")


class ApplyTests(unittest.TestCase):
    def test_agreement_marks_cross_checked_replaces_the_copied_note_and_links_tripsit(self):
        item = substance()
        verdict = {"x": {"status": "agrees", "agrees": ["oral"], "conflicts": [], "durations": "overlap", "url": "https://tripsit.me/factsheets/x"}}
        out = apply_crosschecks([item], verdict)[0]
        self.assertTrue(out["cross_checked"])
        self.assertFalse(out["audited"])
        self.assertNotIn(COPIED_NOTE, out["safety_notes"])
        self.assertIn("https://tripsit.me/factsheets/x", out["sources"])

    def test_conflict_keeps_the_copied_warning_and_adds_the_lower_figure(self):
        item = substance()
        verdict = {"x": {"status": "conflicts", "agrees": [], "durations": None, "url": "https://tripsit.me/factsheets/x", "conflicts": [
            {"route": "oral", "band": "Strong", "psychonautwiki": "60 mg", "tripsit": "30-50mg", "tripsit_is_lower": True}]}}
        out = apply_crosschecks([item], verdict)[0]
        self.assertFalse(out["cross_checked"])
        self.assertIn(COPIED_NOTE, out["safety_notes"])
        self.assertTrue(any("Start with the lower figure" in n for n in out["safety_notes"]))

    def test_applying_twice_changes_nothing(self):
        verdict = {"x": {"status": "conflicts", "agrees": [], "durations": None, "url": "https://tripsit.me/factsheets/x", "conflicts": [
            {"route": "oral", "band": "Strong", "psychonautwiki": "60 mg", "tripsit": "30-50mg", "tripsit_is_lower": True}]}}
        once = apply_crosschecks([substance()], verdict)
        twice = apply_crosschecks(copy.deepcopy(once), verdict)
        self.assertEqual(once, twice)

    def test_a_compound_tripsit_does_not_cover_is_left_alone(self):
        out = apply_crosschecks([substance()], {"x": {"status": "not_covered"}})[0]
        self.assertFalse(out["cross_checked"])
        self.assertEqual(out["safety_notes"], [COPIED_NOTE])


if __name__ == "__main__":
    unittest.main()
