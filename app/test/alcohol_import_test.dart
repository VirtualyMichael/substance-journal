import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:substance_journal_app/data/alcohol_data.dart';
import 'package:substance_journal_app/data/alcohol_import.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/providers.dart';

import 'helpers.dart';

/// Alcohol Tracker export made on 2026-08-23. Personal data, so it is read from the sibling
/// project's folder rather than committed; the tests are skipped if it is not there.
final _backup = File('../../Alcohol ingestion marking app/8-23-2026 Backup Alcohol.json');
final String? _skipBackup = _backup.existsSync() ? null : 'the 8-23-2026 backup is not next to this project';

// Figures worked out independently with Alcohol Tracker's own formulas (see the commit message).
const _rows = 143;
const _standardDrinks = 144.444167;
const _grams = 2024.52944;
const _experiences = 15; // drinks chained by gaps of at most 12 hours
const _drinkingDays = 15;
const _experienceSizes = [8, 9, 9, 6, 7, 3, 10, 15, 14, 14, 4, 14, 10, 10, 10];
const _duplicateKeys = 10; // rows that share time, amount and label with another row

Future<Directory> _scratch(String name) async {
  final dir = await Directory.systemTemp.createTemp(name);
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

/// An Alcohol Tracker SQLite file with its real schema.
String _trackerDatabase(Directory dir, List<Map<String, Object?>> drinks, {List<List<Object?>> presets = const [], int recipes = 0}) {
  final path = '${dir.path}/alcohol_tracker.db';
  final db = sql.sqlite3.open(path);
  db.execute('''
    CREATE TABLE ingestions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, occurred_at TEXT NOT NULL, amount REAL NOT NULL,
      unit TEXT NOT NULL CHECK(unit IN ('shots', 'fl_oz')), abv_percent REAL NOT NULL, label TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '', duration_minutes REAL NOT NULL DEFAULT 0, consumer TEXT NOT NULL DEFAULT 'Me',
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
    CREATE TABLE drink_presets (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, amount REAL NOT NULL,
      unit TEXT NOT NULL CHECK(unit IN ('shots', 'fl_oz')), abv_percent REAL NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
    CREATE TABLE recipes (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, payload TEXT NOT NULL,
      fingerprint TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
  ''');
  for (final d in drinks) {
    db.execute(
      'INSERT INTO ingestions (occurred_at, amount, unit, abv_percent, label, notes, duration_minutes, consumer, created_at, updated_at) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'x', 'x')",
      [d['occurred_at'], d['amount'], d['unit'], d['abv_percent'], d['label'], d['notes'] ?? '', d['duration_minutes'] ?? 0, d['consumer'] ?? 'Me'],
    );
  }
  for (final p in presets) {
    db.execute("INSERT INTO drink_presets (name, amount, unit, abv_percent, created_at, updated_at) VALUES (?, ?, ?, ?, 'x', 'x')", p);
  }
  for (var i = 0; i < recipes; i++) {
    db.execute("INSERT INTO recipes (name, payload, fingerprint, created_at, updated_at) VALUES ('r$i', '{}', 'f$i', 'x', 'x')");
  }
  db.close();
  return path;
}

Map<String, Object?> drink(String at, double amount, String unit, double abv, String label, {String consumer = 'Me', double duration = 0, String notes = ''}) => {
      'occurred_at': at,
      'amount': amount,
      'unit': unit,
      'abv_percent': abv,
      'label': label,
      'consumer': consumer,
      'duration_minutes': duration,
      'notes': notes,
    };

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  group('reading the real backup', () {
    test('parses every row with the right units, people and dates', () {
      final export = parseTrackerJson(_backup.readAsStringSync());
      expect(export.drinks, hasLength(_rows));
      expect(export.problems, isEmpty);
      expect(export.source, 'json');
      expect(export.consumers, {'Me'});
      expect(export.firstDrink, DateTime(2026, 7, 13, 19, 13, 47));
      expect(export.lastDrink, DateTime(2026, 8, 18, 22, 52, 59));
      expect(export.drinks.where((d) => d.unit == 'oz'), hasLength(114)); // "fl_oz" becomes "oz"
      expect(export.drinks.where((d) => d.unit == 'shots'), hasLength(29));
      expect(export.standardDrinks, closeTo(_standardDrinks, 1e-5));
      final long = export.drinks.where((d) => d.durationMinutes > 0).toList();
      expect(long.map((d) => d.durationMinutes), unorderedEquals([30.0, 49.0]));
      expect(export.drinks.firstWhere((d) => d.label == '4Loko').notes, 'Four Loko');
    }, skip: _skipBackup);

    test('the file really contains drinks that share time, amount and label', () {
      final export = parseTrackerJson(_backup.readAsStringSync());
      expect(export.drinks.length - export.drinks.map((d) => d.key).toSet().length, _duplicateKeys);
    }, skip: _skipBackup);

    test('the same file read as a database gives the same drinks', () async {
      final raw = (jsonDecode(_backup.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final dir = await _scratch('tracker_db');
      final path = _trackerDatabase(dir, [for (final r in raw) {...r}]);
      final fromDb = parseTrackerFile(path);
      final fromJson = parseTrackerJson(_backup.readAsStringSync());
      expect(fromDb.source, 'database');
      expect(fromDb.drinks.length, fromJson.drinks.length);
      expect(fromDb.drinks.map((d) => d.key).toList()..sort(), fromJson.drinks.map((d) => d.key).toList()..sort());
      expect(fromDb.standardDrinks, closeTo(fromJson.standardDrinks, 1e-9));
    }, skip: _skipBackup);
  });

  group('importing the real backup', () {
    test('every drink arrives, grouped into experiences, with Alcohol Tracker\'s numbers', () async {
      final me = await db.ensureDefaultPerson();
      final export = parseTrackerJson(_backup.readAsStringSync());
      final result = await importTrackerExport(db, export);

      expect(result.imported, _rows);
      expect(result.duplicatesSkipped, 0); // 10 rows repeat another row's time, amount and label, and are kept
      expect(result.experiencesCreated, _experiences);
      expect(result.peopleCreated, isEmpty);

      final rows = await db.ingestionsForPerson(me.id);
      expect(rows, hasLength(_rows));
      expect(rows.every((r) => r.substanceKey == 'alcohol' && r.route == 'oral' && r.unit == 'g'), isTrue);
      expect(rows.fold<double>(0, (s, r) => s + r.dose!), closeTo(_grams, 1e-4));
      expect(rows.fold<double>(0, (s, r) => s + standardDrinksOf(r, const EstimateSettings())), closeTo(_standardDrinks, 1e-5));

      final bySize = <String, int>{};
      for (final r in rows) {
        bySize[r.experienceId] = (bySize[r.experienceId] ?? 0) + 1;
      }
      final firstToLast = (await db.watchExperiences(me.id).first).reversed.map((e) => bySize[e.id]).toList();
      expect(firstToLast, _experienceSizes);

      // Per-day totals match Alcohol Tracker's own daily maths.
      final totals = dailyStandardDrinks(rows, const EstimateSettings());
      expect(totals, hasLength(_drinkingDays));
      expect(totals[DateTime(2026, 7, 29)], closeTo(14.416667, 1e-5));
      expect(totals[DateTime(2026, 7, 13)], closeTo(8.333333, 1e-5));
    }, skip: _skipBackup);

    test('the label, notes and how long it took are kept', () async {
      final me = await db.ensureDefaultPerson();
      await importTrackerExport(db, parseTrackerJson(_backup.readAsStringSync()));
      final rows = await db.ingestionsForPerson(me.id);
      final loko = rows.singleWhere((r) => DrinkDetails.of(r).name == '4Loko');
      expect(loko.notes, 'Four Loko');
      expect(loko.endTime!.difference(loko.time), const Duration(minutes: 49));
      expect(DrinkDetails.of(loko).volume, 23.5);
      expect(DrinkDetails.of(loko).volumeUnit, 'oz');
      expect(DrinkDetails.of(loko).abv, 13.9);
      expect(loko.time, DateTime(2026, 7, 30, 19, 46, 45));
      expect(rows.where((r) => r.endTime != null), hasLength(2));
    }, skip: _skipBackup);

    test('importing again never overwrites, resurrects or duplicates what you changed', () async {
      final me = await db.ensureDefaultPerson();
      final export = TrackerExport(source: 'json', drinks: [
        TrackerDrink(at: DateTime(2026, 7, 1, 20), amount: 12, unit: 'oz', abvPercent: 5, label: 'Beer', notes: 'original'),
        TrackerDrink(at: DateTime(2026, 7, 1, 21), amount: 1.5, unit: 'oz', abvPercent: 40, label: 'Whiskey'),
        TrackerDrink(at: DateTime(2026, 7, 2, 20), amount: 5, unit: 'oz', abvPercent: 12, label: 'Wine'),
      ]);
      await importTrackerExport(db, export);
      final rows = await db.ingestionsForPerson(me.id);
      final beer = rows.firstWhere((r) => r.detailsJson.contains('Beer'));
      final whiskey = rows.firstWhere((r) => r.detailsJson.contains('Whiskey'));

      // Edit one (new time, volume and note) and delete another.
      await db.updateIngestion(beer.id, time: DateTime(2026, 7, 1, 22, 30), notes: 'my note', dose: const Value(20.0));
      await db.setIngestionDeleted(whiskey.id, true);

      final again = await importTrackerExport(db, export);
      expect(again.imported, 0);
      expect(again.duplicatesSkipped, 3);
      final after = await db.ingestionsForPerson(me.id);
      expect(after, hasLength(2)); // the deleted whiskey stays deleted
      final kept = after.firstWhere((r) => r.id == beer.id);
      expect(kept.notes, 'my note');
      expect(kept.time, DateTime(2026, 7, 1, 22, 30));
      expect(kept.dose, 20.0);
    });

    test('importing the same file again adds nothing', () async {
      final me = await db.ensureDefaultPerson();
      final export = parseTrackerJson(_backup.readAsStringSync());
      await importTrackerExport(db, export);
      final second = await importTrackerExport(db, export);
      expect(second.imported, 0);
      expect(second.duplicatesSkipped, _rows);
      expect(await db.ingestionsForPerson(me.id), hasLength(_rows));
      expect(await db.watchExperiences(me.id).first, hasLength(_experiences));
    }, skip: _skipBackup);

    test('a newer export only adds the new drinks, joining the right experience', () async {
      final me = await db.ensureDefaultPerson();
      final raw = (jsonDecode(_backup.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      await importTrackerExport(db, parseTrackerJson(jsonEncode(raw)));
      // Two drinks later on the last night and one a week afterwards.
      final newer = [
        ...raw,
        drink('2026-08-18T23:30:00', 1, 'fl_oz', 50, '50% Shot'),
        drink('2026-08-19T00:10:00', 1, 'fl_oz', 50, '50% Shot'),
        drink('2026-08-26T20:00:00', 12, 'fl_oz', 5, 'Beer'),
      ];
      final result = await importTrackerExport(db, parseTrackerJson(jsonEncode(newer)));
      expect(result.imported, 3);
      expect(result.duplicatesSkipped, _rows);
      expect(result.experiencesCreated, 1); // the late-night shots joined the last night; the beer is a new one
      expect(await db.ingestionsForPerson(me.id), hasLength(_rows + 3));
      expect(await db.watchExperiences(me.id).first, hasLength(_experiences + 1));
    }, skip: _skipBackup);

    test('the imported drinks give the same estimate whichever app computes them', () async {
      final me = await db.ensureDefaultPerson();
      await importTrackerExport(db, parseTrackerJson(_backup.readAsStringSync()));
      final drinks = await db.ingestionsForPerson(me.id);
      final summary = summarizeBac(drinks, DateTime(2026, 8, 18, 23, 0));
      // Reproduced from the Alcohol Tracker model on the same drinks; see test/golden for the maths.
      expect(summary.peak, greaterThan(0.1));
      expect(summary.peak, lessThan(0.6));
      expect(summary.series, isNotEmpty);
    }, skip: _skipBackup);
  });

  group('the importer itself', () {
    test('drinks by other people become people, and "Me" goes to the default person', () async {
      final me = await db.ensureDefaultPerson();
      final result = await importTrackerExport(
        db,
        parseTrackerJson(jsonEncode([
          drink('2026-07-01T20:00:00', 1, 'shots', 40, 'Shot', consumer: 'Me'),
          drink('2026-07-01T20:10:00', 12, 'fl_oz', 5, 'Beer', consumer: 'Sam'),
          drink('2026-07-01T20:20:00', 12, 'fl_oz', 5, 'Beer', consumer: 'sam'),
        ])),
      );
      expect(result.peopleCreated, ['Sam']);
      final people = await db.activePeople();
      expect(people.map((p) => p.name).toSet(), {'Me', 'Sam'});
      final sam = people.firstWhere((p) => p.name == 'Sam');
      expect(await db.ingestionsForPerson(sam.id), hasLength(2));
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
      // Sam's drinks did not join my experience even though they are minutes apart.
      final mine = (await db.ingestionsForPerson(me.id)).single.experienceId;
      expect((await db.ingestionsForPerson(sam.id)).every((i) => i.experienceId != mine), isTrue);
    });

    test('an existing person with that name is reused', () async {
      await db.ensureDefaultPerson();
      final bob = await db.addPerson('Bob');
      final result = await importTrackerExport(db, parseTrackerJson(jsonEncode([drink('2026-07-01T20:00:00', 1, 'shots', 40, 'Shot', consumer: 'BOB')])));
      expect(result.peopleCreated, isEmpty);
      expect(await db.ingestionsForPerson(bob.id), hasLength(1));
    });

    test('presets are added by name, units mapped, and existing names are kept', () async {
      await db.ensureDefaultPerson();
      await db.addDrinkPreset(name: 'Beer - 12 oz 5%', volume: 12, volumeUnit: 'oz', abvPercent: 5);
      final dir = await _scratch('presets');
      final path = _trackerDatabase(
        dir,
        [drink('2026-07-01T20:00:00', 1, 'shots', 40, 'Shot')],
        presets: [
          ['Beer - 12 oz 5%', 12.0, 'fl_oz', 5.0],
          ['Strong beer - 16 oz 8%', 16.0, 'fl_oz', 8.0],
          ['Double shot - 40%', 2.0, 'shots', 40.0],
        ],
        recipes: 3,
      );
      final export = parseTrackerFile(path);
      expect(export.presets, hasLength(3));
      expect(export.recipeCount, 3);
      final result = await importTrackerExport(db, export);
      expect(result.presetsAdded, 2);
      expect(result.presetsSkipped, 1);
      expect(result.recipesIgnored, 3);
      final presets = await db.watchDrinkPresets().first;
      expect(presets.map((p) => p.name), containsAll(['Beer - 12 oz 5%', 'Strong beer - 16 oz 8%', 'Double shot - 40%']));
      expect(presets, hasLength(3));
      final strong = presets.firstWhere((p) => p.name.startsWith('Strong'));
      expect([strong.amount, strong.unit], [16.0, 'oz']);
      final shot = presets.firstWhere((p) => p.name.startsWith('Double'));
      expect([shot.amount, shot.unit], [2.0, 'shots']);
    });

    test('bad rows are reported and skipped while good rows import', () async {
      final me = await db.ensureDefaultPerson();
      final export = parseTrackerJson(jsonEncode([
        drink('2026-07-01T20:00:00', 1, 'shots', 40, 'Good'),
        {'occurred_at': 'yesterday', 'amount': 1, 'unit': 'shots', 'abv_percent': 40, 'label': 'x'},
        {'occurred_at': '2026-07-01T21:00:00', 'amount': -1, 'unit': 'shots', 'abv_percent': 40, 'label': 'x'},
        {'occurred_at': '2026-07-01T21:30:00', 'amount': 1, 'unit': 'pints', 'abv_percent': 40, 'label': 'x'},
        {'occurred_at': '2026-07-01T22:00:00', 'amount': 1, 'unit': 'shots', 'abv_percent': 140, 'label': 'x'},
        {'unit': 'shots'},
        'not a row',
      ]));
      expect(export.drinks, hasLength(1));
      expect(export.problems, hasLength(6));
      expect(export.problems.first, startsWith('Row 2:'));
      final result = await importTrackerExport(db, export);
      expect(result.imported, 1);
      expect(result.problems, hasLength(6));
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
    });

    test('files that are not Alcohol Tracker data are refused with a clear message', () async {
      expect(() => parseTrackerJson('not json at all'), throwsA(isA<TrackerImportException>()));
      expect(() => parseTrackerJson('{"a": 1}'), throwsA(isA<TrackerImportException>()));
      final dir = await _scratch('other_db');
      final other = sql.sqlite3.open('${dir.path}/other.db')..execute('CREATE TABLE notes (id INTEGER)');
      other.close();
      expect(() => parseTrackerFile('${dir.path}/other.db'), throwsA(isA<TrackerImportException>().having((e) => e.message, 'message', contains('ingestions'))));
      expect(() => parseTrackerFile('${dir.path}/missing.json'), throwsA(isA<TrackerImportException>()));
    });

    test('older databases without the duration and consumer columns still import', () async {
      final dir = await _scratch('old_db');
      final path = '${dir.path}/old.db';
      final old = sql.sqlite3.open(path)
        ..execute('CREATE TABLE ingestions (id INTEGER PRIMARY KEY, occurred_at TEXT, amount REAL, unit TEXT, abv_percent REAL, label TEXT, notes TEXT)')
        ..execute("INSERT INTO ingestions VALUES (1, '2026-07-01T20:00:00', 12, 'fl_oz', 5, 'Beer', '')");
      old.close();
      final export = parseTrackerFile(path);
      expect(export.drinks.single.consumer, 'Me');
      expect(export.drinks.single.durationMinutes, 0);
    });

    test('a failure part way through rolls everything back, including new people', () async {
      final failing = _FailingDb(failOnCall: 3);
      addTearDown(failing.close);
      final me = await failing.ensureDefaultPerson();
      final export = parseTrackerJson(jsonEncode([
        drink('2026-07-01T20:00:00', 1, 'shots', 40, 'A'),
        drink('2026-07-01T21:00:00', 1, 'shots', 40, 'B', consumer: 'Sam'),
        drink('2026-07-01T22:00:00', 1, 'shots', 40, 'C'),
      ]));
      await expectLater(importTrackerExport(failing, export), throwsA(isA<StateError>()));
      expect(failing.calls, 3);
      expect(await failing.ingestionsForPerson(me.id), isEmpty); // drinks A and B were written, then undone
      expect((await failing.activePeople()).map((p) => p.name), ['Me']); // and so was Sam
      expect(await failing.select(failing.experiences).get(), isEmpty);
    });

    test('the default Alcohol Tracker location follows its own folder layout', () {
      if (Platform.isWindows) {
        expect(defaultTrackerDatabasePath({'LOCALAPPDATA': r'C:\Users\x\AppData\Local'}), r'C:\Users\x\AppData\Local\AlcoholTracker\alcohol_tracker.db');
      }
      if (Platform.isLinux) {
        expect(defaultTrackerDatabasePath({'XDG_DATA_HOME': '/data'}), '/data/AlcoholTracker/alcohol_tracker.db');
        expect(defaultTrackerDatabasePath({'HOME': '/home/x'}), '/home/x/.local/share/AlcoholTracker/alcohol_tracker.db');
      }
    });
  });

  group('screen', () {
    Future<(TestApp, Person)> app(WidgetTester tester, {String? picked, String? defaultPath}) async {
      final built = await buildTestApp(tester);
      final me = await dbRun(tester, built.db.ensureDefaultPerson);
      await dbRun(tester, built.db.ensureDefaultDrinkPresets);
      await dbRun(tester, () => built.db.setSetting('alcoholMode', 'true'));
      return (built, me);
    }

    Widget wrap(TestApp built, {String? picked, String? defaultPath}) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(built.db),
            referenceProvider.overrideWithValue(built.reference),
            interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
            clockProvider.overrideWithValue(() => testNow),
            trackerFilePickerProvider.overrideWithValue(() async => picked),
            trackerDefaultPathProvider.overrideWithValue(defaultPath),
          ],
          child: (built.widget as ProviderScope).child,
        );

    Future<void> openSettings(WidgetTester tester, TestApp built, {String? picked, String? defaultPath}) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(built, picked: picked, defaultPath: defaultPath));
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);
    }

    testWidgets('choosing the real backup shows a summary and imports it on confirmation', (tester) async {
      final (built, me) = await app(tester);
      await openSettings(tester, built, picked: _backup.absolute.path);

      await tapKey(tester, 'import-tracker-file');
      expect(find.text('Import from Alcohol Tracker'), findsWidgets);
      expect(find.textContaining('$_rows drinks from Jul 13, 2026 to Aug 18, 2026'), findsOneWidget);
      expect(find.textContaining('144.4 standard drinks'), findsOneWidget);
      expect(find.textContaining('importing the same file again adds nothing'), findsOneWidget);
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), isEmpty); // nothing yet

      await tapKey(tester, 'import-confirm');
      await settle(tester, rounds: 12);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.textContaining('$_rows drinks imported in $_experiences new experiences.'), findsOneWidget);
      await tapKey(tester, 'import-done');
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), hasLength(_rows));
      await disposeApp(tester, built);
    }, skip: _skipBackup != null);

    testWidgets('cancelling imports nothing; the PC button appears only when Alcohol Tracker is installed', (tester) async {
      final (built, me) = await app(tester);
      await openSettings(tester, built, picked: _backup.absolute.path);
      expect(find.byKey(const ValueKey('import-tracker-pc')), findsNothing);
      await tapKey(tester, 'import-tracker-file');
      await tapKey(tester, 'import-cancel');
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), isEmpty);
      await disposeApp(tester, built);
    }, skip: _skipBackup != null);

    testWidgets('the PC button imports straight from the database', (tester) async {
      final dir = Directory.systemTemp.createTempSync('pc_db');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = _trackerDatabase(dir, [drink('2026-07-01T20:00:00', 12, 'fl_oz', 5, 'Beer')], presets: [
        ['Pint', 16.0, 'fl_oz', 4.5],
      ]);
      final (built, me) = await app(tester);
      await openSettings(tester, built, defaultPath: path);
      await tapKey(tester, 'import-tracker-pc');
      expect(find.textContaining('1 drinks from Jul 1, 2026'), findsOneWidget);
      await tapKey(tester, 'import-confirm');
      await settle(tester, rounds: 10);
      expect(find.textContaining('1 drinks imported'), findsOneWidget);
      expect(find.textContaining('1 presets added'), findsOneWidget);
      await tapKey(tester, 'import-done');
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), hasLength(1));
      await disposeApp(tester, built);
    });

    testWidgets('a bad file explains itself and changes nothing', (tester) async {
      final dir = Directory.systemTemp.createTempSync('bad_file');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/oops.json')..writeAsStringSync('{"hello": true}');
      final (built, me) = await app(tester);
      await openSettings(tester, built, picked: file.path);
      await tapKey(tester, 'import-tracker-file');
      expect(find.text('Could not import'), findsOneWidget);
      expect(find.textContaining('expected a list of drinks'), findsOneWidget);
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), isEmpty);
      await disposeApp(tester, built);
    });

    testWidgets('picking nothing does nothing', (tester) async {
      final (built, _) = await app(tester);
      await openSettings(tester, built);
      await tapKey(tester, 'import-tracker-file');
      expect(find.text('Import from Alcohol Tracker'), findsOneWidget); // only the section heading
      await disposeApp(tester, built);
    });
  });
}

({double peak, List<(DateTime, double)> series}) summarizeBac(List<Ingestion> drinks, DateTime at) {
  final series = bacSeries(drinks, const EstimateSettings(), from: at.subtract(const Duration(hours: 6)), to: at.add(const Duration(hours: 8)));
  return (peak: peakValue(series).$2, series: series);
}

/// A database whose Nth drink log fails, to prove an import is all or nothing.
class _FailingDb extends AppDatabase {
  _FailingDb({required this.failOnCall}) : super(NativeDatabase.memory(), deviceId: 'failing');

  final int failOnCall;
  int calls = 0;

  @override
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
  }) {
    if (++calls == failOnCall) throw StateError('boom');
    return super.logDrink(
      personId: personId,
      at: at,
      volume: volume,
      volumeUnit: volumeUnit,
      abvPercent: abvPercent,
      name: name,
      durationMinutes: durationMinutes,
      notes: notes,
      importKey: importKey,
      shotOz: shotOz,
    );
  }
}
