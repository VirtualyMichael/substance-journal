import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  var nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
  int clock() => nowMs;
  void tick([int seconds = 60]) => nowMs += seconds * 1000;

  late AppDatabase pcDb;
  late AppDatabase phoneDb;
  late SyncService pc;
  late SyncService phone;

  setUp(() async {
    nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
    pcDb = AppDatabase.memory(deviceId: 'pc', nowMillis: clock);
    phoneDb = AppDatabase.memory(deviceId: 'phone', nowMillis: clock);
    pc = SyncService(pcDb, deviceName: 'PC', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    phone = SyncService(phoneDb, deviceName: 'Phone', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
  });
  tearDown(() async {
    await pcDb.close();
    await phoneDb.close();
  });

  Future<void> pair() async {
    final code = await pc.offerPairing();
    await phone.acceptPairing(code.encode());
  }

  /// PC sends its changes to the phone (as text, the way a QR or a message would).
  Future<ApplyResult> pcToPhone({bool everything = false}) async {
    // Until the phone has answered once, the PC only knows the pairing it offered.
    final peers = await pc.peers();
    final id = peers.any((p) => p.deviceId == 'phone') ? 'phone' : peers.single.deviceId;
    return phone.receivePackage(await pc.createPackage(id, everything: everything));
  }

  /// The phone's first package is what lets the PC recognise it.
  Future<ApplyResult> phoneToPc({bool everything = false}) async =>
      pc.receivePackage(await phone.createPackage('pc', everything: everything));

  Future<Person> addMe(AppDatabase db) => db.ensureDefaultPerson();

  Future<Ingestion> drink(AppDatabase db, Person person, String substance, double dose, DateTime at) async {
    final e = await db.addExperience(personId: person.id, sortDate: at);
    return db.addIngestion(experience: e, substanceKey: substance, route: 'oral', time: at, dose: dose, unit: 'mg');
  }

  test('pairing: the scanner learns the PC, and the PC learns the phone from its first package', () async {
    final code = await pc.offerPairing();
    expect((await pc.peers()).single.pending, isTrue);
    expect(await phone.acceptPairing(code.encode()), 'PC');
    expect((await phone.peers()).single.name, 'PC');

    await addMe(phoneDb);
    final result = await phoneToPc();
    expect(result.peerName, 'Phone');
    final peers = await pc.peers();
    expect(peers.single.deviceId, 'phone');
    expect(peers.single.pending, isFalse);
  });

  test('offering a pairing twice reuses the same key until it is claimed', () async {
    final a = await pc.offerPairing();
    final b = await pc.offerPairing();
    expect(b.key, a.key);
    expect((await pc.peers()), hasLength(1));
  });

  test('a first sync carries everything: people, experiences, ingestions, notes and ratings', () async {
    await pair();
    final me = await addMe(pcDb);
    final i = await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    await pcDb.addTimedNote(experienceId: i.experienceId, time: DateTime(2026, 7, 1, 11), note: 'hello');
    await pcDb.addRating(experienceId: i.experienceId, shulgin: 'plus2');
    await pcDb.setCompoundPrefs(me.id, const CompoundPrefs(favorites: {'lsd'}, hidden: {}));
    tick();

    final result = await pcToPhone();
    expect(result.applied, greaterThan(5));
    final people = await phoneDb.activePeople();
    expect(people.single.name, 'Me');
    final rows = await phoneDb.ingestionsForPerson(people.single.id);
    expect(rows.single.substanceKey, 'lsd');
    expect(rows.single.dose, 100);
    expect((await phoneDb.watchTimedNotes(i.experienceId).first).single.note, 'hello');
    expect((await phoneDb.watchRatings(i.experienceId).first).single.shulgin, 'plus2');
    expect((await phoneDb.getCompoundPrefs(people.single.id)).favorites, {'lsd'}); // shared settings travel
  });

  test('syncing again changes nothing, and the next package carries only new changes', () async {
    await pair();
    final me = await addMe(pcDb);
    await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    tick();
    await pcToPhone();
    await phoneToPc(); // the phone says how much it has

    final again = await pcToPhone(); // nothing new, but the whole thing re-applies cleanly
    expect(again.applied, 0);

    tick();
    await drink(pcDb, me, 'mdma', 80, DateTime(2026, 7, 1, 12));
    expect(await pc.pendingChangeCount('phone'), lessThan(6)); // just the new experience and ingestion
    final result = await pcToPhone();
    expect(result.applied, 2);
    expect(await phoneDb.ingestionsForPerson((await phoneDb.activePeople()).single.id), hasLength(2));
  });

  test('edits and deletes travel both ways, and the later edit wins a conflict', () async {
    await pair();
    final me = await addMe(pcDb);
    final i = await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    final j = await drink(pcDb, me, 'mdma', 80, DateTime(2026, 7, 1, 11));
    tick();
    await pcToPhone();
    await phoneToPc();

    // Both devices edit the same dose; the phone's edit is later.
    tick();
    await pcDb.updateIngestion(i.id, dose: const Value(120.0));
    tick();
    await phoneDb.updateIngestion(i.id, dose: const Value(90.0), notes: 'phone');
    // And the phone deletes the other one.
    tick();
    await phoneDb.setIngestionDeleted(j.id, true);

    await phoneToPc();
    await pcToPhone();
    final pcRows = await pcDb.ingestionsForPerson(me.id);
    final phoneRows = await phoneDb.ingestionsForPerson(me.id);
    for (final rows in [pcRows, phoneRows]) {
      expect(rows, hasLength(1));
      expect(rows.single.dose, 90);
      expect(rows.single.notes, 'phone');
    }
    // The deleted dose stays deleted on both (a tombstone, not a missing row).
    expect((await pcDb.ingestionsForPersonIncludingDeleted(me.id)).length, 2);
  });

  test('a stale package cannot overwrite a newer local edit', () async {
    await pair();
    final me = await addMe(pcDb);
    final i = await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    tick();
    final old = await pc.createPackage((await pc.peers()).single.deviceId, everything: true);
    await phone.receivePackage(old);
    tick();
    await phoneDb.updateIngestion(i.id, dose: const Value(55.0));
    final replay = await phone.receivePackage(old);
    expect(replay.applied, 0);
    expect((await phoneDb.ingestionsForPerson(me.id)).single.dose, 55);
  });

  test('people stay separate: syncing never merges two people or their doses', () async {
    await pair();
    final me = await addMe(pcDb);
    final alex = await pcDb.addPerson('Alex');
    await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    await drink(pcDb, alex, 'ketamine', 30, DateTime(2026, 7, 1, 10));
    tick();
    await pcToPhone();
    final people = {for (final p in await phoneDb.activePeople()) p.name: p};
    expect(people.keys, {'Me', 'Alex'});
    expect((await phoneDb.ingestionsForPerson(people['Me']!.id)).single.substanceKey, 'lsd');
    expect((await phoneDb.ingestionsForPerson(people['Alex']!.id)).single.substanceKey, 'ketamine');
  });

  test('each device invents its own Me, and that and same-named people become one person, with their data and settings', () async {
    await pair();
    final pcMe = await addMe(pcDb);
    final phoneMe = await addMe(phoneDb);
    expect(pcMe.id, isNot(phoneMe.id)); // each device invented its own
    final pcColby = await pcDb.addPerson('Colby');
    final phoneColby = await phoneDb.addPerson('colby');
    await drink(pcDb, pcMe, 'lsd', 100, DateTime(2026, 7, 1, 10));
    await drink(pcDb, pcColby, 'ketamine', 30, DateTime(2026, 7, 1, 11));
    await drink(phoneDb, phoneMe, 'mdma', 80, DateTime(2026, 7, 1, 12));
    await drink(phoneDb, phoneColby, 'cannabis', 5, DateTime(2026, 7, 1, 13));
    await pcDb.setCompoundPrefs(pcMe.id, const CompoundPrefs(favorites: {'lsd'}, hidden: {}));
    tick();

    await pcToPhone();
    await phoneToPc();
    await pcToPhone();

    for (final db in [pcDb, phoneDb]) {
      final people = await db.activePeople();
      expect(people.map((p) => p.name.toLowerCase()).toList()..sort(), ['colby', 'me']); // not four
      final me = people.firstWhere((p) => p.name == 'Me');
      final colby = people.firstWhere((p) => p.name.toLowerCase() == 'colby');
      expect((await db.ingestionsForPerson(me.id)).map((i) => i.substanceKey).toSet(), {'lsd', 'mdma'});
      expect((await db.ingestionsForPerson(colby.id)).map((i) => i.substanceKey).toSet(), {'ketamine', 'cannabis'});
    }
    final phoneMeNow = (await phoneDb.activePeople()).firstWhere((p) => p.name == 'Me');
    expect((await phoneDb.getCompoundPrefs(phoneMeNow.id)).favorites, {'lsd'}); // settings follow the person
  });

  test('wrong, tampered or unpaired packages are refused and change nothing', () async {
    final me = await addMe(pcDb);
    await drink(pcDb, me, 'lsd', 100, DateTime(2026, 7, 1, 10));
    await pair();
    final good = await pc.createPackage((await pc.peers()).single.deviceId, everything: true);

    // A third device with its own key.
    final otherDb = AppDatabase.memory(deviceId: 'other', nowMillis: clock);
    addTearDown(otherDb.close);
    final other = SyncService(otherDb, deviceName: 'Other');
    final otherCode = await other.offerPairing();
    final strangerDb = AppDatabase.memory(deviceId: 'stranger', nowMillis: clock);
    addTearDown(strangerDb.close);
    final stranger = SyncService(strangerDb, deviceName: 'Stranger');
    await stranger.acceptPairing(otherCode.encode());
    await strangerDb.ensureDefaultPerson();
    final fromStranger = await stranger.createPackage('other', everything: true);

    // The phone has never paired with "other" or "stranger".
    await expectLater(phone.receivePackage(fromStranger), throwsA(isA<SyncException>()));
    final i = good.length ~/ 2;
    final tampered = good.substring(0, i) + (good[i] == 'A' ? 'B' : 'A') + good.substring(i + 1);
    await expectLater(phone.receivePackage(tampered), throwsA(isA<SyncException>()));
    await expectLater(phone.receivePackage('hello'), throwsA(isA<SyncException>()));
    await expectLater(pc.receivePackage(good), throwsA(isA<SyncException>())); // made by this device
    expect(await phoneDb.activePeople(), isEmpty);
  });

  test('forgetting a device stops its packages being accepted', () async {
    await pair();
    await addMe(pcDb);
    final package = await pc.createPackage((await pc.peers()).single.deviceId, everything: true);
    await phone.forgetPeer('pc');
    await expectLater(phone.receivePackage(package), throwsA(isA<SyncException>()));
  });

  test('pairing works on a database upgraded from the old peers table (public_key NOT NULL, no default)', () async {
    final legacy = AppDatabase(
      NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE peers (
            device_id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
            last_known_address TEXT, last_synced_hlc TEXT NOT NULL DEFAULT '', paired_at INTEGER NOT NULL
          )''');
        raw.execute("CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, hlc TEXT NOT NULL, shared INTEGER NOT NULL DEFAULT 0)");
        raw.execute('PRAGMA user_version = 2');
      }),
      deviceId: 'old-pc',
      nowMillis: clock,
    );
    addTearDown(legacy.close);
    final service = SyncService(legacy, deviceName: 'Old PC');
    final code = await service.offerPairing(); // used to fail with a NOT NULL constraint
    expect(code.encode(), startsWith('SJPAIR1:'));
    expect((await service.peers()).single.pending, isTrue);

    final other = SyncService(phoneDb, deviceName: 'Phone');
    expect(await other.acceptPairing(code.encode()), 'Old PC');
  });

  test('this device cannot pair with its own code', () async {
    final code = await pc.offerPairing();
    await expectLater(pc.acceptPairing(code.encode()), throwsA(isA<SyncException>()));
    await expectLater(pc.acceptPairing('junk'), throwsA(isA<SyncException>()));
  });

  test('a package for an unpaired peer cannot be created', () async {
    await expectLater(pc.createPackage('nobody'), throwsA(isA<SyncException>()));
  });
}
