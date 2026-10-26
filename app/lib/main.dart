import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/reference_repository.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final reference = await ReferenceRepository.load();
  final file = await defaultDatabaseFile();
  await file.parent.create(recursive: true);

  // The device id goes into every sync clock stamp; keep it stable across launches.
  final bootstrap = AppDatabase(NativeDatabase.createInBackground(file), deviceId: 'pending');
  var deviceId = await bootstrap.getSetting('deviceId');
  await bootstrap.close();
  if (deviceId == null) {
    deviceId = newId();
    final setup = AppDatabase(NativeDatabase.createInBackground(file), deviceId: deviceId);
    await setup.setSetting('deviceId', deviceId);
    await setup.close();
  }

  final db = AppDatabase(NativeDatabase.createInBackground(file), deviceId: deviceId);
  await db.ensureDefaultPerson();

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      referenceProvider.overrideWithValue(reference),
      interactionPairsProvider.overrideWithValue(reference.interactionPairs),
    ],
    child: const SubstanceJournalApp(),
  ));
}
