"""Copy the reference data into the Flutter app's assets.

Flutter can only bundle files inside app/, so data/*.json (the single source of truth,
refreshed by sync_substance_data.py) is copied to app/assets/data/. Run after changing data:

    python scripts/sync_app_assets.py
"""
from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data"
TARGET = ROOT / "app" / "assets" / "data"


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    for name in ("substances.json", "effects.json", "interactions.json"):
        shutil.copyfile(SOURCE / name, TARGET / name)
        print(f"copied {name}")


if __name__ == "__main__":
    main()
