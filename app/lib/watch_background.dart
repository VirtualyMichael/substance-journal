import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/database.dart';
import 'data/db_security.dart';
import 'data/reference_repository.dart';
import 'data/watch_bridge.dart';

const _channel = MethodChannel('sj/watchbg');

/// The entry point the phone starts, with no screen, when the watch asks for something while the
/// app is closed. It opens the journal the same way the app does, answers, and waits to be shut
/// down. Android calls "snapshot" (the data for the watch), "same" (log the last dose again) and
/// "close".
@pragma('vm:entry-point')
Future<void> watchMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  AppDatabase? db;
  ReferenceRepository? base;

  Future<AppDatabase> open() async {
    final existing = db;
    if (existing != null) return existing;
    final file = await defaultDatabaseFile();
    final key = await loadOrCreateKey(SecureKeyVault(file.parent), file);
    final bootstrap = AppDatabase(openEncrypted(file, key), deviceId: 'pending');
    final deviceId = await bootstrap.getSetting('deviceId') ?? 'watch';
    await bootstrap.close();
    final opened = AppDatabase(openEncrypted(file, key), deviceId: deviceId);
    db = opened;
    return opened;
  }

  Future<Map<String, Object?>> answer(String method) async {
    final database = await open();
    base ??= await ReferenceRepository.load();
    final prefs = await database.getWatchPrefs();
    if (!prefs.enabled) return {'ok': false, 'message': 'The watch is turned off in the app.'};
    final reference = await loadCatalogFor(database, base!);
    final person = await currentPersonFor(database);
    final now = DateTime.now();

    String? message;
    var ok = true;
    if (method == 'same') {
      final result = await logSameForWatch(db: database, reference: reference, personId: person.id, now: now);
      ok = result.ok;
      message = result.message;
    }
    final snapshot = buildWatchSnapshot(
      ingestions: await database.ingestionsForPerson(person.id),
      reference: reference,
      alcoholSettings: await database.getEstimateSettings(person.id),
      now: DateTime.now(),
      prefs: prefs,
    );
    return {'ok': ok, 'message': message, 'snapshot': jsonEncode(snapshot)};
  }

  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'snapshot':
      case 'same':
        try {
          return jsonEncode(await answer(call.method));
        } on Object catch (e) {
          return jsonEncode({'ok': false, 'message': 'Could not reach the journal ($e).'});
        }
      case 'close':
        await db?.close();
        db = null;
        return null;
      default:
        throw MissingPluginException();
    }
  });
  // Tell Android the handler is in place.
  unawaited(_channel.invokeMethod<void>('ready'));
}
