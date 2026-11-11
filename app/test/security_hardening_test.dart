import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/app_lock.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/digest_service.dart';
import 'package:substance_journal_app/data/lan_sync.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final loopback = InternetAddress.loopbackIPv4;

  group('the app lock', () {
    setUpAll(() => pinIterations = 1000);

    test('a PIN made by an earlier version (fewer rounds, no round count stored) still opens, and is flagged for upgrade', () async {
      final old = await lockWithPin('2580');
      // Rebuild what the earlier version stored: 20,000 rounds and no "iter" field.
      pinIterations = legacyPinIterations;
      final legacy = await lockWithPin('2580');
      pinIterations = 1000;
      final json = jsonDecode(legacy.encode()) as Map<String, dynamic>..remove('iter');
      final decoded = LockConfig.decode(jsonEncode(json));
      expect(decoded.iterations, legacyPinIterations);
      expect(await pinMatches(decoded, '2580'), isTrue);
      expect(await pinMatches(decoded, '2581'), isFalse);
      expect(old.iterations, 1000);
    });

    test('wrong tries are remembered so restarting the app is not a free retry', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      expect((await db.loadLockGuard()).failures, 0);
      final until = DateTime(2026, 7, 1, 12, 5);
      await db.saveLockGuard(LockGuard(failures: 6, waitUntil: until));
      final back = await db.loadLockGuard();
      expect(back.failures, 6);
      expect(back.waitUntil, until);
      expect(LockGuard.decode('garbage').failures, 0);
    });
  });

  group('sync', () {
    test('a paired device can change shared preferences but not private settings such as the lock', () async {
      expect(isSyncableSetting('estimate:abc'), isTrue);
      expect(isSyncableSetting('limits:abc'), isTrue);
      expect(isSyncableSetting('appLock'), isFalse);
      expect(isSyncableSetting('digestFolder'), isFalse);
      expect(isSyncableSetting('peerAddr:pc'), isFalse);
      expect(isSyncableSetting('lockGuard'), isFalse);

      final db = AppDatabase.memory(deviceId: 'a');
      addTearDown(db.close);
      final service = SyncService(db, deviceName: 'A');
      await db.setSetting('appLock', 'mine');
      final future = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
      await service.mergeBackup({
        'tables': {
          'settings': [
            {'key': 'appLock', 'value': 'attacker', 'hlc': '$future-0000-b', 'shared': true},
          ],
        },
      });
      expect(await db.getSetting('appLock'), 'mine');
    });

    test('the Wi-Fi server refuses an oversized request and gives a stranger no answer to discovery', () async {
      final db = AppDatabase.memory(deviceId: 'pc');
      addTearDown(db.close);
      final server = LanSyncServer(SyncService(db, deviceName: 'PC'), 'pc', port: 0, discoveryPort: 0, bindAddress: loopback);
      expect(await server.start(), isTrue);
      addTearDown(server.stop);

      // A body that claims to be far bigger than any journal is turned away before it is read.
      final tcp = await Socket.connect(loopback, server.httpPort!);
      addTearDown(tcp.destroy);
      tcp.write('POST /sj/sync HTTP/1.1\r\nHost: x\r\nContent-Length: ${maxSyncBodyBytes + 1}\r\n\r\nAAAA');
      final first = await utf8.decoder.bind(tcp).first.timeout(const Duration(seconds: 5));
      expect(first, startsWith('HTTP/1.1 413'));

      // A discovery request with no valid tag is ignored: nothing comes back.
      final socket = await RawDatagramSocket.bind(loopback, 0);
      addTearDown(socket.close);
      final heard = Completer<bool>();
      socket.listen((e) {
        if (e == RawSocketEvent.read && socket.receive() != null && !heard.isCompleted) heard.complete(true);
      });
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      socket.send(utf8.encode('SJ2?$now|abc|forged'), loopback, server.udpPort!);
      socket.send(utf8.encode('SJ?stranger'), loopback, server.udpPort!); // the old, unauthenticated form
      expect(await Future.any([heard.future, Future<bool>.delayed(const Duration(milliseconds: 700), () => false)]), isFalse);
    });

    test('a bounded reader gives up past its limit', () async {
      final big = Stream<List<int>>.fromIterable([List.filled(600, 1), List.filled(600, 1)]);
      expect(await readBounded(big, limit: 1000), isNull);
      expect(await readBounded(Stream<List<int>>.value(utf8.encode('hi')), limit: 1000), 'hi');
    });
  });

  test('deleting the digest removes only what the digest wrote', () {
    final dir = Directory.systemTemp.createTempSync('sj-digest');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/me').createSync();
    File('${dir.path}/me/profile.md').writeAsStringSync('x');
    File('${dir.path}/people.json').writeAsStringSync('{}');
    Directory('${dir.path}/photos').createSync();
    File('${dir.path}/photos/keep.jpg').writeAsStringSync('mine');
    expect(deleteDigestFiles(dir), 1);
    expect(Directory('${dir.path}/me').existsSync(), isFalse);
    expect(File('${dir.path}/people.json').existsSync(), isFalse);
    expect(File('${dir.path}/photos/keep.jpg').existsSync(), isTrue);
  });
}
