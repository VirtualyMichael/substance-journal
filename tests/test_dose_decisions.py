import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from substance_journal.core.dose_decisions import BANDS, DECISION_PREFIX, apply_decisions  # noqa: E402

CATALOG = {e["key"]: e for e in json.loads((ROOT / "data" / "substances_extra.json").read_text(encoding="utf-8"))}


def _bands(roa):
    return [roa.get("dose_threshold"), roa["dose_light"]["min"], roa["dose_common"]["min"], roa["dose_strong"]["min"], roa["dose_heavy"]]


class DoseDecisionTests(unittest.TestCase):
    def test_catalog_has_decided_values_and_ascending_ladders(self):
        for (key, route), mins in BANDS.items():
            roa = next(r for r in CATALOG[key]["roas"] if r["route"] == route)
            ladder = [v for v in _bands(roa) if v is not None]
            self.assertEqual(ladder, sorted(ladder), f"{key} {route}")
            for band, value in mins.items():
                got = roa["dose_threshold"] if band == "threshold" else (roa[f"dose_{band}"]["min"] if band != "heavy" else roa["dose_heavy"])
                self.assertEqual(got, value, f"{key} {route} {band}")

    def test_zolpidem_never_above_label_ceiling_before_heavy(self):
        roa = next(r for r in CATALOG["zolpidem"]["roas"] if r["route"] == "oral")
        self.assertLessEqual(roa["dose_common"]["max"], 10)

    def test_notes_carry_decisions_and_are_idempotent(self):
        once = apply_decisions(json.loads(json.dumps(list(CATALOG.values()))))
        twice = apply_decisions(json.loads(json.dumps(once)))
        self.assertEqual(once, twice)
        notes = next(i for i in once if i["key"] == "zolpidem")["safety_notes"]
        self.assertEqual(len([n for n in notes if n.startswith(DECISION_PREFIX)]), 1)


if __name__ == "__main__":
    unittest.main()
