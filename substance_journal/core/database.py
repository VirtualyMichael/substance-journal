from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime
from pathlib import Path

from substance_journal.core import reference_data
from substance_journal.core.models import (
    DoseRange,
    DurationPhase,
    EffectLog,
    Ingestion,
    Interaction,
    RouteOfAdministration,
    Session,
    Substance,
    SubjectiveEffect,
    SubstancePreset,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS substances (
    key TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    common_names TEXT NOT NULL,
    category TEXT NOT NULL,
    chemical_class TEXT NOT NULL,
    summary TEXT,
    wiki_url TEXT,
    has_tolerance INTEGER NOT NULL,
    tolerance_group TEXT,
    addiction_potential TEXT
);

CREATE TABLE IF NOT EXISTS routes_of_administration (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    substance_key TEXT NOT NULL,
    route TEXT NOT NULL,
    unit TEXT NOT NULL,
    dose_threshold REAL,
    dose_light_min REAL,
    dose_light_max REAL,
    dose_common_min REAL,
    dose_common_max REAL,
    dose_strong_min REAL,
    dose_strong_max REAL,
    dose_heavy REAL
);

CREATE TABLE IF NOT EXISTS duration_phases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    roa_id INTEGER NOT NULL,
    phase TEXT NOT NULL,
    min_minutes REAL,
    max_minutes REAL
);

CREATE TABLE IF NOT EXISTS interactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    substance_a TEXT NOT NULL,
    substance_b TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    note TEXT
);

CREATE TABLE IF NOT EXISTS subjective_effects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    subcategory TEXT,
    description TEXT,
    wiki_url TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consumer TEXT NOT NULL DEFAULT 'Me',
    started_at TEXT NOT NULL,
    ended_at TEXT,
    notes TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS ingestions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    substance_key TEXT NOT NULL,
    roa_id INTEGER NOT NULL,
    amount REAL NOT NULL,
    unit TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    consumer TEXT NOT NULL DEFAULT 'Me',
    notes TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ingestions_session ON ingestions(session_id);

CREATE TABLE IF NOT EXISTS effect_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    effect_id INTEGER NOT NULL,
    occurred_at TEXT NOT NULL,
    intensity TEXT,
    notes TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_effect_logs_session ON effect_logs(session_id);

