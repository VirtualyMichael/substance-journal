import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'database.dart';

/// One drink from Alcohol Tracker, with its units already mapped to ours (`oz` or `shots`).
class TrackerDrink {
  const TrackerDrink({
    required this.at,
    required this.amount,
    required this.unit,
    required this.abvPercent,
    required this.label,
    this.notes = '',
    this.durationMinutes = 0,
    this.consumer = 'Me',
  });

  final DateTime at;
  final double amount;
  final String unit;
  final double abvPercent;
  final String label;
  final String notes;
  final double durationMinutes;
  final String consumer;

  /// Same rule Alcohol Tracker uses to spot a repeated import: time to the second, amount, label.
  String get key => '${at.toIso8601String().split('.').first}|$amount|$label';
}

class TrackerPreset {
  const TrackerPreset({required this.name, required this.amount, required this.unit, required this.abvPercent});
  final String name;
  final double amount;
  final String unit;
  final double abvPercent;
}

/// What was read from an Alcohol Tracker file, before anything is written.
class TrackerExport {
  const TrackerExport({
    required this.drinks,
    this.presets = const [],
    this.recipeCount = 0,
    this.problems = const [],
    required this.source,
  });

  final List<TrackerDrink> drinks;
  final List<TrackerPreset> presets;

  /// Recipes found in a database file. They are not imported (the new app has no recipe book yet).
  final int recipeCount;

  /// Rows that could not be read, each with the reason.
  final List<String> problems;

  /// `json` (an Alcohol Tracker export) or `database` (its own SQLite file).
  final String source;

  DateTime? get firstDrink => drinks.isEmpty ? null : drinks.map((d) => d.at).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get lastDrink => drinks.isEmpty ? null : drinks.map((d) => d.at).reduce((a, b) => a.isAfter(b) ? a : b);
  Set<String> get consumers => {for (final d in drinks) d.consumer};

  /// Standard drinks in the whole file, using the default 1.5 oz at 40% definition.
  double get standardDrinks {
    var total = 0.0;
    for (final d in drinks) {
      total += alcoholIngestionFor(at: d.at, volume: d.amount, volumeUnit: d.unit, abvPercent: d.abvPercent).standardDrinks(const EstimateSettings());
    }
    return total;
  }
}

class TrackerImportException implements Exception {
  const TrackerImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _mapUnit(String unit) => switch (unit) {
      'fl_oz' || 'oz' => 'oz',
      'shots' => 'shots',
      _ => throw FormatException('unknown unit "$unit"'),
    };

/// Reads one record in either format. Throws [FormatException] naming what is wrong.
TrackerDrink _drinkFrom(Map<String, dynamic> row) {
  num number(String key) {
    final v = row[key];
    if (v is num) return v;
    if (v is String) {
      final parsed = num.tryParse(v);
      if (parsed != null) return parsed;
    }
    throw FormatException('$key is missing or not a number');
  }

  final rawTime = row['occurred_at'];
  if (rawTime is! String) throw const FormatException('occurred_at is missing');
  final at = DateTime.tryParse(rawTime);
  if (at == null) throw FormatException('occurred_at "$rawTime" is not a date');
  final amount = number('amount').toDouble();
  final abv = number('abv_percent').toDouble();
  if (amount <= 0) throw const FormatException('amount must be positive');
  if (abv < 0 || abv > 100) throw const FormatException('abv_percent must be between 0 and 100');
  final duration = row['duration_minutes'] is num ? (row['duration_minutes'] as num).toDouble() : 0.0;
  final consumer = (row['consumer'] as String?)?.trim();
  return TrackerDrink(
    at: at,
    amount: amount,
    unit: _mapUnit('${row['unit']}'),
    abvPercent: abv,
    label: '${row['label'] ?? ''}',
    notes: '${row['notes'] ?? ''}',
    durationMinutes: duration < 0 ? 0 : duration,
    consumer: consumer == null || consumer.isEmpty ? 'Me' : consumer,
  );
}

TrackerExport _collect(List<Map<String, dynamic>> rows, {List<TrackerPreset> presets = const [], int recipes = 0, required String source}) {
  final drinks = <TrackerDrink>[];
  final problems = <String>[];
  for (var i = 0; i < rows.length; i++) {
    try {
      drinks.add(_drinkFrom(rows[i]));
    } on FormatException catch (e) {
      problems.add('Row ${i + 1}: ${e.message}');
    }
  }
  return TrackerExport(drinks: drinks, presets: presets, recipeCount: recipes, problems: problems, source: source);
}

/// Parses Alcohol Tracker's JSON export (a list of drinks).
TrackerExport parseTrackerJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const TrackerImportException('That file is not valid JSON.');
  }
  if (decoded is! List) {
    throw const TrackerImportException('This does not look like an Alcohol Tracker export (expected a list of drinks).');
  }
  final rows = <Map<String, dynamic>>[];
  for (final item in decoded) {
    rows.add(item is Map<String, dynamic> ? item : const {});
  }
  return _collect(rows, source: 'json');
}

