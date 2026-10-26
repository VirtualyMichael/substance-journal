import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:substance_journal_app/data/backup.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/sync.dart';
import 'package:substance_journal_app/providers.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AppDatabase other;
  late BackupService backup;
  late BackupService otherBackup;

  setUp(() async {
    db = AppDatabase.memory(deviceId: 'a');
    other = AppDatabase.memory(deviceId: 'b');
    backup = BackupService(db, SyncService(db, deviceName: 'A'));
    otherBackup = BackupService(other, SyncService(other, deviceName: 'B'));
  });
  tearDown(() async {
    await db.close();
    await other.close();
  });

  Future<void> seed() async {
    final me = await db.ensureDefaultPerson();
    final e = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1, 20), title: 'Night, "out"');
    await db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20), dose: 100, unit: 'µg', notes: '=HYPERLINK("x")');
    await db.addIngestion(experience: e, substanceKey: 'alcohol', route: 'oral', time: DateTime(2026, 7, 1, 21), dose: 14, unit: 'g', details: {'volume': 12, 'volumeUnit': 'oz', 'abv': 5});
    await db.addTimedNote(experienceId: e.id, time: DateTime(2026, 7, 1, 22), note: 'peak');
  }

  group('encrypted backup', () {
    test('restores into an empty journal, exactly', () async {
      await seed();
      final text = await backup.createEncryptedBackup('my passphrase');
      expect(text.contains('lsd'), isFalse);

      final result = await otherBackup.restoreEncryptedBackup(text, 'my passphrase');
      expect(result.applied, greaterThan(3));
      final me = (await other.activePeople()).single;
      final rows = await other.ingestionsForPerson(me.id);
      expect(rows.map((r) => r.substanceKey), ['lsd', 'alcohol']);
      expect(rows.first.dose, 100);
      expect(rows.last.detailsJson, contains('"volume":12'));
    });

    test('a wrong passphrase fails and changes nothing', () async {
      await seed();
      final text = await backup.createEncryptedBackup('my passphrase');
      await expectLater(otherBackup.restoreEncryptedBackup(text, 'nope nope'), throwsA(isA<SyncCryptoException>()));
      expect(await other.activePeople(), isEmpty);
    });

    test('restoring an old backup does not undo newer edits or bring back deleted entries', () async {
      await seed();
      final text = await backup.createEncryptedBackup('my passphrase');
      final me = (await db.activePeople()).single;
      final rows = await db.ingestionsForPerson(me.id);
      await db.updateIngestion(rows.first.id, notes: 'edited later');
      await db.setIngestionDeleted(rows.last.id, true);

      final result = await backup.restoreEncryptedBackup(text, 'my passphrase');
      expect(result.applied, 0);
      final after = await db.ingestionsForPerson(me.id);
      expect(after, hasLength(1));
      expect(after.single.notes, 'edited later');
    });

    test('something that is not a backup is refused', () async {
      await expectLater(backup.restoreEncryptedBackup('hello', 'passphrase'), throwsA(isA<SyncCryptoException>()));
    });
  });

  group('exports', () {
    test('CSV has a row per live dose, quotes cells and neutralises spreadsheet formulas', () async {
      await seed();
      final csv = await backup.exportCsv();
      final lines = csv.trim().split('\r\n');
      expect(lines.first, 'person,date,time,substance,route,dose,unit,dose_is_estimate,experience,notes');
      expect(lines, hasLength(3));
      expect(lines[1], contains('Me,2026-07-01,20:00,lsd,sublingual,100.0,µg'));
      expect(lines[1], contains('"Night, ""out"""'));
      expect(lines[1], contains("\"'=HYPERLINK(\"\"x\"\")\"")); // no leading =
      final me = (await db.activePeople()).single;
      await db.setIngestionDeleted((await db.ingestionsForPerson(me.id)).first.id, true);
      expect((await backup.exportCsv()).trim().split('\r\n'), hasLength(2));
    });

    test('JSON export lists every table', () async {
      await seed();
      final json = await backup.exportJson();
      expect(json, contains('"ingestions"'));
      expect(json, contains('"experiences"'));
      expect(json, contains('substance-journal-export'));
    });
  });

  group('automatic copies', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('autobackup');
      file = File('${dir.path}/journal.db');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    void makeDb(int version) {
      final raw = sql.sqlite3.open(file.path);
      raw.execute('CREATE TABLE IF NOT EXISTS t (x INTEGER); INSERT INTO t VALUES (1); PRAGMA user_version = $version;');
      raw.close();
    }

    test('makes one daily copy, and a before-upgrade copy only when the format is older', () async {
      makeDb(2);
      await BackupService.autoBackup(file, targetVersion: 3, now: DateTime(2026, 7, 1));
      await BackupService.autoBackup(file, targetVersion: 3, now: DateTime(2026, 7, 1)); // same day: nothing more
      final names = BackupService.folderFor(file).listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList()..sort();
      expect(names, ['before-upgrade-from-v2.db', 'daily-2026-07-01.db']);

      makeDb(3);
      await BackupService.autoBackup(file, targetVersion: 3, now: DateTime(2026, 7, 2));
      expect(BackupService.folderFor(file).listSync(), hasLength(3)); // + daily only
    });

    test('keeps only the newest daily copies but never deletes upgrade copies', () async {
      makeDb(2);
      for (var day = 1; day <= 6; day++) {
        await BackupService.autoBackup(file, targetVersion: 3, now: DateTime(2026, 7, day), keepDaily: 3);
      }
      final names = BackupService.folderFor(file).listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList()..sort();
      expect(names.where((n) => n.startsWith('daily-')), ['daily-2026-07-04.db', 'daily-2026-07-05.db', 'daily-2026-07-06.db']);
      expect(names.where((n) => n.startsWith('before-upgrade')), hasLength(1));
    });

    test('a missing or empty database is ignored without an error', () async {
      await BackupService.autoBackup(file, targetVersion: 3);
      file.writeAsBytesSync([]);
      await BackupService.autoBackup(file, targetVersion: 3);
      expect(BackupService.folderFor(file).existsSync(), isFalse);
    });
  });

  testWidgets('settings: create a backup with a passphrase, then restore it elsewhere', (tester) async {
    String? savedText;
    final built = await buildTestApp(tester);
    await dbRun(tester, () async {
      final me = await built.db.ensureDefaultPerson();
      final e = await built.db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1, 20));
      await built.db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20), dose: 100, unit: 'µg');
    });
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
        clockProvider.overrideWithValue(() => testNow),
        packageSaverProvider.overrideWithValue((name, text) async {
          savedText = text;
          return name;
        }),
      ],
      child: (built.widget as ProviderScope).child,
    ));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('create-backup')), 300, scrollable: find.byType(Scrollable).first);
    await tapKey(tester, 'create-backup');
    await tester.enterText(find.byKey(const ValueKey('passphrase')), 'secret one');
    await tester.enterText(find.byKey(const ValueKey('passphrase-again')), 'different');
    await tapKey(tester, 'passphrase-ok');
    expect(find.text('The two passphrases differ.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('passphrase-again')), 'secret one');
    await tapKey(tester, 'passphrase-ok');
    // Key derivation runs in another isolate, outside the test's fake clock.
    for (var i = 0; i < 40 && find.byKey(const ValueKey('output-summary')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1)); // let the sheet finish sliding in
    expect(find.byKey(const ValueKey('output-summary')), findsOneWidget);
    await tapKey(tester, 'output-save');
    await settle(tester);
    expect(savedText, startsWith('SJBAK1|'));

    final target = (await tester.runAsync(() async => AppDatabase.memory(deviceId: 'c')))!;
    addTearDown(() async => tester.runAsync(target.close));
    final restored = await tester.runAsync(
      () => BackupService(target, SyncService(target, deviceName: 'C')).restoreEncryptedBackup(savedText!, 'secret one'),
    );
    expect(restored!.applied, greaterThan(2));
    await disposeApp(tester, built);
  });
}
