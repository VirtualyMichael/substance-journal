# Substance Journal

A private, offline harm-reduction journal for Windows and Android (Linux and iOS build from the
same code). Log what you take, see effect timelines, get dose and interaction heads-ups, and keep
your phone and computer in sync with no account and no server. Your data never leaves your devices.

> Harm-reduction tool, not medical advice. Estimates (BAC, dose classes, effect curves, tolerance)
> are guides, not measurements. It contains no synthesis, sourcing or acquisition information.

## What it does

- **Journal and timelines:** experiences with doses, notes and ratings; combined effect curves per
  substance with hover read-outs; per-substance toggles to see each alone or overlapping.
- **Per-person:** every curve, tolerance estimate and warning is for one person, with several
  people on one device and a calendar showing who was on which day.
- **Safety:** warnings for strong or repeat doses, high daily totals and raised tolerance; a
  tolerance and break page; drinking limits with alerts.
- **Alcohol mode:** fl oz, shots and standard drinks, BAC estimate, a library of 100+ recipes, and
  import from [Alcohol Tracker](https://github.com/VirtualyMichael/alcohol-tracker).
- **Cannabis:** absorbed-dose estimates by method, saved strains and batches with usage and spend.
- **Import:** PsychonautWiki Journal exports, with a review screen to choose what to keep. Importing
  twice never overwrites, resurrects or duplicates anything.
- **Sync without a server:** automatic over Wi-Fi, or by QR codes, a file or pasted text. All packages
  are encrypted with a key shared at pairing; edits and deletes merge.
- **Backup:** encrypted backups with a passphrase, CSV and JSON export, automatic daily copies.
- **Reminders:** daily check-in and limit alerts, local to the device.
- **Voice and AI:** [`mcp/substance-journal`](mcp/substance-journal) lets an assistant log doses
  (with a read-back and a yes) and produce reports.

## Download

Get the latest build from [Releases](../../releases): the Android `.apk` and a Windows `.zip`
(unzip and run `substance_journal_app.exe`).

## Build it yourself

Flutter 3.4x or newer. From `app/`:

```bash
flutter pub get
flutter test
flutter run -d windows        # or an Android device
flutter build windows --release
flutter build apk --release
```

`app/packages/sj_core` holds the pure-Dart logic (reference data, dosing, sync, backup). GitHub
Actions builds and tests all platforms on every push. The original Python/PySide6 prototype is still
in `substance_journal/`.

## Reference data and credit

Dose, duration and interaction data comes from [PsychonautWiki](https://psychonautwiki.org) (CC BY-SA 4.0)
and [TripSit](https://tripsit.me)'s open combination dataset. Nine compounds are audited by hand against
several sources. Of the other 272, those whose dose bands and timings agree with TripSit's open dataset are marked
cross-checked, where they disagree the app says so and tells you to start with the lower figure, and the rest are
copied from PsychonautWiki and marked as not checked (`scripts/crosscheck_tripsit.py`, report in `docs/data-audit/crosscheck.md`). See
[docs/ATTRIBUTION.md](docs/ATTRIBUTION.md) and [docs/ROADMAP.md](docs/ROADMAP.md).

## License

Code: GPL-3.0 (see [LICENSE](LICENSE)). Reference data derived from PsychonautWiki stays under
CC BY-SA 4.0.
