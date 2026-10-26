# Graph Report - app  (2026-10-26)

## Corpus Check
- 133 files · ~78,296 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 536 nodes · 442 edges · 54 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output
- Edge kinds: contains: 442


## Input Scope
- Requested: tracked
- Resolved: tracked (source: cli)
- Included files: 133 · Candidates: 211
- Excluded: 0 untracked · 6127 ignored · 0 sensitive · 0 missing committed
- Recommendation: Use --scope all or graphify.yaml inputs.corpus for a knowledge-base folder.

## Graph Freshness
- Built from Git commit: `bd54140`
- Compare this hash to `git rev-parse HEAD` before trusting freshness-sensitive graph output.
## God Nodes (most connected - your core abstractions)
1. `SubstanceJournalApp` - 1 edges
2. `_SubstanceJournalAppState` - 1 edges
3. `AddIngestionPage` - 1 edges
4. `_AddIngestionPageState` - 1 edges
5. `AdvisoryList` - 1 edges
6. `CustomUnitChoice` - 1 edges
7. `DoseInput` - 1 edges
8. `DoseStorage` - 1 edges
9. `DoseBands` - 1 edges
10. `DoseEditor` - 1 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Community 0"
Cohesion: 0.10
Nodes (3): AlcoholIngestion, EstimateSettings, SessionExposure

### Community 1 - "Community 1"
Cohesion: 0.10
Nodes (10): _AlcoholCalculator, _CannabisForm, CustomUnitChoice, DoseBands, DoseEditor, DoseInput, DoseStorage, _GenericForm (+2 more)

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (5): _PairingCodeDialog, _SendSheet, _SendSheetState, SyncPage, _SyncPageState

### Community 3 - "Community 3"
Cohesion: 0.13
Nodes (4): ReferenceLine, TimelineChart, _TimelineChartState, TimelinePainter

### Community 4 - "Community 4"
Cohesion: 0.15
Nodes (7): _ImportRecipesDialog, _ImportRecipesDialogState, RecipeDetailPage, RecipeEditorPage, _RecipeEditorPageState, RecipesPage, _RecipesPageState

### Community 5 - "Community 5"
Cohesion: 0.17
Nodes (2): AddIngestionPage, _AddIngestionPageState

### Community 6 - "Community 6"
Cohesion: 0.17
Nodes (4): _DrinkDialog, _DrinkDialogState, _PresetDialog, _PresetDialogState

### Community 7 - "Community 7"
Cohesion: 0.17
Nodes (3): FrameAssembler, PairingCode, SyncCryptoException

### Community 8 - "Community 8"
Cohesion: 0.18
Nodes (4): ExperiencePage, _ExperiencePageState, _IngestionTile, _RatingTile

### Community 9 - "Community 9"
Cohesion: 0.18
Nodes (2): _AutomaticCopies, BackupSection

### Community 10 - "Community 10"
Cohesion: 0.18
Nodes (6): _CompoundSearchDialog, _CompoundSearchDialogState, _IndividualDosesDialog, _IndividualDosesDialogState, PwReviewPage, _PwReviewPageState

### Community 11 - "Community 11"
Cohesion: 0.18
Nodes (5): at, Bioavailability, CannabisCurve, CannabisCurveShape, CannabisDoseEstimate

### Community 12 - "Community 12"
Cohesion: 0.20
Nodes (5): AlcoholDayView, DrinkTile, QuickAddBar, _QuickAddBarState, _StatusCard

### Community 13 - "Community 13"
Cohesion: 0.20
Nodes (5): AlcoholSettingsSection, EstimateSettingsForm, _EstimateSettingsFormState, LimitsForm, _LimitsFormState

### Community 14 - "Community 14"
Cohesion: 0.20
Nodes (6): QrCard, QrFramePlayer, _QrFramePlayerState, QrScanPage, _QrScanPageState, ScanDone

### Community 15 - "Community 15"
Cohesion: 0.22
Nodes (3): _BarsPainter, DailyBarsChart, MonthHeatmap

### Community 16 - "Community 16"
Cohesion: 0.22
Nodes (5): CalendarPage, _CalendarPageState, _DayCell, _DaySheet, _PersonBadge

### Community 17 - "Community 17"
Cohesion: 0.22
Nodes (3): CurveIngestion, IntensityCurve, TrapezoidCurve

### Community 18 - "Community 18"
Cohesion: 0.22
Nodes (3): Recipe, RecipeFormatException, RecipeIngredient

### Community 19 - "Community 19"
Cohesion: 0.22
Nodes (1): TestApp

### Community 21 - "Community 21"
Cohesion: 0.22
Nodes (1): Gap

### Community 23 - "Community 23"
Cohesion: 0.25
Nodes (3): InteractionWarning, names, TripSitPair

### Community 24 - "Community 24"
Cohesion: 0.25
Nodes (1): _FailingDb

### Community 28 - "Community 28"
Cohesion: 0.33
Nodes (2): _ConfirmDialog, _ResultDialog

### Community 29 - "Community 29"
Cohesion: 0.33
Nodes (2): _CustomSubstanceDialog, _CustomSubstanceDialogState

### Community 31 - "Community 31"
Cohesion: 0.33
Nodes (2): _CustomUnitDialog, _CustomUnitDialogState

