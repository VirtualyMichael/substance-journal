# Substance Journal

Local, offline, dark-mode desktop journal for logging substance ingestions, tracking
subjective effects against PsychonautWiki's Subjective Effect Index, and surfacing
dosing/duration/interaction reference data. Windows and Linux are both supported.

This is a companion project to [Alcohol Tracker](../Alcohol%20ingestion%20marking%20app),
reusing its architecture (PySide6 + SQLite + PyInstaller) but generalized to many
substances instead of just alcohol.

Tracked substances (v1): Alcohol, Nicotine, Cannabis (flower/concentrate/edible),
Psilocybin, LSD, DMT, MDMA, 2C-B, Ketamine.

## Data sources

Reference data (dosing, duration, interactions, subjective effects) is synced from:

- [PsychonautWiki](https://psychonautwiki.org) via its [Bifrost GraphQL API](https://github.com/psychonautwiki/bifrost)
- [TripSit](https://tripsit.me)'s open [drug combination dataset](https://github.com/TripSit/drugs)

into `data/*.json`, which is bundled with the app so it runs fully offline. Run
`scripts/sync_substance_data.py` to refresh it.

This is a harm-reduction journaling tool, not a source of synthesis, sourcing, or
acquisition information. All effect/dose/duration/interaction data comes from the
publicly published harm-reduction references above.

## Build (Windows)

```powershell
.\build.ps1
```

## Build (Linux)

```bash
./build.sh
```

## Run During Development

```bash
python3 -m venv .venv
source .venv/bin/activate   # or .venv\Scripts\Activate.ps1 on Windows
python -m pip install -r requirements.txt
python -m substance_journal
```

## Test

```bash
.venv/bin/python -m unittest tests.test_core   # or .venv\Scripts\python.exe on Windows
```

## Accuracy Note

All dosing, duration, tolerance, and interaction information is for harm-reduction
journaling only. It is not medical advice, and using any of these substances carries
real risk regardless of what this app displays.