CREATE TABLE IF NOT EXISTS substance_presets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    substance_key TEXT NOT NULL,
    roa_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    amount REAL NOT NULL
);
"""


def _range_minutes(duration_range: dict | None) -> tuple[float | None, float | None]:
    if not duration_range:
        return None, None
    units = duration_range.get("units") or "minutes"
    factor = {"seconds": 1 / 60, "minutes": 1.0, "hours": 60.0, "days": 1440.0}.get(units, 1.0)
    lo = duration_range.get("min")
    hi = duration_range.get("max")
    return (lo * factor if lo is not None else None, hi * factor if hi is not None else None)


class Store:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()
        self._reseed_reference_data()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def _init_schema(self) -> None:
        with closing(self._connect()) as connection:
            connection.executescript(SCHEMA)
            connection.commit()

    # ---- reference data (reseeded from bundled JSON on every startup) ----

    def _reseed_reference_data(self) -> None:
        substances = reference_data.load_substances()
        effects = reference_data.load_effects()
        interactions = reference_data.load_interactions()

        with closing(self._connect()) as connection:
            connection.execute("DELETE FROM duration_phases")
            connection.execute("DELETE FROM routes_of_administration")
            connection.execute("DELETE FROM substances")
            connection.execute("DELETE FROM interactions")
            connection.execute("DELETE FROM subjective_effects")

            for substance in substances:
                connection.execute(
                    """
                    INSERT INTO substances (
                        key, name, common_names, category, chemical_class, summary,
                        wiki_url, has_tolerance, tolerance_group, addiction_potential
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        substance["key"],
                        substance["name"],
                        json.dumps(substance["common_names"]),
                        substance["category"],
                        substance["chemical_class"],
                        substance["summary"],
                        substance["wiki_url"],
                        1 if substance["has_tolerance"] else 0,
                        substance["tolerance_group"],
                        substance["addiction_potential"],
                    ),
                )
                for roa in substance["roas"]:
                    light = roa["dose_light"] or {}
                    common = roa["dose_common"] or {}
                    strong = roa["dose_strong"] or {}
                    cursor = connection.execute(
                        """
                        INSERT INTO routes_of_administration (
                            substance_key, route, unit, dose_threshold,
                            dose_light_min, dose_light_max, dose_common_min, dose_common_max,
                            dose_strong_min, dose_strong_max, dose_heavy
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            substance["key"],
                            roa["route"],
                            roa["unit"],
                            roa["dose_threshold"],
                            light.get("min"),
                            light.get("max"),
                            common.get("min"),
                            common.get("max"),
                            strong.get("min"),
                            strong.get("max"),
                            roa["dose_heavy"],
                        ),
                    )
                    roa_id = cursor.lastrowid
                    for phase in ("onset", "comeup", "peak", "offset", "total", "afterglow"):
                        lo, hi = _range_minutes((roa["duration"] or {}).get(phase))
                        if lo is None and hi is None:
                            continue
                        connection.execute(
                            "INSERT INTO duration_phases (roa_id, phase, min_minutes, max_minutes) VALUES (?, ?, ?, ?)",
                            (roa_id, phase, lo, hi),
                        )

            for interaction in interactions:
                connection.execute(
                    "INSERT INTO interactions (substance_a, substance_b, risk_level, note) VALUES (?, ?, ?, ?)",
                    (
                        interaction["substance_a"],
                        interaction["substance_b"],
                        interaction["risk_level"],
                        interaction["note"],
                    ),
                )

            for effect in effects:
                connection.execute(
                    "INSERT INTO subjective_effects (name, category, subcategory, description, wiki_url) VALUES (?, ?, ?, ?, ?)",
                    (
                        effect["name"],
                        effect["category"],
                        effect["subcategory"],
                        effect.get("description"),
                        effect.get("wiki_url"),
                    ),
                )
            connection.commit()

    def _row_to_roa(self, connection: sqlite3.Connection, row: sqlite3.Row) -> RouteOfAdministration:
        phase_rows = connection.execute(
            "SELECT phase, min_minutes, max_minutes FROM duration_phases WHERE roa_id = ?", (row["id"],)
        ).fetchall()
        durations = tuple(
            DurationPhase(phase=p["phase"], min_minutes=p["min_minutes"], max_minutes=p["max_minutes"])
            for p in phase_rows
        )

        def dose_range(min_key: str, max_key: str) -> DoseRange | None:
            if row[min_key] is None and row[max_key] is None:
                return None
            return DoseRange(min=row[min_key], max=row[max_key])

        return RouteOfAdministration(
            id=row["id"],
            substance_key=row["substance_key"],
            route=row["route"],
            unit=row["unit"],
            dose_threshold=row["dose_threshold"],
            dose_light=dose_range("dose_light_min", "dose_light_max"),
            dose_common=dose_range("dose_common_min", "dose_common_max"),
            dose_strong=dose_range("dose_strong_min", "dose_strong_max"),
            dose_heavy=row["dose_heavy"],
            durations=durations,
        )

    def list_substances(self) -> list[Substance]:
        with closing(self._connect()) as connection:
            substance_rows = connection.execute("SELECT * FROM substances ORDER BY name").fetchall()
            result = []
            for srow in substance_rows:
                roa_rows = connection.execute(
                    "SELECT * FROM routes_of_administration WHERE substance_key = ? ORDER BY route",
                    (srow["key"],),
                ).fetchall()
                roas = tuple(self._row_to_roa(connection, r) for r in roa_rows)
                result.append(
                    Substance(
                        key=srow["key"],
                        name=srow["name"],
                        common_names=tuple(json.loads(srow["common_names"])),
                        category=srow["category"],
                        chemical_class=srow["chemical_class"],
                        summary=srow["summary"],
                        wiki_url=srow["wiki_url"],
                        has_tolerance=bool(srow["has_tolerance"]),
                        tolerance_group=srow["tolerance_group"],
                        addiction_potential=srow["addiction_potential"],
                        roas=roas,
                    )
                )
            return result

    def get_substance(self, key: str) -> Substance | None:
        return next((s for s in self.list_substances() if s.key == key), None)

    def list_effects(self) -> list[SubjectiveEffect]:
        with closing(self._connect()) as connection:
            rows = connection.execute("SELECT * FROM subjective_effects ORDER BY category, name").fetchall()
        return [
            SubjectiveEffect(
                id=row["id"],
                name=row["name"],
                category=row["category"],
                subcategory=row["subcategory"],
                description=row["description"],
                wiki_url=row["wiki_url"],
            )
            for row in rows
        ]

    def recent_effects(self, limit: int = 8) -> list[SubjectiveEffect]:
        with closing(self._connect()) as connection:
            rows = connection.execute(
                """
                SELECT se.* FROM subjective_effects se
                JOIN (
                    SELECT effect_id, MAX(occurred_at) AS last_used
                    FROM effect_logs
                    GROUP BY effect_id
                ) recent ON recent.effect_id = se.id
                ORDER BY recent.last_used DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [
            SubjectiveEffect(
                id=row["id"],
                name=row["name"],
                category=row["category"],
                subcategory=row["subcategory"],
                description=row["description"],
                wiki_url=row["wiki_url"],
            )
            for row in rows
        ]

    def lookup_interaction(self, substance_a: str, substance_b: str) -> Interaction | None:
        pair = tuple(sorted((substance_a, substance_b)))
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT * FROM interactions WHERE substance_a = ? AND substance_b = ?", pair
            ).fetchone()
        if row is None:
            return None
        return Interaction(
            substance_a=row["substance_a"], substance_b=row["substance_b"], risk_level=row["risk_level"], note=row["note"]
        )

    # ---- sessions ----

    def start_session(self, consumer: str, started_at: datetime, notes: str = "") -> int:
        with closing(self._connect()) as connection:
            cursor = connection.execute(
                "INSERT INTO sessions (consumer, started_at, ended_at, notes) VALUES (?, ?, NULL, ?)",
                (consumer, started_at.isoformat(timespec="seconds"), notes),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def end_session(self, session_id: int, ended_at: datetime) -> None:
        with closing(self._connect()) as connection:
            connection.execute(
                "UPDATE sessions SET ended_at = ? WHERE id = ?",
                (ended_at.isoformat(timespec="seconds"), session_id),
            )
            connection.commit()

    def get_open_session(self, consumer: str) -> Session | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT * FROM sessions WHERE consumer = ? AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1",
                (consumer,),
            ).fetchone()
        return self._row_to_session(row) if row else None

    def get_session(self, session_id: int) -> Session | None:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
        return self._row_to_session(row) if row else None

    def list_sessions(self, consumer: str | None = None) -> list[Session]:
        with closing(self._connect()) as connection:
            if consumer and consumer != "All":
                rows = connection.execute(
                    "SELECT * FROM sessions WHERE consumer = ? ORDER BY started_at DESC", (consumer,)
                ).fetchall()
            else:
                rows = connection.execute("SELECT * FROM sessions ORDER BY started_at DESC").fetchall()
        return [self._row_to_session(row) for row in rows]

    @staticmethod
    def _row_to_session(row: sqlite3.Row) -> Session:
        return Session(
            id=row["id"],
            consumer=row["consumer"],
            started_at=datetime.fromisoformat(row["started_at"]),
            ended_at=datetime.fromisoformat(row["ended_at"]) if row["ended_at"] else None,
            notes=row["notes"],
        )

    # ---- ingestions ----

    def add_ingestion(self, ingestion: Ingestion) -> int:
        now = datetime.now().isoformat(timespec="seconds")
        with closing(self._connect()) as connection:
            cursor = connection.execute(
                """
                INSERT INTO ingestions (
                    session_id, substance_key, roa_id, amount, unit, occurred_at, consumer, notes, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    ingestion.session_id,
                    ingestion.substance_key,
                    ingestion.roa_id,
                    ingestion.amount,
                    ingestion.unit,
                    ingestion.occurred_at.isoformat(timespec="seconds"),
                    ingestion.consumer,
                    ingestion.notes,
                    now,
                    now,
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_ingestions_for_session(self, session_id: int) -> list[Ingestion]:
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM ingestions WHERE session_id = ? ORDER BY occurred_at", (session_id,)
            ).fetchall()
        return [self._row_to_ingestion(row) for row in rows]

    def delete_ingestion(self, ingestion_id: int) -> None:
        with closing(self._connect()) as connection:
            connection.execute("DELETE FROM ingestions WHERE id = ?", (ingestion_id,))
            connection.commit()

    @staticmethod
    def _row_to_ingestion(row: sqlite3.Row) -> Ingestion:
        return Ingestion(
            id=row["id"],
            session_id=row["session_id"],
            substance_key=row["substance_key"],
            roa_id=row["roa_id"],
            amount=row["amount"],
            unit=row["unit"],
            occurred_at=datetime.fromisoformat(row["occurred_at"]),
            consumer=row["consumer"],
            notes=row["notes"],
        )

    # ---- effect logs ----

    def add_effect_log(self, effect_log: EffectLog) -> int:
        with closing(self._connect()) as connection:
            cursor = connection.execute(
                "INSERT INTO effect_logs (session_id, effect_id, occurred_at, intensity, notes) VALUES (?, ?, ?, ?, ?)",
                (
                    effect_log.session_id,
                    effect_log.effect_id,
                    effect_log.occurred_at.isoformat(timespec="seconds"),
                    effect_log.intensity,
                    effect_log.notes,
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_effect_logs_for_session(self, session_id: int) -> list[EffectLog]:
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM effect_logs WHERE session_id = ? ORDER BY occurred_at", (session_id,)
            ).fetchall()
        return [
            EffectLog(
                id=row["id"],
                session_id=row["session_id"],
                effect_id=row["effect_id"],
                occurred_at=datetime.fromisoformat(row["occurred_at"]),
                intensity=row["intensity"],
                notes=row["notes"],
            )
            for row in rows
        ]

    # ---- substance presets ----

    def list_presets(self, substance_key: str | None = None) -> list[SubstancePreset]:
        with closing(self._connect()) as connection:
            if substance_key:
                rows = connection.execute(
                    "SELECT * FROM substance_presets WHERE substance_key = ? ORDER BY name", (substance_key,)
                ).fetchall()
            else:
                rows = connection.execute("SELECT * FROM substance_presets ORDER BY name").fetchall()
        return [
            SubstancePreset(id=row["id"], substance_key=row["substance_key"], roa_id=row["roa_id"], name=row["name"], amount=row["amount"])
            for row in rows
        ]

    def save_preset(self, preset: SubstancePreset) -> int:
        with closing(self._connect()) as connection:
            cursor = connection.execute(
                "INSERT INTO substance_presets (substance_key, roa_id, name, amount) VALUES (?, ?, ?, ?)",
                (preset.substance_key, preset.roa_id, preset.name, preset.amount),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def delete_preset(self, preset_id: int) -> None:
        with closing(self._connect()) as connection:
            connection.execute("DELETE FROM substance_presets WHERE id = ?", (preset_id,))
            connection.commit()

    # ---- consumers ----

    def list_consumers(self) -> list[str]:
        with closing(self._connect()) as connection:
            rows = connection.execute("SELECT DISTINCT consumer FROM sessions ORDER BY consumer").fetchall()
        return [str(row["consumer"]) for row in rows] if rows else ["Me"]
