import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/dedupe.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
  int clock() => nowMs;
  void tick() => nowMs += 60000;

  late AppDatabase a, b;
  late SyncService sa, sb;

  setUp(() async {
    nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
    a = AppDatabase.memory(deviceId: 'a', nowMillis: clock);
    b = AppDatabase.memory(deviceId: 'b', nowMillis: clock);
    sa = SyncService(a, deviceName: 'A', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    sb = SyncService(b, deviceName: 'B', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    await sb.acceptPairing((await sa.offerPairing()).encode());
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  final t1 = DateTime(2026, 6, 1, 20);
  final t2 = DateTime(2026, 6, 1, 21);
  final t3 = DateTime(2026, 6, 2, 20);

  /// The same imported history, created independently (random ids) on a device.
  Future<(Experience, Experience)> importHistory(AppDatabase db) async {
    final me = await db.ensureDefaultPerson();
    final e1 = await db.addExperience(personId: me.id, sortDate: t1);
    await db.addIngestion(experience: e1, substanceKey: 'alcohol', route: 'oral', time: t1, dose: 14, unit: 'g');
    await db.addIngestion(experience: e1, substanceKey: 'alcohol', route: 'oral', time: t1, dose: 14, unit: 'g'); // a real twin
    await db.addIngestion(experience: e1, substanceKey: 'lsd', route: 'sublingual', time: t2, dose: 100, unit: 'µg');
    final e2 = await db.addExperience(personId: me.id, sortDate: t3);
    await db.addIngestion(experience: e2, substanceKey: 'cannabis', route: 'smoked', time: t3, dose: 5, unit: 'mg');
    return (e1, e2);
  }

  Future<int> liveDoses(AppDatabase db) async => (await db.ingestionsForPerson((await db.activePeople()).single.id)).length;
  Future<int> liveExperiences(AppDatabase db) async => (await db.watchExperiences((await db.activePeople()).single.id).first).length;

  Future<void> syncBoth() async {
    tick();
    await sb.receivePackage(await sa.createPackage((await sa.peers()).single.deviceId, everything: true));
    tick();
    await sa.receivePackage(await sb.createPackage('a', everything: true));
    tick();
    await sb.receivePackage(await sa.createPackage('b', everything: true));
  }

  group('syncing a history both devices imported', () {
    test('is not doubled, keeps real twins, and stays stable when synced again', () async {
      await importHistory(a);
      await importHistory(b);
      await syncBoth();
      await syncBoth();
      for (final db in [a, b]) {
        expect(await liveDoses(db), 4); // alcohol x2 (twins), lsd, cannabis
        expect(await liveExperiences(db), 2);
      }
    });

    test('keeps what only one device had: extra doses, notes, ratings and titles', () async {
      final (ea, _) = await importHistory(a);
      final (eb, _) = await importHistory(b);
      await a.updateExperience(ea.id, title: 'Party');
      await a.addTimedNote(experienceId: ea.id, time: t2, note: 'only on A');
      await b.addRating(experienceId: eb.id, shulgin: 'plus2');
      await b.addIngestion(experience: eb, substanceKey: 'mdma', route: 'oral', time: t2, dose: 80, unit: 'mg'); // extra dose on B
      await syncBoth();
      for (final db in [a, b]) {
        final me = (await db.activePeople()).single;
        expect(await liveDoses(db), 5);
        final experiences = await db.watchExperiences(me.id).first;
        expect(experiences, hasLength(2));
        final party = experiences.firstWhere((e) => e.title == 'Party');
        expect((await db.watchTimedNotes(party.id).first).single.note, 'only on A');
        expect((await db.watchRatings(party.id).first).single.shulgin, 'plus2');
        expect((await db.ingestionsForExperience(party.id)).any((i) => i.substanceKey == 'mdma'), isTrue);
      }
    });

    test('a later edit still reaches the one matched entry (no copy appears)', () async {
      await importHistory(a);
      await importHistory(b);
      await syncBoth();
      final me = (await a.activePeople()).single;
      final lsd = (await a.ingestionsForPerson(me.id)).firstWhere((i) => i.substanceKey == 'lsd');
      tick();
      await a.updateIngestion(lsd.id, dose: const Value(75.0), notes: 'edited on A');
      await syncBoth();
      final onB = await b.ingestionsForPerson((await b.activePeople()).single.id);
      expect(onB.length, 4);
      final edited = onB.firstWhere((i) => i.substanceKey == 'lsd');
      expect(edited.dose, 75);
      expect(edited.notes, 'edited on A');
    });

    test('a dose deleted on one device is not brought back by the other copy', () async {
      await importHistory(a);
      await importHistory(b);
      await syncBoth();
      final me = (await a.activePeople()).single;
      final cannabis = (await a.ingestionsForPerson(me.id)).firstWhere((i) => i.substanceKey == 'cannabis');
      tick();
      await a.setIngestionDeleted(cannabis.id, true);
      await syncBoth();
      expect((await b.ingestionsForPerson((await b.activePeople()).single.id)).any((i) => i.substanceKey == 'cannabis'), isFalse);
    });

    test('the same dose logged to the second on one device and the minute on another still matches', () async {
      final me = await a.ensureDefaultPerson();
      final ea = await a.addExperience(personId: me.id, sortDate: t1);
      await a.addIngestion(experience: ea, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 6, 1, 20, 0, 41), dose: 100, unit: 'µg');
      final meB = await b.ensureDefaultPerson();
      final eb = await b.addExperience(personId: meB.id, sortDate: t1);
      await b.addIngestion(experience: eb, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 6, 1, 20, 0), dose: 100, unit: 'µg');
      await syncBoth();
      expect(await liveDoses(a), 1);
      expect(await liveDoses(b), 1);
    });

    test('different doses are never merged', () async {
      final me = await a.ensureDefaultPerson();
      final e = await a.addExperience(personId: me.id, sortDate: t1);
      await a.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: t1, dose: 100, unit: 'µg');
      final meB = await b.ensureDefaultPerson();
      final eb = await b.addExperience(personId: meB.id, sortDate: t1);
      await b.addIngestion(experience: eb, substanceKey: 'lsd', route: 'sublingual', time: t1, dose: 120, unit: 'µg'); // different amount
      await b.addIngestion(experience: eb, substanceKey: 'lsd', route: 'oral', time: t1, dose: 100, unit: 'µg'); // different route
      await syncBoth();
      expect(await liveDoses(a), 3);
    });
  });

  group('cleaning up copies that already exist', () {
    /// One device holding two copies of a history (as after an earlier sync).
    Future<void> doubled(AppDatabase db) async {
      await importHistory(db);
      final me = (await db.activePeople()).single;
      final e1 = await db.addExperience(personId: me.id, sortDate: t1);
      await db.addIngestion(experience: e1, substanceKey: 'alcohol', route: 'oral', time: t1, dose: 14, unit: 'g');
      await db.addIngestion(experience: e1, substanceKey: 'alcohol', route: 'oral', time: t1, dose: 14, unit: 'g');
      await db.addIngestion(experience: e1, substanceKey: 'lsd', route: 'sublingual', time: t2, dose: 100, unit: 'µg', notes: 'good one');
      await db.updateExperience(e1.id, title: 'Copy with a title');
      await db.addTimedNote(experienceId: e1.id, time: t2, note: 'peak');
      final e2 = await db.addExperience(personId: me.id, sortDate: t3);
      await db.addIngestion(experience: e2, substanceKey: 'cannabis', route: 'smoked', time: t3, dose: 5, unit: 'mg');
    }

    test('finds the copies, merges them, keeps twins and extras, and can be undone', () async {
      await doubled(a);
      final cleaner = DuplicateCleaner(a);
      final scan = await cleaner.scan();
      expect(scan.doseCopies, 4);
      expect(scan.experienceGroups, 2);

      final result = await cleaner.apply(scan);
      expect(result.dosesMerged, 4);
      expect(result.experiencesMerged, 2);
      final me = (await a.activePeople()).single;
      expect(await liveDoses(a), 4); // twins kept
      final experiences = await a.watchExperiences(me.id).first;
      expect(experiences, hasLength(2));
      final first = experiences.firstWhere((e) => e.title == 'Copy with a title'); // the title survived
      final doses = await a.ingestionsForExperience(first.id);
      expect(doses.firstWhere((i) => i.substanceKey == 'lsd').notes, 'good one'); // the note survived
      expect((await a.watchTimedNotes(first.id).first).single.note, 'peak');
      expect((await DuplicateCleaner(a).scan()).isEmpty, isTrue);

      expect(await cleaner.hasUndo(), isTrue);
      expect(await cleaner.undo(), greaterThan(0));
      expect(await liveDoses(a), 8);
      expect(await liveExperiences(a), 4);
      expect(await cleaner.hasUndo(), isFalse);
    });

    test('a history with real twins and no copies is left alone', () async {
      await importHistory(a);
      expect((await DuplicateCleaner(a).scan()).isEmpty, isTrue);
    });

    test('two devices cleaning the same mess end up agreeing', () async {
      await doubled(a);
      await sb.receivePackage(await sa.createPackage((await sa.peers()).single.deviceId, everything: true));
      await DuplicateCleaner(a).apply(await DuplicateCleaner(a).scan());
      await DuplicateCleaner(b).apply(await DuplicateCleaner(b).scan());
      await syncBoth();
      expect(await liveDoses(a), 4);
      expect(await liveDoses(b), 4);
      expect(await liveExperiences(a), 2);
      expect(await liveExperiences(b), 2);
    });
  });

  group('combining a day', () {
    test('experiences within 12 hours join into one, whatever the substance; other days and people stay apart', () async {
      final me = await a.ensureDefaultPerson();
      final alex = await a.addPerson('Alex');
      Future<void> night(dynamic person, String substance, DateTime at) async {
        final e = await a.addExperience(personId: person.id, sortDate: at);
        await a.addIngestion(experience: e, substanceKey: substance, route: 'oral', time: at, dose: 5, unit: 'mg');
      }

      await night(me, 'alcohol', DateTime(2026, 10, 21, 19, 39));
      await night(me, 'cannabis', DateTime(2026, 10, 21, 20, 22)); // same evening
      await night(me, 'mdma', DateTime(2026, 10, 22, 2, 0)); // chained: within 12 h of the last
      await night(me, 'alcohol', DateTime(2026, 10, 25, 19, 0)); // a different day
      await night(alex, 'cannabis', DateTime(2026, 10, 21, 20, 0)); // someone else

      final cleaner = DuplicateCleaner(a);
      expect((await cleaner.scan()).isEmpty, isTrue); // not duplicates, so the plain scan leaves them
      final scan = await cleaner.scan(combineNearby: true);
      expect(scan.experienceGroups, 1);
      expect(scan.experienceMerges.single.length, 3);

      await cleaner.apply(scan);
      final mine = await a.watchExperiences(me.id).first;
      expect(mine, hasLength(2));
      final evening = (await Future.wait([for (final e in mine) a.ingestionsForExperience(e.id)])).firstWhere((l) => l.length == 3);
      expect(evening.map((i) => i.substanceKey).toSet(), {'alcohol', 'cannabis', 'mdma'});
      expect(await a.watchExperiences(alex.id).first, hasLength(1));
      expect(await cleaner.undo(), greaterThan(0));
      expect(await a.watchExperiences(me.id).first, hasLength(4));
    });
  });
}
