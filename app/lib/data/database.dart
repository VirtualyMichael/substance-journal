import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sj_core/sj_core.dart';

import 'tables.dart';

part 'database.g.dart';

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
  int get schemaVersion => 1;

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
  }) async {
    final id = newId();
    await into(experiences).insert(ExperiencesCompanion.insert(
      id: id,
      hlc: nextHlc(),
      personId: personId,
      sortDate: sortDate,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_nowMillis()),
      title: Value(title),
      notes: Value(notes),
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
      notes: Value(notes ?? ''),
      detailsJson: Value(jsonEncode(details ?? const {})),
    ));
    return (select(ingestions)..where((t) => t.id.equals(id))).getSingle();
  }

  Stream<List<Ingestion>> watchIngestionsForPerson(String personId) => (select(ingestions)
        ..where((t) => t.personId.equals(personId) & t.deleted.equals(false))
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
  }) async {
    await (update(ingestions)..where((t) => t.id.equals(id))).write(IngestionsCompanion(
      time: time == null ? const Value.absent() : Value(time),
      endTime: endTime,
      dose: dose,
      doseIsEstimate: doseIsEstimate,
      notes: notes == null ? const Value.absent() : Value(notes),
      hlc: Value(nextHlc()),
    ));
  }

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
