import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/lan_sync.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final loopback = InternetAddress.loopbackIPv4;
  var nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
  int clock() => nowMs;

  late AppDatabase pcDb, phoneDb;
  late SyncService pc, phone;
  LanSyncServer? server;

  setUp(() async {
    nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
    pcDb = AppDatabase.memory(deviceId: 'pc', nowMillis: clock);
    phoneDb = AppDatabase.memory(deviceId: 'phone', nowMillis: clock);
    pc = SyncService(pcDb, deviceName: 'PC', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    phone = SyncService(phoneDb, deviceName: 'Phone', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    server = LanSyncServer(pc, 'pc', port: 0, discoveryPort: 0, bindAddress: loopback);
    expect(await server!.start(), isTrue);
    await phone.acceptPairing((await pc.offerPairing()).encode());
  });
  tearDown(() async {
    await server?.stop();
    await pcDb.close();
    await phoneDb.close();
  });

  Future<void> seed(AppDatabase db, String substance, DateTime at) async {
    final me = await db.ensureDefaultPerson();
    final e = await db.addExperience(personId: me.id, sortDate: at);
    await db.addIngestion(experience: e, substanceKey: substance, route: 'oral', time: at, dose: 10, unit: 'mg');
  }

  Future<int> doses(AppDatabase db) async => (await db.ingestionsForPerson((await db.activePeople()).single.id)).length;

  test('one tap swaps both directions, and the first sync completes the pairing', () async {
    await seed(pcDb, 'mdma', DateTime(2026, 6, 1, 20));
    await seed(phoneDb, 'lsd', DateTime(2026, 6, 2, 20));
    expect((await pc.peers()).single.pending, isTrue);

    final client = LanSyncClient(phone, 'phone');
    final result = await client.syncWith('pc', address: '127.0.0.1', port: server!.httpPort);
    expect(result.peerName, 'PC');
    expect(result.received, greaterThan(0));

    expect(await doses(phoneDb), 2); // got the PC's dose
    expect(await doses(pcDb), 2); // and the PC got the phone's in the same round trip
    final peers = await pc.peers();
    expect(peers.single.deviceId, 'phone');
    expect(peers.single.pending, isFalse);
  });

  test('later syncs are quick deltas and keep the address for next time', () async {
    await seed(pcDb, 'mdma', DateTime(2026, 6, 1, 20));
    final client = LanSyncClient(phone, 'phone');
    await client.syncWith('pc', address: '127.0.0.1', port: server!.httpPort);
    expect(await phoneDb.getSetting('peerAddr:pc'), '127.0.0.1:${server!.httpPort}');

    nowMs += 60000;
    await seed(phoneDb, 'lsd', DateTime(2026, 6, 3, 20));
    final again = await client.syncWith('pc'); // no address given: uses the remembered one
    expect(again.received, 0); // the PC had nothing new for the phone
    expect(await doses(pcDb), 2);
  });

  test('the other device is found by broadcast when no address is known', () async {
    await seed(pcDb, 'mdma', DateTime(2026, 6, 1, 20));
    final client = LanSyncClient(phone, 'phone', discoveryTargets: [loopback], discoveryPort: server!.udpPort!, discoveryWait: const Duration(seconds: 2));
    final result = await client.syncWith('pc');
    expect(result.received, greaterThan(0));
    expect(await doses(phoneDb), 1);
  });

  test('a device that is not there gives a plain message', () async {
    final client = LanSyncClient(phone, 'phone', discoveryTargets: [loopback], discoveryPort: 9, discoveryWait: const Duration(milliseconds: 300));
    await expectLater(client.syncWith('pc'), throwsA(isA<LanSyncException>()));
    await expectLater(client.syncWith('pc', address: '127.0.0.1', port: 9), throwsA(isA<LanSyncException>()));
  });

  test('a device with the wrong key is refused and nothing changes', () async {
    await seed(pcDb, 'mdma', DateTime(2026, 6, 1, 20));
    final strangerDb = AppDatabase.memory(deviceId: 'stranger', nowMillis: clock);
    addTearDown(strangerDb.close);
    final stranger = SyncService(strangerDb, deviceName: 'Stranger');
    final otherDb = AppDatabase.memory(deviceId: 'other', nowMillis: clock);
    addTearDown(otherDb.close);
    final other = SyncService(otherDb, deviceName: 'Other');
    await stranger.acceptPairing((await other.offerPairing()).encode()); // a different key entirely
    await seed(strangerDb, 'lsd', DateTime(2026, 6, 5, 20));

    // The stranger pretends 'other' is at the PC's address.
    final client = LanSyncClient(stranger, 'stranger');
    await expectLater(client.syncWith('other', address: '127.0.0.1', port: server!.httpPort), throwsA(isA<LanSyncException>()));
    expect(await doses(pcDb), 1);
  });

  test('requests that are not sync packages are turned away', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final bad = await (await http.postUrl(Uri.parse('http://127.0.0.1:${server!.httpPort}/sj/sync'))..write('hello')).close();
    expect(bad.statusCode, 400);
    final get = await (await http.getUrl(Uri.parse('http://127.0.0.1:${server!.httpPort}/'))).close();
    expect(get.statusCode, 404);
  });
}
