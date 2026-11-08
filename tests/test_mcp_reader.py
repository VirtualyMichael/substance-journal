"""The read-only reader server against a digest folder laid out like the app writes it."""
import importlib.util
import json
from pathlib import Path

import pytest

pytest.importorskip("mcp")

SERVER = Path(__file__).resolve().parents[1] / "mcp" / "substance-journal-reader" / "server.py"

PROFILE = """# Profile: Me
Generated 2026-10-31 12:00.

## By compound
- Cannabis: 8 doses on 3 days, last 2026-10-30 (3 h ago), 8 in the last 30 days, tolerance high and rising.
- Alcohol: 6 doses on 2 days, last 2026-10-28 (2 days ago), 6 in the last 30 days, tolerance moderate and steady.
"""

MONTH = """# 2026-10 for Me
14 doses on 3 of 31 days (28 without use).

## Totals
- Cannabis: 8 doses, about 21.6 mg absorbed.
- Alcohol: 6 drinks, about 4.2 standard drinks (59 g ethanol).

## Days
- 2026-10-28: Alcohol x6 (4.2 std drinks); Cannabis x4 (~10.8 mg absorbed)
"""

SHEET = """# Experience: Quiet night, 2026-10-28 20:43
Person: Me | 3 doses | first 20:43

## Doses
- 20:43 (+0m) Cannabis, smoked, 2.70 mg [common for this route]; ~2.7 mg absorbed; note: first bowl
- 21:03 (+20m) Alcohol, oral, 12 fl oz at 5%
- 21:23 (+40m) Cannabis, smoked, 2.70 mg [common for this route]; ~2.7 mg absorbed

## Estimated curve (model, not measured)
- Cannabis: noticeable from about 20:48, peaks about 21:50 (relative intensity 2.4)

## Going in
- Cannabis: tolerance moderate, last used 2d before.

## Notes during
- 22:13 (+1h 30m): feeling anxious, drank water
"""

OTHER = SHEET.replace("2026-10-28 20:43", "2026-10-30 14:20").replace("Quiet night", "Afternoon").replace("feeling anxious, drank water", "calm")


@pytest.fixture()
def srv(tmp_path, monkeypatch):
    me = tmp_path / "me"
    (me / "months").mkdir(parents=True)
    (me / "experiences").mkdir()
    (me / "profile.md").write_text(PROFILE, encoding="utf-8")
    (me / "months" / "2026-10.md").write_text(MONTH, encoding="utf-8")
    (me / "experiences" / "2026-10-28_2043_aaaaaaaa.md").write_text(SHEET, encoding="utf-8")
    (me / "experiences" / "2026-10-30_1420_bbbbbbbb.md").write_text(OTHER, encoding="utf-8")
    index = {
        "generated": "2026-10-31T12:00:00",
        "experiences": [
            {"id": "bbbbbbbb-0000", "path": "experiences/2026-10-30_1420_bbbbbbbb.md", "date": "2026-10-30", "time": "14:20", "title": "Afternoon", "substances": ["Cannabis"], "doses": 2, "tokens": 300},
            {"id": "aaaaaaaa-0000", "path": "experiences/2026-10-28_2043_aaaaaaaa.md", "date": "2026-10-28", "time": "20:43", "title": "Quiet night", "substances": ["Alcohol", "Cannabis"], "doses": 3, "tokens": 400},
        ],
    }
    (me / "index.json").write_text(json.dumps(index), encoding="utf-8")
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DIGEST", str(tmp_path))
    spec = importlib.util.spec_from_file_location("sj_reader", SERVER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_guide_explains_layers_and_safety(srv):
    g = srv.guide()
    assert "profile" in g and "experience" in g
    assert "Never say a dose, mix or plan is safe" in g


def test_profile_month_and_latest_experience(srv):
    assert "Cannabis: 8 doses" in srv.profile()
    assert "2026-10 for Me" in srv.month()
    assert "Afternoon" in srv.experience()
    assert "No page for 2026-09" in srv.month("2026-09")


def test_experience_by_date_and_id(srv):
    assert "Quiet night" in srv.experience("2026-10-28")
    assert "Quiet night" in srv.experience("aaaaaaaa")
    assert "No experience matches" in srv.experience("1999-01-01")


def test_list_filters_by_date_and_compound(srv):
    all_rows = srv.list_experiences()
    assert all_rows.count("\n") == 1
    assert "Quiet night" in srv.list_experiences(substance="alcohol")
    assert "Afternoon" not in srv.list_experiences(substance="alcohol")
    assert "Quiet night" not in srv.list_experiences(start="2026-10-29")
    assert "more" in srv.list_experiences(limit=1)


def test_find_searches_notes_with_dates(srv):
    out = srv.find("anxious")
    assert "2026-10-28 20:43" in out and "feeling anxious" in out
    assert srv.find("zzz") == "No matches."


def test_doses_for_one_compound(srv):
    out = srv.doses("cannabis")
    assert out.count("Cannabis, smoked") == 4
    assert "Alcohol" not in out
    assert "No doses" in srv.doses("lsd")


def test_tolerance_and_compare(srv):
    assert "tolerance high and rising" in srv.tolerance()
    cmp = srv.compare_months("2026-10", "2026-09")
    assert "21.6 mg absorbed" in cmp and "2026-09: no data" in cmp


def test_every_tool_is_bounded(srv):
    big = "x" * 40000
    capped = srv._cap(big, 100)
    assert len(capped) < 800 and "Cut to fit" in capped


def test_missing_folder_explains_how_to_make_it(tmp_path, monkeypatch):
    monkeypatch.setenv("SUBSTANCE_JOURNAL_DIGEST", str(tmp_path / "nothing"))
    spec = importlib.util.spec_from_file_location("sj_reader2", SERVER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert "Keep the folder up to date" in mod.profile()
