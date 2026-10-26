# Substance Journal 2: one app for PC and phone

Decisions made with you: **Flutter** (Windows, Linux, Android, iOS), **direct device-to-device sync with QR pairing**, and the PySide6 app is **frozen** (it keeps the audited data fixes, no more feature work). The new app replaces both Substance Journal and Alcohol Tracker.

## 1. What the PsychonautWiki Journal does (research)
Sources: the app's wiki page ([PsychonautWiki Journal](https://psychonautwiki.org/wiki/PsychonautWiki_Journal)), its store listings, and the Android source ([isaakhanimann/psychonautwiki-journal-android](https://github.com/isaakhanimann/psychonautwiki-journal-android)). The wiki page itself lists only logging, notes, an experience overview, offline reference data and on-device privacy, so the detail below comes from the source tree.

**Licence note.** The Android repo is GPL-3.0 and was archived on 2025-11-08; the maintained version is closed source. We will use it only to learn which features exist and design everything our own way, with no copied code, so our app's licence stays ours.

| Area | What it has | Our version |
|---|---|---|
| **Tabs** | Journal, Search (substances), Safer, Stats, Settings | Today, Journal, Compounds, Insights, Safer use, Settings |
| **Experience** | A session with title, notes, creation and sort date, favourite flag, location (name plus coordinates) | Same, plus a person (consumer) on every experience, tags, and photos later |
| **Ingestion** | Substance, route, time and optional end time, dose, "dose is an estimate" with standard deviation, unit, notes, stomach fullness (shifts oral onset), consumer name, optional custom unit | Same fields, plus product (strain, batch, purity) and our absorbed-dose model |
| **Add flow** | Search, route, check interactions, safer-use check, dose with live dose-class label (threshold to heavy), purity calculator, unknown-dose option, then time/date and colour | Same stepped flow, but each step is skippable from a quick-add chip |
| **Custom units** | "1 pill = 120 mg MDMA", with estimate, archive and plural names | Same, shared across devices |
| **Custom substances** | User-defined compounds with their own routes | Same |
| **Timeline** | Overlaid per-ingestion curves (onset, comeup, peak, offset) weighted by dose, colour per substance, timed notes and ratings drawn on the axis, "explain timeline" screen | Same idea with our per-substance models: alcohol uses the BAC model, cannabis uses route curves |
| **Timed notes** | A note at a time, with a colour, optionally shown on the timeline | Same |
| **Ratings** | Shulgin scale (-, plus/minus, +, ++, +++) with time | Same, plus 0-10 mood/pain/sleep sliders |
| **Calendar** | Month calendar of experiences, per-day lists | Same, with the multi-person progress badges below |
| **Stats** | Bar charts of use per substance and period, per-substance page with last use and tolerance timing | Usage over time, heatmap, tolerance and T-break, correlations, exports |
| **Safer use** | Dose guide, route explanations, drug testing, reagent testing, volumetric dosing, safer hallucinogens/sniffing/stimulants pages | Same pages, written in our own words, plus a volumetric-dosing calculator |
| **Settings** | Substance colours, combination (interaction) settings, custom units, export/import, FAQ, hidden-substance toggle | Same, plus appearance, units, PIN lock, sync |
| **Reference data** | PsychonautWiki offline, plus TripSit and saferparty.ch | Our audited `data/*.json` with sources and confidence |
| **Privacy** | All data on device | Same; sync is direct between your devices, end-to-end encrypted, no account |

## 2. Your new requirements
1. **Compound picker.** Search box plus ordering by your history: most used, most recent, favourites, then everything else. You can hide compounds you never use and reveal them again. The picker is the first step of Add and also has its own tab.
2. **Alcohol mode.** A switch that turns the whole app into the Alcohol Tracker experience: only alcohol, drink presets, quick-add bar, BAC timeline, standard-drink analytics. It can be toggled in Settings or from a header chip, and remembered per device. Alcohol data stays in the same journal, so switching back loses nothing.
3. **People never mix.** Every experience, ingestion, effect log, tolerance track and curve belongs to one person. Charts, tolerance, interaction warnings and stats are always computed for the selected person only. There is no combined curve. A test asserts that adding person B's ingestion never changes person A's curve, tolerance or warnings.
4. **Multi-person day badge.** On the calendar, any day with more than one person gets a small icon showing each person's progress through their experience at that moment, as a whole-number percent (for example 50% and 20%). Progress is elapsed time from that person's first ingestion to the end of their last expected offset (or the end of the curve), clamped to 0-100 and rounded to whole numbers. Finished days show 100%. The badge updates live for today.
5. **PsychonautWiki-Journal feature set** (table above), built our own way.
6. **Desktop <-> phone sync** over QR pairing.
7. **Platforms.** Windows, Linux, Android, iOS (macOS comes free with Flutter).

