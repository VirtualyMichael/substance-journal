import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import 'data/custom_substances.dart';
import 'data/database.dart';
import 'data/reference_repository.dart';

/// Overridden at startup (and in tests) with real instances.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider'));
final referenceProvider = Provider<ReferenceRepository>((ref) => throw UnimplementedError('referenceProvider'));
final interactionPairsProvider = Provider<List<TripSitPair>>((ref) => const []);

/// The time "now", overridable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ---- compounds: reference data plus the user's own ----

final customSubstancesProvider =
    StreamProvider<List<CustomSubstance>>((ref) => ref.watch(databaseProvider).watchCustomSubstances());

final customUnitsProvider = StreamProvider<List<CustomUnit>>((ref) => ref.watch(databaseProvider).watchCustomUnits());

/// Everything the UI should look compounds up in: bundled reference data plus custom
/// compounds. Deleted custom compounds still resolve (for old ingestions) but are not offered.
final catalogProvider = Provider<ReferenceRepository>((ref) {
  final base = ref.watch(referenceProvider);
  final rows = ref.watch(customSubstancesProvider).value ?? const <CustomSubstance>[];
  return base.withCustom(
    active: [for (final r in rows) if (!r.deleted) substanceFromCustom(r)],
    archived: [for (final r in rows) if (r.deleted) substanceFromCustom(r)],
  );
});

// ---- people ----

final peopleProvider = StreamProvider<List<Person>>((ref) => ref.watch(databaseProvider).watchPeople());

final _currentPersonIdProvider =
    StreamProvider<String?>((ref) => ref.watch(databaseProvider).watchSetting('currentPersonId'));

/// The person whose journal is on screen. Everything personal (experiences, usage, curves,
/// tolerance, warnings) is read through this one person; there is no "everyone" view.
final currentPersonProvider = Provider<Person?>((ref) {
  final people = ref.watch(peopleProvider).value ?? const <Person>[];
  if (people.isEmpty) return null;
  final id = ref.watch(_currentPersonIdProvider).value;
  return people.firstWhere(
    (p) => p.id == id,
    orElse: () => people.firstWhere((p) => p.isDefault, orElse: () => people.first),
  );
});

// ---- per-person data ----

final experiencesProvider = StreamProvider.autoDispose.family<List<Experience>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchExperiences(personId),
);

final personIngestionsProvider = StreamProvider.autoDispose.family<List<Ingestion>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchIngestionsForPerson(personId),
);

final usageProvider = StreamProvider.autoDispose.family<Map<String, UsageStat>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchUsageForPerson(personId),
);

final compoundPrefsProvider = StreamProvider.autoDispose.family<CompoundPrefs, String>(
  (ref, personId) => ref.watch(databaseProvider).watchCompoundPrefs(personId),
);

// ---- Alcohol mode ----

/// Whether this device shows the alcohol-only app. A per-device choice, not synced.
final alcoholModeProvider = StreamProvider<bool>(
  (ref) => ref.watch(databaseProvider).watchSetting('alcoholMode').map((v) => v == 'true'),
);

final estimateSettingsProvider = StreamProvider.autoDispose.family<EstimateSettings, String>(
  (ref, personId) => ref.watch(databaseProvider).watchEstimateSettings(personId),
);

final drinkPresetsProvider = StreamProvider<List<Preset>>((ref) => ref.watch(databaseProvider).watchDrinkPresets());

/// One person's alcohol ingestions, oldest first.
final alcoholDrinksProvider = Provider.autoDispose.family<List<Ingestion>, String>((ref, personId) {
  final all = ref.watch(personIngestionsProvider(personId)).value ?? const <Ingestion>[];
  return [for (final i in all) if (i.substanceKey == 'alcohol') i];
});

// ---- calendar (the one place that looks across people) ----

final allExperiencesProvider =
    StreamProvider.autoDispose<List<Experience>>((ref) => ref.watch(databaseProvider).watchAllExperiences());

final allIngestionsProvider =
    StreamProvider.autoDispose<List<Ingestion>>((ref) => ref.watch(databaseProvider).watchAllIngestions());

// ---- one experience ----

final experienceProvider = StreamProvider.autoDispose.family<Experience?, String>(
  (ref, id) => ref.watch(databaseProvider).watchExperience(id),
);

final experienceIngestionsProvider = StreamProvider.autoDispose.family<List<Ingestion>, String>(
  (ref, id) => ref.watch(databaseProvider).watchIngestionsForExperience(id),
);

final timedNotesProvider = StreamProvider.autoDispose.family<List<TimedNote>, String>(
  (ref, id) => ref.watch(databaseProvider).watchTimedNotes(id),
);

final ratingsProvider = StreamProvider.autoDispose.family<List<Rating>, String>(
  (ref, id) => ref.watch(databaseProvider).watchRatings(id),
);

// ---- appearance ----

final themeModeProvider = StreamProvider<ThemeMode>((ref) {
  return ref.watch(databaseProvider).watchSetting('themeMode').map(
        (v) => switch (v) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
});
