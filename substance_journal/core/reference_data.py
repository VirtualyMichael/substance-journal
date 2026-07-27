from __future__ import annotations

import json
import sys
from functools import lru_cache
from pathlib import Path

# Bump when data/*.json changes shape in a way that requires re-seeding existing
# databases (not just refreshed values) - see database.py's seed-once check.
DATA_VERSION = 1


def _data_dir() -> Path:
    # PyInstaller extracts --add-data files under sys._MEIPASS at runtime (both
    # onefile and onedir builds); fall back to the source tree layout in dev mode.
    bundle_root = getattr(sys, "_MEIPASS", None)
    if bundle_root:
        return Path(bundle_root) / "data"
    return Path(__file__).resolve().parent.parent.parent / "data"


_DATA_DIR = _data_dir()


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