/// Reads Alcohol Tracker's own SQLite database without modifying it.
TrackerExport parseTrackerDatabase(String path) {
  final sql.Database db;
  try {
    db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  } on sql.SqliteException catch (e) {
    throw TrackerImportException('Could not open the database: ${e.message}');
  }
  try {
    final tables = {for (final r in db.select("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'] as String};
    if (!tables.contains('ingestions')) {
      throw const TrackerImportException('This database has no "ingestions" table, so it is not an Alcohol Tracker database.');
    }
    final rows = [
      for (final r in db.select('SELECT * FROM ingestions ORDER BY occurred_at'))
        {for (final k in r.keys) k: r[k]},
    ];
    final presets = <TrackerPreset>[];
    if (tables.contains('drink_presets')) {
      for (final r in db.select('SELECT name, amount, unit, abv_percent FROM drink_presets ORDER BY name')) {
        try {
          presets.add(TrackerPreset(
            name: r['name'] as String,
            amount: (r['amount'] as num).toDouble(),
            unit: _mapUnit(r['unit'] as String),
            abvPercent: (r['abv_percent'] as num).toDouble(),
          ));
        } on FormatException {
          // A preset we cannot read is skipped; the drinks matter more.
        }
      }
    }
    final recipes = tables.contains('recipes') ? (db.select('SELECT COUNT(*) AS n FROM recipes').first['n'] as int) : 0;
    return _collect(rows, presets: presets, recipes: recipes, source: 'database');
  } finally {
    db.close();
  }
}

/// Reads a file picked by the user: a SQLite database (by its header) or a JSON export.
TrackerExport parseTrackerFile(String path) {
  final file = File(path);
  if (!file.existsSync()) throw TrackerImportException('Could not find $path');
  final head = file.openSync()..setPositionSync(0);
  final magic = head.readSync(16);
  head.closeSync();
  if (String.fromCharCodes(magic).startsWith('SQLite format 3')) return parseTrackerDatabase(path);
  return parseTrackerJson(file.readAsStringSync());
}

/// Where Alcohol Tracker keeps its database on this computer, or null on phones.
String? defaultTrackerDatabasePath([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  if (Platform.isWindows) {
    final base = env['LOCALAPPDATA'] ?? (env['USERPROFILE'] == null ? null : '${env['USERPROFILE']}\\AppData\\Local');
    return base == null ? null : '$base\\AlcoholTracker\\alcohol_tracker.db';
  }
  if (Platform.isLinux) {
    final base = env['XDG_DATA_HOME'] ?? (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
    return base == null ? null : '$base/AlcoholTracker/alcohol_tracker.db';
  }
  if (Platform.isMacOS) {
    return env['HOME'] == null ? null : '${env['HOME']}/Library/Application Support/AlcoholTracker/alcohol_tracker.db';
  }
  return null;
}

class TrackerImportResult {
  const TrackerImportResult({
    required this.imported,
    required this.duplicatesSkipped,
    required this.presetsAdded,
    required this.presetsSkipped,
    required this.experiencesCreated,
    required this.peopleCreated,
    required this.problems,
    required this.recipesIgnored,
  });

  final int imported;
  final int duplicatesSkipped;
  final int presetsAdded;
  final int presetsSkipped;
  final int experiencesCreated;
  final List<String> peopleCreated;
  final List<String> problems;
  final int recipesIgnored;
}

const _personColors = [0xFFE07A5F, 0xFF3D9970, 0xFFD1495B, 0xFF2EB5C4, 0xFFE0A100, 0xFF7A6FF0];

/// Writes an Alcohol Tracker export into the journal, all or nothing.
///
/// - The consumer "Me" is the default person; any other name becomes (or matches) a person.
/// - A drink joins the person's nearest experience within 12 hours, else starts a new one, the
///   same rule as quick add.
/// - A row already present (same time to the second, amount and label) is skipped, so importing
///   the same file twice adds nothing. Identical rows *inside* the file are kept: they are two
///   drinks logged in the same second, not a repeat.
/// - Presets are added by name; ones you already have are left alone.
Future<TrackerImportResult> importTrackerExport(AppDatabase db, TrackerExport export) {
  return db.transaction(() async {
    final people = await db.activePeople();
    final byName = {for (final p in people) p.name.toLowerCase(): p};
    final defaultPerson = people.firstWhere((p) => p.isDefault, orElse: () => people.isEmpty ? throw StateError('No people') : people.first);
    final created = <String>[];

    Future<Person> personFor(String consumer) async {
      if (consumer.toLowerCase() == 'me') return defaultPerson;
      final existing = byName[consumer.toLowerCase()];
      if (existing != null) return existing;
      final person = await db.addPerson(consumer, colorValue: _personColors[created.length % _personColors.length]);
      byName[consumer.toLowerCase()] = person;
      created.add(consumer);
      return person;
    }

    // What each person already has, counted, so a repeat import adds nothing.
    final existingCounts = <String, Map<String, int>>{};
    Future<Map<String, int>> countsFor(Person person) async {
      final cached = existingCounts[person.id];
      if (cached != null) return cached;
      final counts = <String, int>{};
      // Deleted drinks count too, so importing again never brings back one you removed, and a
      // drink you edited keeps the key it was imported under, so it is not added a second time.
      for (final i in await db.ingestionsForPersonIncludingDeleted(person.id)) {
        if (i.substanceKey != 'alcohol') continue;
        final key = _importKeyOf(i);
        if (key == null) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      return existingCounts[person.id] = counts;
    }

    final sorted = [...export.drinks]..sort((a, b) => a.at.compareTo(b.at));
    var imported = 0;
    var skipped = 0;
    var experiences = 0;
    for (final drink in sorted) {
      final person = await personFor(drink.consumer);
      final counts = await countsFor(person);
      final already = counts[drink.key] ?? 0;
      if (already > 0) {
        counts[drink.key] = already - 1;
        skipped++;
        continue;
      }
      final logged = await db.logDrink(
        personId: person.id,
        at: drink.at,
        volume: drink.amount,
        volumeUnit: drink.unit,
        abvPercent: drink.abvPercent,
        name: drink.label,
        durationMinutes: drink.durationMinutes,
        notes: drink.notes,
        importKey: drink.key,
      );
      imported++;
      if (logged.createdExperience) experiences++;
    }

    final havePresets = {for (final p in await db.watchDrinkPresets().first) p.name.toLowerCase()};
    var presetsAdded = 0;
    var presetsSkipped = 0;
    for (final preset in export.presets) {
      if (havePresets.contains(preset.name.toLowerCase())) {
        presetsSkipped++;
        continue;
      }
      await db.addDrinkPreset(name: preset.name, volume: preset.amount, volumeUnit: preset.unit, abvPercent: preset.abvPercent);
      havePresets.add(preset.name.toLowerCase());
      presetsAdded++;
    }

    return TrackerImportResult(
      imported: imported,
      duplicatesSkipped: skipped,
      presetsAdded: presetsAdded,
      presetsSkipped: presetsSkipped,
      experiencesCreated: experiences,
      peopleCreated: created,
      problems: export.problems,
      recipesIgnored: export.recipeCount,
    );
  });
}

/// The key a drink was imported under, or, for drinks logged before keys were recorded, the key
/// its current time, volume and name give.
String? _importKeyOf(Ingestion i) {
  if (i.detailsJson.isNotEmpty) {
    final stored = (jsonDecode(i.detailsJson) as Map<String, dynamic>)['importKey'];
    if (stored is String) return stored;
  }
  final d = _details(i);
  final volume = d.$1;
  if (volume == null) return null;
  return '${i.time.toIso8601String().split('.').first}|$volume|${d.$2}';
}

/// (volume, name) recorded on an alcohol ingestion's details, if any.
(double?, String) _details(Ingestion i) {
  if (i.detailsJson.isEmpty) return (null, '');
  final json = jsonDecode(i.detailsJson) as Map<String, dynamic>;
  return ((json['volume'] as num?)?.toDouble(), json['drink'] as String? ?? '');
}