### Community 32 - "Community 32"
Cohesion: 0.40
Nodes (2): CompoundDetailPage, CompoundsPage

### Community 33 - "Community 33"
Cohesion: 0.40
Nodes (3): InsightsPage, _InsightsPageState, _Stat

### Community 34 - "Community 34"
Cohesion: 0.40
Nodes (2): EditIngestionDialog, _EditIngestionDialogState

### Community 35 - "Community 35"
Cohesion: 0.40
Nodes (2): SubstanceJournalApp, _SubstanceJournalAppState

### Community 36 - "Community 36"
Cohesion: 0.40
Nodes (2): DrinkLimits, LimitStatus

### Community 37 - "Community 37"
Cohesion: 0.40
Nodes (1): UsageStat

### Community 38 - "Community 38"
Cohesion: 0.40
Nodes (2): DoseAdvisory, PastDose

### Community 39 - "Community 39"
Cohesion: 0.40
Nodes (4): DoseRange, DurationPhase, RouteOfAdministration, Substance

### Community 40 - "Community 40"
Cohesion: 0.40
Nodes (1): UseEvent

### Community 41 - "Community 41"
Cohesion: 0.40
Nodes (3): MonthSummary, SubstanceUsage, UsageEntry

### Community 44 - "Community 44"
Cohesion: 0.40
Nodes (2): TimelineMarker, TimelineSeries

### Community 46 - "Community 46"
Cohesion: 0.40
Nodes (3): AppShell, _AppShellState, PersonSwitcher

### Community 47 - "Community 47"
Cohesion: 0.50
Nodes (3): AlcoholAnalyticsPage, _AlcoholAnalyticsPageState, ToleranceSummary

### Community 48 - "Community 48"
Cohesion: 0.50
Nodes (1): DayPerson

### Community 49 - "Community 49"
Cohesion: 0.50
Nodes (2): CompoundPicker, _CompoundPickerState

### Community 51 - "Community 51"
Cohesion: 0.50
Nodes (1): _ResultDialog

### Community 52 - "Community 52"
Cohesion: 0.50
Nodes (1): Hlc

### Community 53 - "Community 53"
Cohesion: 0.50
Nodes (1): ToleranceTrack

### Community 58 - "Community 58"
Cohesion: 0.50
Nodes (2): aliases, names

### Community 60 - "Community 60"
Cohesion: 0.67
Nodes (2): TolerancePage, _TrackCard

### Community 61 - "Community 61"
Cohesion: 0.67
Nodes (1): JournalPage

### Community 63 - "Community 63"
Cohesion: 0.67
Nodes (1): SettingsPage

### Community 65 - "Community 65"
Cohesion: 0.67
Nodes (1): names

### Community 71 - "Community 71"
Cohesion: 1.00
Nodes (1): AdvisoryList

### Community 72 - "Community 72"
Cohesion: 1.00
Nodes (1): AlcoholHistoryPage

### Community 73 - "Community 73"
Cohesion: 1.00
Nodes (1): AlcoholDaySummary

### Community 91 - "Community 91"
Cohesion: 1.00
Nodes (1): CustomUnitPicker

### Community 92 - "Community 92"
Cohesion: 1.00
Nodes (1): CustomUnitsPage

## Knowledge Gaps
- **145 isolated node(s):** `SubstanceJournalApp`, `_SubstanceJournalAppState`, `AddIngestionPage`, `_AddIngestionPageState`, `AdvisoryList` (+140 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 5`** (2 nodes): `AddIngestionPage`, `_AddIngestionPageState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (2 nodes): `_AutomaticCopies`, `BackupSection`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `TestApp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (1 nodes): `Gap`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `_FailingDb`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (2 nodes): `_ConfirmDialog`, `_ResultDialog`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (2 nodes): `_CustomSubstanceDialog`, `_CustomSubstanceDialogState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (2 nodes): `_CustomUnitDialog`, `_CustomUnitDialogState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (2 nodes): `CompoundDetailPage`, `CompoundsPage`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (2 nodes): `EditIngestionDialog`, `_EditIngestionDialogState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (2 nodes): `SubstanceJournalApp`, `_SubstanceJournalAppState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (2 nodes): `DrinkLimits`, `LimitStatus`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `UsageStat`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (2 nodes): `DoseAdvisory`, `PastDose`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (1 nodes): `UseEvent`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (2 nodes): `TimelineMarker`, `TimelineSeries`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 48`** (1 nodes): `DayPerson`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 49`** (2 nodes): `CompoundPicker`, `_CompoundPickerState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 51`** (1 nodes): `_ResultDialog`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 52`** (1 nodes): `Hlc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (1 nodes): `ToleranceTrack`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 58`** (2 nodes): `aliases`, `names`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 60`** (2 nodes): `TolerancePage`, `_TrackCard`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 61`** (1 nodes): `JournalPage`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 63`** (1 nodes): `SettingsPage`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 65`** (1 nodes): `names`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 71`** (1 nodes): `AdvisoryList`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 72`** (1 nodes): `AlcoholHistoryPage`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 73`** (1 nodes): `AlcoholDaySummary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 91`** (1 nodes): `CustomUnitPicker`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 92`** (1 nodes): `CustomUnitsPage`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `SubstanceJournalApp`, `_SubstanceJournalAppState`, `AddIngestionPage` to the rest of the system?**
  _145 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._