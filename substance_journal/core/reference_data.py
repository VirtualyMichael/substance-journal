from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

# Bump when data/*.json changes shape in a way that requires re-seeding existing
# databases (not just refreshed values) - see database.py's seed-once check.
DATA_VERSION = 1

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"


def _load_json(name: str) -> list[dict]:
    path = _DATA_DIR / name
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def load_substances() -> list[dict]:
    return _load_json("substances.json")


@lru_cache(maxsize=1)
def load_effects() -> list[dict]:
    return _load_json("effects.json")


@lru_cache(maxsize=1)
def load_interactions() -> list[dict]:
    return _load_json("interactions.json")
