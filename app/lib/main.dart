import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import 'app.dart';
import 'data/backup.dart';
import 'data/database.dart';
import 'data/db_security.dart';
import 'data/reference_repository.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final reference = await ReferenceRepository.load();
  final file = await defaultDatabaseFile();
  await file.parent.create(recursive: true);

  // The journal is encrypted with a random key kept in the operating system's credential store.
  // A journal from an earlier version is encrypted in place on first start.
  final vault = SecureKeyVault(file.parent);
  String? key;
  var encrypted = true;
  try {
    key = await loadOrCreateKey(vault, file);
    final converted = await encryptInPlace(file, key);
    if (converted) await encryptCopies(BackupService.folderFor(file), key);
  } on KeyUnavailable {
    runApp(const KeyMissingApp());
    return;
  } on Object catch (e) {
    // Never lose the journal over this: carry on as before, and say so in Settings.
    debugPrint('Database encryption failed: $e');
    key = null;
    encrypted = false;
  }
  QueryExecutor open() => key == null ? NativeDatabase.createInBackground(file) : openEncrypted(file, key);

  // The device id goes into every sync clock stamp; keep it stable across launches.
  // Keep a copy before anything touches the file: daily, and before a version upgrade.
  await BackupService.autoBackup(file, targetVersion: currentSchemaVersion, hexKey: key);

  final bootstrap = AppDatabase(open(), deviceId: 'pending');
  var deviceId = await bootstrap.getSetting('deviceId');
  await bootstrap.close();
  if (deviceId == null) {
    deviceId = newId();
    final setup = AppDatabase(open(), deviceId: deviceId);
    await setup.setSetting('deviceId', deviceId);
    await setup.close();
  }

  final db = AppDatabase(open(), deviceId: deviceId);
  await db.ensureDefaultPerson();

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      databaseEncryptedProvider.overrideWithValue(encrypted),
      referenceProvider.overrideWithValue(reference),
      interactionPairsProvider.overrideWithValue(reference.interactionPairs),
    ],
    child: const SubstanceJournalApp(),
  ));
}

/// Shown instead of the app when the journal is encrypted but its key is gone from this device
/// (for example after the Windows account or the phone's keystore was reset). Nothing is changed.
class KeyMissingApp extends StatelessWidget {
  const KeyMissingApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The key that protects your journal is not on this device, so it cannot be opened. Nothing has been changed or deleted. '
                'Restore the key (for example by signing in to the same Windows account), or restore an encrypted backup into a fresh install.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
