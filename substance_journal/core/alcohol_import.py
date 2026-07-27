"""Import ingestion history from Alcohol Tracker (the sibling "Alcohol ingestion
marking app" project) into this app's alcohol substance/oral route, grouping each
consumer's per-day entries into one closed session per day (Alcohol Tracker has no
session concept of its own).

Supports two source formats:
- Alcohol Tracker's own SQLite database (its default on-disk storage) - read
  directly, no export step needed.
- Alcohol Tracker's JSON export (MainWindow.export_data), for when a user wants to
  import from a file that isn't at the default location.
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
from collections import defaultdict
from contextlib import closing
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from substance_journal.core.database import Store
from substance_journal.core.models import Ingestion

ALCOHOL_DENSITY_GRAMS_PER_FL_OZ = 23.36
SHOT_VOLUME_OZ = 1.5


def default_alcohol_tracker_db_path() -> Path:
    """Mirrors Alcohol Tracker's own core/paths.py default_db_path() exactly, so this
    always points at where Alcohol Tracker actually stores its data."""
    if sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "AlcoholTracker" / "alcohol_tracker.db"


@dataclass(frozen=True)
class ImportResult:
    imported: int
    skipped_duplicates: int
    sessions_created: int


def _pure_alcohol_grams(amount: float, unit: str, abv_percent: float) -> float:
    fluid_ounces = amount * SHOT_VOLUME_OZ if unit == "shots" else amount
    pure_alcohol_oz = fluid_ounces * (abv_percent / 100.0)
    return pure_alcohol_oz * ALCOHOL_DENSITY_GRAMS_PER_FL_OZ


def _read_rows_from_json(path: Path) -> list[dict]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _read_rows_from_sqlite(path: Path) -> list[dict]:
    with closing(sqlite3.connect(path)) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            "SELECT occurred_at, amount, unit, abv_percent, label, notes, consumer FROM ingestions"
        ).fetchall()
    return [
        {
            "occurred_at": row["occurred_at"],
            "amount": row["amount"],
            "unit": row["unit"],
            "abv_percent": row["abv_percent"],
            "label": row["label"],
            "notes": row["notes"],
            "consumer": row["consumer"],
        }
        for row in rows
    ]


def _read_rows(path: Path) -> list[dict]:
    if path.suffix.lower() in (".db", ".sqlite", ".sqlite3"):
        return _read_rows_from_sqlite(path)
    return _read_rows_from_json(path)


def import_alcohol_tracker_data(store: Store, path: Path) -> ImportResult:
    rows = _read_rows(path)

    alcohol = store.get_substance("alcohol")
    if alcohol is None or not alcohol.roas:
        raise RuntimeError("Alcohol substance/route data is not available - run scripts/sync_substance_data.py first.")
    roa = alcohol.roas[0]

    existing_by_signature = set()
    for existing in store.list_ingestions():
        if existing.substance_key == "alcohol":
            existing_by_signature.add((existing.consumer, existing.occurred_at, round(existing.amount, 2)))

    by_day_and_consumer: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in rows:
        occurred_at = datetime.fromisoformat(row["occurred_at"])
        consumer = row.get("consumer") or "Me"
        day_key = occurred_at.date().isoformat()
        by_day_and_consumer[(consumer, day_key)].append(row)

    imported = 0
    skipped = 0
    sessions_created = 0

    for (consumer, _day), day_rows in by_day_and_consumer.items():
        day_rows.sort(key=lambda r: r["occurred_at"])
        to_insert = []
        for row in day_rows:
            occurred_at = datetime.fromisoformat(row["occurred_at"])
            grams = round(_pure_alcohol_grams(row["amount"], row["unit"], row["abv_percent"]), 2)
            if (consumer, occurred_at, grams) in existing_by_signature:
                skipped += 1
                continue
            notes = row.get("label") or ""
            if row.get("notes"):
                notes = f"{notes} — {row['notes']}" if notes else row["notes"]
            to_insert.append((occurred_at, grams, notes))

        if not to_insert:
            continue

        session_id = store.start_session(consumer, to_insert[0][0], notes="Imported from Alcohol Tracker")
        sessions_created += 1
        for occurred_at, grams, notes in to_insert:
            store.add_ingestion(
                Ingestion(
                    id=None,
                    session_id=session_id,
                    substance_key="alcohol",
                    roa_id=roa.id,
                    amount=grams,
                    unit=roa.unit,
                    occurred_at=occurred_at,
                    consumer=consumer,
                    notes=notes,
                )
            )
            imported += 1
        store.end_session(session_id, to_insert[-1][0])

    return ImportResult(imported=imported, skipped_duplicates=skipped, sessions_created=sessions_created)
