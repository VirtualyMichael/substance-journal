import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sj_core/sj_core.dart';

import 'tables.dart';

part 'database.g.dart';

/// Bumped when a table changes; backups copy the file before an upgrade past an older number.
const int currentSchemaVersion = 3;

@DriftDatabase(tables: [
  People,
  Experiences,
  Ingestions,
  TimedNotes,
  Ratings,
  CustomUnits,
  CustomSubstances,
  Products,
  Presets,
  Settings,
  Peers,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {required this.deviceId, int Function()? nowMillis})
      : _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch),
        _clock = Hlc.zero(deviceId);

  /// In-memory database for tests.
  AppDatabase.memory({String deviceId = 'test-device', int Function()? nowMillis})
      : this(NativeDatabase.memory(), deviceId: deviceId, nowMillis: nowMillis);

  /// This device's id; goes into every clock stamp.
  final String deviceId;
  final int Function() _nowMillis;
  Hlc _clock;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(customSubstances, customSubstances.onsetMinutes);
            await m.addColumn(customSubstances, customSubstances.durationHours);
          }
          if (from < 3) {
            await m.addColumn(peers, peers.sharedKey);
          }
        },
      );

  /// Stamps a local edit: advances the clock and returns its text form.
  String nextHlc() {
    _clock = _clock.send(_nowMillis());
    return _clock.toString();
  }

  /// Folds a remote clock into ours so later local edits sort after everything we have seen.
  void observeHlc(String remote) {
    _clock = _clock.receive(Hlc.parse(remote), _nowMillis());
  }

  // ---- people ----

  Future<Person> addPerson(String name, {int? colorValue, bool isDefault = false}) async {
    final row = PeopleCompanion.insert(
      id: newId(),
      hlc: nextHlc(),
      name: name,
      colorValue: colorValue == null ? const Value.absent() : Value(colorValue),
      isDefault: Value(isDefault),
    );
    await into(people).insert(row);
    return (select(people)..where((t) => t.id.equals(row.id.value))).getSingle();
  }

  Future<List<Person>> activePeople() =>
      (select(people)..where((t) => t.deleted.equals(false))..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  // ---- experiences & ingestions (always scoped to one person) ----

  Future<Experience> addExperience({
    required String personId,
    required DateTime sortDate,
    String title = '',
    String notes = '',
    bool isFavorite = false,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) async {
    final id = newId();
    await into(experiences).insert(ExperiencesCompanion.insert(
      id: id,
      hlc: nextHlc(),
      personId: personId,
      sortDate: sortDate,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(_nowMillis()),
      title: Value(title),
      notes: Value(notes),
      isFavorite: Value(isFavorite),
      locationName: Value(locationName),
      latitude: Value(latitude),
      longitude: Value(longitude),
    ));
    return (select(experiences)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<Ingestion> addIngestion({
    required Experience experience,
    required String substanceKey,
    required String route,
    required DateTime time,
    DateTime? endTime,
    double? dose,
    String? unit,
    bool doseIsEstimate = false,
    double? doseStdDev,
    String? stomachFullness,
    double? absorbedMg,
    String? method,
    String? notes,
    Map<String, Object?>? details,
    String? customUnitId,
  }) async {
    final id = newId();
    await into(ingestions).insert(IngestionsCompanion.insert(
      id: id,
      hlc: nextHlc(),
      experienceId: experience.id,
      personId: experience.personId,
      substanceKey: substanceKey,
      route: route,
      time: time,
      endTime: Value(endTime),
      dose: Value(dose),
      unit: Value(unit),
      doseIsEstimate: Value(doseIsEstimate),
      doseStdDev: Value(doseStdDev),
      stomachFullness: Value(stomachFullness),
      absorbedMg: Value(absorbedMg),
      method: Value(method),
      customUnitId: Value(customUnitId),
      notes: Value(notes ?? ''),
      detailsJson: Value(jsonEncode(details ?? const {})),
    ));
    return (select(ingestions)..where((t) => t.id.equals(id))).getSingle();
  }

  Stream<List<Ingestion>> watchIngestionsForPerson(String personId) => (select(ingestions)
        ..where((t) => t.personId.equals(personId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  /// Every person's experiences. Only the calendar uses this, to show who is on which day;
  /// anything that draws curves, tolerance or warnings must stay per person.
  Stream<List<Experience>> watchAllExperiences() => (select(experiences)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.sortDate)]))
      .watch();

  /// Every person's ingestions, for the calendar only (see [watchAllExperiences]).
  Stream<List<Ingestion>> watchAllIngestions() => (select(ingestions)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  Stream<List<Ingestion>> watchIngestionsForExperience(String experienceId) => (select(ingestions)
        ..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  Future<void> setIngestionDeleted(String id, bool value) async {
    await (update(ingestions)..where((t) => t.id.equals(id)))
        .write(IngestionsCompanion(deleted: Value(value), hlc: Value(nextHlc())));
  }

  Future<void> updateIngestion(
    String id, {
    DateTime? time,
    Value<DateTime?> endTime = const Value.absent(),
    Value<double?> dose = const Value.absent(),
    Value<bool> doseIsEstimate = const Value.absent(),
    String? notes,
    String? substanceKey,
    String? route,
    String? unit,
    Value<String?> customUnitId = const Value.absent(),
    Value<double?> absorbedMg = const Value.absent(),
    Value<String?> method = const Value.absent(),
    String? detailsJson,
  }) async {
    await (update(ingestions)..where((t) => t.id.equals(id))).write(IngestionsCompanion(
      time: time == null ? const Value.absent() : Value(time),
      endTime: endTime,
      dose: dose,
      doseIsEstimate: doseIsEstimate,
      notes: notes == null ? const Value.absent() : Value(notes),
      substanceKey: substanceKey == null ? const Value.absent() : Value(substanceKey),
      route: route == null ? const Value.absent() : Value(route),
      unit: unit == null ? const Value.absent() : Value(unit),
      customUnitId: customUnitId,
      absorbedMg: absorbedMg,
      method: method,
      detailsJson: detailsJson == null ? const Value.absent() : Value(detailsJson),
      hlc: Value(nextHlc()),
    ));
  }

  // ---- custom compounds ----

  Future<CustomSubstance> addCustomSubstance({
    required String name,
    required String units,
    String description = '',
    int onsetMinutes = 30,
    double durationHours = 4.0,
  }) async {
    final id = newId();
    await into(customSubstances).insert(CustomSubstancesCompanion.insert(
      id: id,
      hlc: nextHlc(),
      name: name,
      units: units,
      description: Value(description),
      onsetMinutes: Value(onsetMinutes),
      durationHours: Value(durationHours),
    ));
    return (select(customSubstances)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateCustomSubstance(
    String id, {
    String? name,
    String? units,
    String? description,
    int? onsetMinutes,
    double? durationHours,
  }) async {
    await (update(customSubstances)..where((t) => t.id.equals(id))).write(CustomSubstancesCompanion(
      name: name == null ? const Value.absent() : Value(name),
      units: units == null ? const Value.absent() : Value(units),
      description: description == null ? const Value.absent() : Value(description),
      onsetMinutes: onsetMinutes == null ? const Value.absent() : Value(onsetMinutes),
      durationHours: durationHours == null ? const Value.absent() : Value(durationHours),
      hlc: Value(nextHlc()),
    ));
  }

  /// Soft delete. Past ingestions keep resolving to the compound's name.
  Future<void> setCustomSubstanceDeleted(String id, bool value) async {
    await (update(customSubstances)..where((t) => t.id.equals(id)))
        .write(CustomSubstancesCompanion(deleted: Value(value), hlc: Value(nextHlc())));
  }

  /// Every custom compound including deleted ones (so old ingestions can still show a name).
  Stream<List<CustomSubstance>> watchCustomSubstances() =>
      (select(customSubstances)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  // ---- custom units ("1 pill = 120 mg") ----

  Future<CustomUnit> addCustomUnit({
    required String substanceKey,
    required String route,
    required String name,
    required String unitSingular,
    String? unitPlural,
    required double doseOfOneUnit,
    double? doseStdDev,
    required String originalUnit,
    bool isEstimate = false,
    String note = '',
  }) async {
    final id = newId();
    await into(customUnits).insert(CustomUnitsCompanion.insert(
      id: id,
      hlc: nextHlc(),
      substanceKey: substanceKey,
      route: route,
      name: name,
      unitSingular: unitSingular,
      unitPlural: Value(unitPlural),
      doseOfOneUnit: Value(doseOfOneUnit),
      doseStdDev: Value(doseStdDev),
      originalUnit: originalUnit,
      isEstimate: Value(isEstimate),
      note: Value(note),
    ));
    return (select(customUnits)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateCustomUnit(
    String id, {
    String? name,
    String? unitSingular,
    Value<String?> unitPlural = const Value.absent(),
    double? doseOfOneUnit,
    Value<double?> doseStdDev = const Value.absent(),
    bool? isEstimate,
    bool? isArchived,
    String? note,
  }) async {
    await (update(customUnits)..where((t) => t.id.equals(id))).write(CustomUnitsCompanion(
      name: name == null ? const Value.absent() : Value(name),
      unitSingular: unitSingular == null ? const Value.absent() : Value(unitSingular),
      unitPlural: unitPlural,
      doseOfOneUnit: doseOfOneUnit == null ? const Value.absent() : Value(doseOfOneUnit),
      doseStdDev: doseStdDev,
      isEstimate: isEstimate == null ? const Value.absent() : Value(isEstimate),
      isArchived: isArchived == null ? const Value.absent() : Value(isArchived),
      note: note == null ? const Value.absent() : Value(note),
      hlc: Value(nextHlc()),
    ));
  }

  Future<void> setCustomUnitDeleted(String id, bool value) async {
    await (update(customUnits)..where((t) => t.id.equals(id)))
        .write(CustomUnitsCompanion(deleted: Value(value), hlc: Value(nextHlc())));
  }

  Stream<List<CustomUnit>> watchCustomUnits() => (select(customUnits)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  // ---- people (extra) ----

  Stream<List<Person>> watchPeople() =>
      (select(people)..where((t) => t.deleted.equals(false))..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Creates the first person on a fresh install ("Me").
  Future<Person> ensureDefaultPerson() async {
    final existing = await activePeople();
    if (existing.isNotEmpty) return existing.firstWhere((p) => p.isDefault, orElse: () => existing.first);
    return addPerson('Me', isDefault: true);
  }

  Future<void> renamePerson(String id, String name) async {
    await (update(people)..where((t) => t.id.equals(id)))
        .write(PeopleCompanion(name: Value(name), hlc: Value(nextHlc())));
  }

  /// Removes a person and tombstones everything they own, so their data cannot leak into
  /// anyone else's view. The default person cannot be deleted.
  Future<void> deletePerson(String id) async {
    final person = await (select(people)..where((t) => t.id.equals(id))).getSingle();
    if (person.isDefault) throw StateError('The default person cannot be deleted');
    await transaction(() async {
      for (final e in await (select(experiences)..where((t) => t.personId.equals(id))).get()) {
        await deleteExperience(e.id);
      }
      await (update(people)..where((t) => t.id.equals(id)))
          .write(PeopleCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
    });
  }

  Future<String?> currentPersonId() => getSetting('currentPersonId');

  Future<void> setCurrentPerson(String id) => setSetting('currentPersonId', id);

  // ---- experiences (extra) ----

  Stream<List<Experience>> watchExperiences(String personId) => (select(experiences)
        ..where((t) => t.personId.equals(personId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.sortDate)]))
      .watch();

  Stream<Experience?> watchExperience(String id) =>
      (select(experiences)..where((t) => t.id.equals(id) & t.deleted.equals(false))).watchSingleOrNull();

  Future<void> updateExperience(
    String id, {
    String? title,
    String? notes,
    bool? isFavorite,
    DateTime? sortDate,
  }) async {
    await (update(experiences)..where((t) => t.id.equals(id))).write(ExperiencesCompanion(
      title: title == null ? const Value.absent() : Value(title),
      notes: notes == null ? const Value.absent() : Value(notes),
      isFavorite: isFavorite == null ? const Value.absent() : Value(isFavorite),
      sortDate: sortDate == null ? const Value.absent() : Value(sortDate),
      hlc: Value(nextHlc()),
    ));
  }

  /// Soft-deletes an experience and everything inside it.
  Future<void> deleteExperience(String id) async {
    await transaction(() async {
      await (update(ingestions)..where((t) => t.experienceId.equals(id)))
          .write(IngestionsCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
      await (update(timedNotes)..where((t) => t.experienceId.equals(id)))
          .write(TimedNotesCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
      await (update(ratings)..where((t) => t.experienceId.equals(id)))
          .write(RatingsCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
      await (update(experiences)..where((t) => t.id.equals(id)))
          .write(ExperiencesCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
    });
  }

  Future<void> setExperienceDeleted(String id, bool value) async {
    await transaction(() async {
      final stamp = value ? const Value(true) : const Value(false);
      await (update(ingestions)..where((t) => t.experienceId.equals(id)))
          .write(IngestionsCompanion(deleted: stamp, hlc: Value(nextHlc())));
      await (update(timedNotes)..where((t) => t.experienceId.equals(id)))
          .write(TimedNotesCompanion(deleted: stamp, hlc: Value(nextHlc())));
      await (update(ratings)..where((t) => t.experienceId.equals(id)))
          .write(RatingsCompanion(deleted: stamp, hlc: Value(nextHlc())));
      await (update(experiences)..where((t) => t.id.equals(id)))
          .write(ExperiencesCompanion(deleted: stamp, hlc: Value(nextHlc())));
    });
  }

  // ---- timed notes and ratings ----

  Future<TimedNote> addTimedNote({
    required String experienceId,
    required DateTime time,
    required String note,
    int? colorValue,
    bool showOnTimeline = true,
  }) async {
    final id = newId();
    await into(timedNotes).insert(TimedNotesCompanion.insert(
      id: id,
      hlc: nextHlc(),
      experienceId: experienceId,
      time: time,
      note: note,
      colorValue: colorValue == null ? const Value.absent() : Value(colorValue),
      showOnTimeline: Value(showOnTimeline),
    ));
    return (select(timedNotes)..where((t) => t.id.equals(id))).getSingle();
  }

  Stream<List<TimedNote>> watchTimedNotes(String experienceId) => (select(timedNotes)
        ..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  Future<void> deleteTimedNote(String id) async {
    await (update(timedNotes)..where((t) => t.id.equals(id)))
        .write(TimedNotesCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
  }

  Future<Rating> addRating({
    required String experienceId,
    DateTime? time,
    String? shulgin,
    Map<String, int>? scores,
  }) async {
    final id = newId();
    await into(ratings).insert(RatingsCompanion.insert(
      id: id,
      hlc: nextHlc(),
      experienceId: experienceId,
      time: Value(time),
      shulgin: Value(shulgin),
      scoresJson: Value(jsonEncode(scores ?? const {})),
    ));
    return (select(ratings)..where((t) => t.id.equals(id))).getSingle();
  }

  Stream<List<Rating>> watchRatings(String experienceId) => (select(ratings)
        ..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .watch();

  Future<void> deleteRating(String id) async {
    await (update(ratings)..where((t) => t.id.equals(id)))
        .write(RatingsCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
  }

  // ---- Alcohol mode: drinks, presets and body settings ----

  /// Experience a drink at [at] belongs to: that of the person's ingestion closest in time to it,
  /// if one is within the [window] (either side, so back-dating works), else null.
  Future<Experience?> recentExperienceFor(String personId, DateTime at, {Duration window = const Duration(hours: 12)}) async {
    final nearby = await (select(ingestions)
          ..where((t) =>
              t.personId.equals(personId) &
              t.deleted.equals(false) &
              t.time.isBiggerOrEqualValue(at.subtract(window)) &
              t.time.isSmallerOrEqualValue(at.add(window))))
        .get();
    if (nearby.isEmpty) return null;
    nearby.sort((a, b) => a.time.difference(at).abs().compareTo(b.time.difference(at).abs()));
    return (select(experiences)..where((t) => t.id.equals(nearby.first.experienceId) & t.deleted.equals(false))).getSingleOrNull();
  }

  /// Logs one drink for [personId], joining their recent experience or starting a new one.
  ///
  /// The dose is stored in grams of ethanol; the volume, unit and ABV go in `details` so the
  /// estimate can be recomputed exactly (and a drink can be edited as a drink).
  Future<LoggedDrink> logDrink({
    required String personId,
    required DateTime at,
    required double volume,
    required String volumeUnit,
    required double abvPercent,
    String name = '',
    double durationMinutes = 0,
    String notes = '',
    double shotOz = shotVolumeOz,
    String? importKey,
  }) async {
    var experience = await recentExperienceFor(personId, at);
    final created = experience == null;
    experience ??= await addExperience(personId: personId, sortDate: at);
    if (at.isBefore(experience.sortDate)) {
      await updateExperience(experience.id, sortDate: at);
    }
    final ingestion = await addIngestion(
      experience: experience,
      substanceKey: 'alcohol',
      route: 'oral',
      time: at,
      endTime: durationMinutes > 0 ? at.add(Duration(minutes: durationMinutes.round())) : null,
      dose: drinkGrams(volume, volumeUnit, abvPercent, shotOz: shotOz),
      unit: 'g',
      notes: notes,
      details: {'drink': name, 'volume': volume, 'volumeUnit': volumeUnit, 'abv': abvPercent, 'importKey': ?importKey},
    );
    return LoggedDrink(ingestion: ingestion, experienceId: experience.id, createdExperience: created);
  }

  /// Takes back a drink just logged; removes the experience too if the drink created it.
  Future<void> undoLoggedDrink(LoggedDrink logged) async {
    await setIngestionDeleted(logged.ingestion.id, true);
    if (logged.createdExperience) await deleteExperience(logged.experienceId);
  }

  Stream<List<Preset>> watchDrinkPresets() => (select(presets)
        ..where((t) => t.substanceKey.equals('alcohol') & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<Preset> addDrinkPreset({
    required String name,
    required double volume,
    required String volumeUnit,
    required double abvPercent,
  }) async {
    final id = newId();
    await into(presets).insert(PresetsCompanion.insert(
      id: id,
      hlc: nextHlc(),
      substanceKey: 'alcohol',
      route: 'oral',
      name: name,
      amount: volume,
      unit: volumeUnit,
      detailsJson: Value(jsonEncode({'abv': abvPercent})),
    ));
    return (select(presets)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateDrinkPreset(
    String id, {
    String? name,
    double? volume,
    String? volumeUnit,
    double? abvPercent,
  }) async {
    await (update(presets)..where((t) => t.id.equals(id))).write(PresetsCompanion(
      name: name == null ? const Value.absent() : Value(name),
      amount: volume == null ? const Value.absent() : Value(volume),
      unit: volumeUnit == null ? const Value.absent() : Value(volumeUnit),
      detailsJson: abvPercent == null ? const Value.absent() : Value(jsonEncode({'abv': abvPercent})),
      hlc: Value(nextHlc()),
    ));
  }

  Future<void> setDrinkPresetDeleted(String id, bool value) async {
    await (update(presets)..where((t) => t.id.equals(id)))
        .write(PresetsCompanion(deleted: Value(value), hlc: Value(nextHlc())));
  }

  /// Adds Alcohol Tracker's six starter drinks the first time, and only if there are none.
  Future<void> ensureDefaultDrinkPresets() async {
    final any = await (select(presets)..where((t) => t.substanceKey.equals('alcohol'))..limit(1)).getSingleOrNull();
    if (any != null) return;
    for (final d in defaultDrinkPresets) {
      await addDrinkPreset(name: d.name, volume: d.volume, volumeUnit: d.unit, abvPercent: d.abv);
    }
  }

  Stream<EstimateSettings> watchEstimateSettings(String personId) =>
      watchSetting('estimate:$personId').map(_decodeEstimateSettings);

  Future<EstimateSettings> getEstimateSettings(String personId) async =>
      _decodeEstimateSettings(await getSetting('estimate:$personId'));

  /// Body and model settings are per person: BAC depends on whose body it is.
  Future<void> setEstimateSettings(String personId, EstimateSettings value) =>
      setSetting('estimate:$personId', jsonEncode(value.toJson()), shared: true);

  EstimateSettings _decodeEstimateSettings(String? text) =>
      text == null || text.isEmpty ? const EstimateSettings() : estimateSettingsFromJson(jsonDecode(text) as Map<String, dynamic>);

  // ---- compound picker preferences (per person) ----

  Stream<CompoundPrefs> watchCompoundPrefs(String personId) =>
      (select(settings)..where((t) => t.key.equals('compoundPrefs:$personId')))
          .watchSingleOrNull()
          .map((row) => CompoundPrefs.decode(row?.value));

  Future<CompoundPrefs> getCompoundPrefs(String personId) async =>
      CompoundPrefs.decode(await getSetting('compoundPrefs:$personId'));

  Future<void> setCompoundPrefs(String personId, CompoundPrefs prefs) =>
      setSetting('compoundPrefs:$personId', prefs.encode(), shared: true);

  Future<void> toggleFavorite(String personId, String substanceKey) async {
    final p = await getCompoundPrefs(personId);
    final favorites = {...p.favorites};
    favorites.contains(substanceKey) ? favorites.remove(substanceKey) : favorites.add(substanceKey);
    await setCompoundPrefs(personId, CompoundPrefs(favorites: favorites, hidden: p.hidden));
  }

  Future<void> setHidden(String personId, String substanceKey, bool hidden) async {
    final p = await getCompoundPrefs(personId);
    final next = {...p.hidden};
    hidden ? next.add(substanceKey) : next.remove(substanceKey);
    await setCompoundPrefs(personId, CompoundPrefs(favorites: p.favorites, hidden: next));
  }

  Stream<Map<String, UsageStat>> watchUsageForPerson(String personId) =>
      watchIngestionsForPerson(personId).map((rows) {
        final usage = <String, UsageStat>{};
        for (final row in rows) {
          final existing = usage[row.substanceKey];
          usage[row.substanceKey] = UsageStat(
            count: (existing?.count ?? 0) + 1,
            lastUsed: existing == null || row.time.isAfter(existing.lastUsed) ? row.time : existing.lastUsed,
          );
        }
        return usage;
      });

  /// Live ingestions for ONE person. There is intentionally no query that returns
  /// several people's ingestions together; curves and tolerance must never mix people.
  Future<List<Ingestion>> ingestionsForPerson(String personId) => (select(ingestions)
        ..where((t) => t.personId.equals(personId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .get();

  /// Every ingestion of one person including deleted ones. Importers use it so a drink you
  /// deleted is not brought back by importing the same file again.
  Future<List<Ingestion>> ingestionsForPersonIncludingDeleted(String personId) =>
      (select(ingestions)..where((t) => t.personId.equals(personId))).get();

  Future<List<Ingestion>> ingestionsForExperience(String experienceId) => (select(ingestions)
        ..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.time)]))
      .get();

  /// Soft delete: keeps the row as a tombstone so the delete reaches other devices.
  Future<void> deleteIngestion(String id) async {
    await (update(ingestions)..where((t) => t.id.equals(id)))
        .write(IngestionsCompanion(deleted: const Value(true), hlc: Value(nextHlc())));
  }

  /// How often and how recently a person used each substance, for the compound picker.
  Future<Map<String, UsageStat>> usageForPerson(String personId) async {
    final rows = await ingestionsForPerson(personId);
    final usage = <String, UsageStat>{};
    for (final row in rows) {
      final existing = usage[row.substanceKey];
      usage[row.substanceKey] = UsageStat(
        count: (existing?.count ?? 0) + 1,
        lastUsed: existing == null || row.time.isAfter(existing.lastUsed) ? row.time : existing.lastUsed,
      );
    }
    return usage;
  }

  // ---- settings ----

  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((t) => t.key.equals(key))).watchSingleOrNull().map((row) => row?.value);

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value, {bool shared = false}) =>
      into(settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value, hlc: nextHlc(), shared: Value(shared)));
}

/// A drink just logged, with what is needed to undo it.
class LoggedDrink {
  const LoggedDrink({required this.ingestion, required this.experienceId, required this.createdExperience});
  final Ingestion ingestion;
  final String experienceId;
  final bool createdExperience;
}

class DrinkPresetDefault {
  const DrinkPresetDefault(this.name, this.volume, this.unit, this.abv);
  final String name;
  final double volume;
  final String unit;
  final double abv;
}

/// Alcohol Tracker's starter presets.
const List<DrinkPresetDefault> defaultDrinkPresets = [
  DrinkPresetDefault('Shot - 40%', 1, 'shots', 40),
  DrinkPresetDefault('Double shot - 40%', 2, 'shots', 40),
  DrinkPresetDefault('Beer - 12 oz 5%', 12, 'oz', 5),
  DrinkPresetDefault('Strong beer - 16 oz 8%', 16, 'oz', 8),
  DrinkPresetDefault('Wine - 5 oz 12%', 5, 'oz', 12),
  DrinkPresetDefault('Hard seltzer - 12 oz 5%', 12, 'oz', 5),
];

/// A person's favourite and hidden compounds in the picker.
class CompoundPrefs {
  const CompoundPrefs({this.favorites = const {}, this.hidden = const {}});
  final Set<String> favorites;
  final Set<String> hidden;

  static CompoundPrefs decode(String? text) {
    if (text == null || text.isEmpty) return const CompoundPrefs();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return CompoundPrefs(
      favorites: {...(json['favorites'] as List? ?? const []).cast<String>()},
      hidden: {...(json['hidden'] as List? ?? const []).cast<String>()},
    );
  }

  String encode() => jsonEncode({'favorites': favorites.toList()..sort(), 'hidden': hidden.toList()..sort()});
}

Future<File> defaultDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'substance_journal.sqlite'));
}