## 3. Architecture
- **Repo layout** (in the existing `substance-journal` repo): `app/` (Flutter), `app/packages/core` (pure-Dart domain: models, PK/curve engines, tolerance, analytics, sync merge), `data/` (reference JSON, unchanged), `scripts/` (Python sync + overrides, unchanged), `legacy/` notes for the frozen PySide6 code (code stays where it is).
- **Storage.** SQLite through Drift. Every record has a UUID, `updatedAt` (hybrid logical clock), `deletedAt` (tombstone) and `deviceId`. The file stays plain SQLite so the MCP server can still read it.
- **Reference data.** Bundled as assets from `data/*.json`; the Python sync script remains the way they are refreshed.
- **Logic port.** The alcohol BAC/tolerance engine (Alcohol Tracker `core/calculations.py`, `analytics.py`), the effect curves, `core/tolerance.py` and the cannabis model are ported to Dart. A Python script exports golden test vectors (inputs and expected outputs) so the Dart tests prove identical numbers.
- **UI.** Material 3 with our design tokens, adaptive layouts: bottom navigation on phones, navigation rail plus split panes on desktop, charts with `fl_chart`.
- **Multi-person model.** `Person` table; `personId` on experiences, ingestions, effect logs, ratings, presets (shared presets optional). A single "current person" selector in the header filters every query.

### Sync design
- **Pairing.** Desktop shows a QR code containing: device id, public key (X25519), one-time pairing secret, and its addresses (LAN IP and Tailscale IP if present). The phone scans it, both sides derive a shared key and each stores the other as a trusted peer. A short confirmation code is shown on both screens to defeat a wrong-device scan.
- **Transport.** Direct connection over Wi-Fi or Tailscale, discovery via mDNS and the addresses in the QR, authenticated and encrypted with the Noise protocol (or libsodium sealed streams). No server, no account.
- **Protocol.** Each device keeps a per-peer "last seen clock". On connect they exchange changes since that clock, per table. Merge rule: highest hybrid logical clock wins per record; deletes are tombstones; edits to different fields of the same record are merged field by field.
- **What syncs.** People, experiences, ingestions, notes, ratings, custom units/substances, presets, products, limits, settings that are marked shared. Reference data does not sync.
- **Triggers.** On app open, after saving, on a timer while foreground, and a manual "Sync now". Background sync on Android; iOS syncs when open (platform limit).
- **Failure handling.** Interrupted sync resumes; a backup snapshot is taken before applying remote changes; a conflict log lists anything overwritten.

### Platform notes
- Windows and Linux: Flutter desktop builds, installer (Inno Setup) and AppImage/tarball.
- Android: APK now, store later.
- iOS: needs a Mac with Xcode and an Apple developer account ($99/year) to build and install. I can write and test everything else; the iOS build step would need your Mac or a cloud Mac build service.
- Flutter is not installed on this PC (also missing the Android SDK). Installing them means downloading about 2-3 GB, which I will ask you to approve.

## 4. Phases
Each phase ends with passing tests, and a build you can open.

0. **Done:** reference data audit and fixes (branch `data-audit-fixes`).
1. **Foundations.** Install Flutter and the Android SDK; create `app/`; core package with models, UUID/HLC ids, Drift schema; asset loader for `data/*.json`; golden-vector exporter in Python; CI-style test script.
2. **Engines in Dart.** Port alcohol BAC and tolerance, generic effect curves, substance tolerance, cannabis dosing; prove parity with golden tests (including a round trip of your `8-23-2026 Backup Alcohol.json`).
3. **Journal core.** People, experiences, ingestions with the add flow, compound picker (search, history sort, favourites, hide), custom units and substances, timeline, timed notes, ratings, interaction checker.
4. **Calendar, multi-person and Alcohol mode.** Calendar with the whole-number progress badges, strict per-person isolation tests, Alcohol mode with presets, quick add and analytics.
5. **Insights and cannabis.** Stats, heatmap, tolerance and T-break, correlations, export (CSV/JSON), reports; cannabis products, absorbed-dose calculator and route curves; psilocybin grams and nicotine product presets.
6. **Sync.** Pairing, transport, merge, conflict log; tests with two simulated devices (including clock skew, offline edits, deletes) before any real phone test.
7. **Safer-use content and polish.** Dose guide, drug testing, volumetric dosing, themes, PIN lock, backups, empty states, accessibility.
8. **Ship.** Windows installer, Linux package, Android APK, iOS build when a Mac is available; migrate your Alcohol Tracker and Substance Journal databases; retire the old apps.
9. **Extras.** Limits and reminders, daily check-in, encrypted backup, MCP/voice server for the new schema.

## 5. Risks and open points
- A rewrite is large. Phases 1-4 are the critical path; sync and cannabis modelling can ship after the first usable build.
- iOS needs Apple tooling you may not have; Android, Windows and Linux do not.
- Browser/web build is possible later (Flutter web) but is not planned.
- Alcohol Tracker's MCP server reads its own SQLite file today; it will need to point at the new database in phase 9.

## Status (2026-10-25)
- **Phase 1 done:** Flutter app, core package, sync-ready database, compound ordering.
- **Phase 2 done:** alcohol model, generic curves and cannabis dosing in Dart, checked against Python goldens.
- **Phase 3 mostly done:** people with strict per-person scoping, experiences, the add flow (compound, route, interaction check, dose, time), compound picker (search, history, favourites, hidden), timeline chart, timed notes, ratings, settings, adaptive phone/desktop layout, light and dark themes.
- **Phase 3 not yet built:** custom units ("1 pill = 120 mg"), custom substances, editing an ingestion's compound or route, per-ingestion colour choice, the calendar view and multi-person progress badge (phase 4), Alcohol mode (phase 4).
- **Screenshots without launching the app:** `SJ_SCREENSHOTS_DIR=<dir> flutter test test/screenshots_test.dart` renders the main screens to PNG.
