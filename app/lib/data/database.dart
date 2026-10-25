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
    double? dose,
    String? unit,
    bool doseIsEstimate = false,
    double? doseStdDev,
    String? notes,
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
      dose: Value(dose),
      unit: Value(unit),
      doseIsEstimate: Value(doseIsEstimate),
      doseStdDev: Value(doseStdDev),
      notes: Value(notes ?? ''),
    ));
    return (select(ingestions)..where((t) => t.id.equals(id))).getSingle();
  }

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

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value, {bool shared = false}) =>
      into(settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value, hlc: nextHlc(), shared: Value(shared)));
}

Future<File> defaultDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'substance_journal.sqlite'));
}
