import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sj_core/sj_core.dart';

import 'data/alcohol_import.dart';
import 'data/custom_substances.dart';
import 'data/database.dart';
import 'data/reference_repository.dart';
import 'data/auto_sync.dart';
import 'data/lan_sync.dart';
import 'data/reminders.dart';
import 'ui/quicklog/launch_route.dart';
import 'data/sync.dart';

/// Overridden at startup (and in tests) with real instances.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider'));
final referenceProvider = Provider<ReferenceRepository>((ref) => throw UnimplementedError('referenceProvider'));
final interactionPairsProvider = Provider<List<TripSitPair>>((ref) => const []);

/// The time "now", overridable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Bumps every 30 seconds and whenever the app returns to the foreground, so anything showing
/// "now" (curves, Now markers, active timers) moves on instead of freezing at the last rebuild.
class ClockTick extends Notifier<int> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  int build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => state++);
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });
    return 0;
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState state_) {
    if (state_ == AppLifecycleState.resumed) state++;
  }
}

final clockTickProvider = NotifierProvider<ClockTick, int>(ClockTick.new);

/// The current time, refreshed by [clockTickProvider]. Watch this (not [clockProvider]) in any
/// widget that draws something relative to now.
final nowProvider = Provider<DateTime>((ref) {
  ref.watch(clockTickProvider);
  return ref.watch(clockProvider)();
});

// ---- compounds: reference data plus the user's own ----

final customSubstancesProvider =
    StreamProvider<List<CustomSubstance>>((ref) => ref.watch(databaseProvider).watchCustomSubstances());

final customUnitsProvider = StreamProvider<List<CustomUnit>>((ref) => ref.watch(databaseProvider).watchCustomUnits());

/// Everything the UI should look compounds up in: bundled reference data plus custom
/// compounds. Deleted custom compounds still resolve (for old ingestions) but are not offered.
final catalogProvider = Provider<ReferenceRepository>((ref) {
  final base = ref.watch(referenceProvider);
  final rows = ref.watch(customSubstancesProvider).value ?? const <CustomSubstance>[];
  return base.withCustom(
    active: [for (final r in rows) if (!r.deleted) substanceFromCustom(r)],
    archived: [for (final r in rows) if (r.deleted) substanceFromCustom(r)],
  );
});

// ---- people ----

final peopleProvider = StreamProvider<List<Person>>((ref) => ref.watch(databaseProvider).watchPeople());

final _currentPersonIdProvider =
    StreamProvider<String?>((ref) => ref.watch(databaseProvider).watchSetting('currentPersonId'));

/// The person whose journal is on screen. Everything personal (experiences, usage, curves,
/// tolerance, warnings) is read through this one person; there is no "everyone" view.
final currentPersonProvider = Provider<Person?>((ref) {
  final people = ref.watch(peopleProvider).value ?? const <Person>[];
  if (people.isEmpty) return null;
  final id = ref.watch(_currentPersonIdProvider).value;
  return people.firstWhere(
    (p) => p.id == id,
    orElse: () => people.firstWhere((p) => p.isDefault, orElse: () => people.first),
  );
});

// ---- per-person data ----

final experiencesProvider = StreamProvider.autoDispose.family<List<Experience>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchExperiences(personId),
);

final personIngestionsProvider = StreamProvider.autoDispose.family<List<Ingestion>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchIngestionsForPerson(personId),
);

final personRatingsProvider = StreamProvider.autoDispose.family<List<Rating>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchRatingsForPerson(personId),
);

final usageProvider = StreamProvider.autoDispose.family<Map<String, UsageStat>, String>(
  (ref, personId) => ref.watch(databaseProvider).watchUsageForPerson(personId),
);

final compoundPrefsProvider = StreamProvider.autoDispose.family<CompoundPrefs, String>(
  (ref, personId) => ref.watch(databaseProvider).watchCompoundPrefs(personId),
);

// ---- Alcohol mode ----

/// Whether this device shows the alcohol-only app. A per-device choice, not synced.
final alcoholModeProvider = StreamProvider<bool>(
  (ref) => ref.watch(databaseProvider).watchSetting('alcoholMode').map((v) => v == 'true'),
);

final estimateSettingsProvider = StreamProvider.autoDispose.family<EstimateSettings, String>(
  (ref, personId) => ref.watch(databaseProvider).watchEstimateSettings(personId),
);

final limitsProvider = StreamProvider.autoDispose.family<DrinkLimits, String>(
  (ref, personId) => ref.watch(databaseProvider).watchLimits(personId),
);

/// Saved cannabis strains and batches, shared by everyone on this journal.
final cannabisProductsProvider = StreamProvider<List<Product>>((ref) => ref.watch(databaseProvider).watchProducts('cannabis'));

/// Saved dose presets for one substance and route, keyed "substance|route".
final dosePresetsProvider = StreamProvider.autoDispose.family<List<Preset>, String>((ref, key) {
  final parts = key.split('|');
  return ref.watch(databaseProvider).watchDosePresets(parts[0], parts[1]);
});

/// Every saved sample, and the drug-checking tests done on them.
final samplesProvider = StreamProvider<List<Product>>((ref) => ref.watch(databaseProvider).watchSamples());

final reagentTestsProvider = StreamProvider<List<ReagentTest>>((ref) => ref.watch(databaseProvider).watchReagentTests());

final allDosePresetsProvider = StreamProvider<List<Preset>>((ref) => ref.watch(databaseProvider).watchAllDosePresets());

final drinkPresetsProvider = StreamProvider<List<Preset>>((ref) => ref.watch(databaseProvider).watchDrinkPresets());

/// One person's alcohol ingestions, oldest first.
final alcoholDrinksProvider = Provider.autoDispose.family<List<Ingestion>, String>((ref, personId) {
  final all = ref.watch(personIngestionsProvider(personId)).value ?? const <Ingestion>[];
  return [for (final i in all) if (i.substanceKey == 'alcohol') i];
});

// ---- importing from Alcohol Tracker ----

/// Asks for a PsychonautWiki Journal export. Replaced in tests so no real dialog opens.
final pwFilePickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        dialogTitle: 'Choose a PsychonautWiki Journal export',
      );
      return file?.path;
    });

/// Asks the user for a file. Replaced in tests so no real dialog opens.
final trackerFilePickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'db', 'sqlite', 'sqlite3'],
        dialogTitle: 'Choose an Alcohol Tracker export or database',
      );
      return file?.path;
    });

/// Alcohol Tracker's database on this computer, if it exists (never on phones).
final trackerDefaultPathProvider = Provider<String?>((ref) {
  final path = defaultTrackerDatabasePath();
  return path != null && File(path).existsSync() ? path : null;
});

// ---- calendar (the one place that looks across people) ----

final allExperiencesProvider =
    StreamProvider.autoDispose<List<Experience>>((ref) => ref.watch(databaseProvider).watchAllExperiences());

final allIngestionsProvider =
    StreamProvider.autoDispose<List<Ingestion>>((ref) => ref.watch(databaseProvider).watchAllIngestions());

// ---- one experience ----

final experienceProvider = StreamProvider.autoDispose.family<Experience?, String>(
  (ref, id) => ref.watch(databaseProvider).watchExperience(id),
);

final experienceIngestionsProvider = StreamProvider.autoDispose.family<List<Ingestion>, String>(
  (ref, id) => ref.watch(databaseProvider).watchIngestionsForExperience(id),
);

final timedNotesProvider = StreamProvider.autoDispose.family<List<TimedNote>, String>(
  (ref, id) => ref.watch(databaseProvider).watchTimedNotes(id),
);

final ratingsProvider = StreamProvider.autoDispose.family<List<Rating>, String>(
  (ref, id) => ref.watch(databaseProvider).watchRatings(id),
);

// ---- appearance ----

/// The accent colour chosen on this device (null for the default blue).
final accentColorProvider = StreamProvider<Color?>((ref) {
  return ref.watch(databaseProvider).watchSetting('accentColor').map((v) => v == null ? null : Color(int.parse(v)));
});

final rainbowAccentProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchSetting('rainbowAccent').map((v) => v == 'true');
});

final themeModeProvider = StreamProvider<ThemeMode>((ref) {
  return ref.watch(databaseProvider).watchSetting('themeMode').map(
        (v) => switch (v) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
});

// ---- syncing between devices ----

/// A readable default name for this device until the user names it.
String defaultDeviceName() {
  if (Platform.isAndroid) return 'Phone';
  if (Platform.isIOS) return 'iPhone';
  return Platform.localHostname;
}

final deviceNameProvider = StreamProvider<String>(
  (ref) => ref.watch(databaseProvider).watchSetting('deviceName').map((v) => v ?? defaultDeviceName()),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(databaseProvider), deviceName: ref.watch(deviceNameProvider).value ?? defaultDeviceName()),
);

/// Answers sync requests from your other devices while the app is open. Not started in tests.
final lanServerProvider = Provider<LanSyncServer?>((ref) {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  final server = LanSyncServer(ref.watch(syncServiceProvider), ref.watch(databaseProvider).deviceId);
  ref.onDispose(server.stop);
  server.start();
  return server;
});

/// Syncs with paired devices on its own while the app is open. Not started in tests.
final autoSyncProvider = Provider<AutoSync?>((ref) {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  final sync = ref.watch(syncServiceProvider);
  final auto = AutoSync(ref.watch(databaseProvider), sync, ref.watch(lanClientProvider));
  ref.onDispose(auto.stop);
  auto.start();
  return auto;
});

/// How notifications are delivered. Replaced in tests.
final notifierProvider = Provider<ReminderNotifier>((ref) => LocalNotifier());

/// Daily check-in and limit alerts, running while the app is open. Not started in tests.
final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(ref.watch(databaseProvider), ref.watch(notifierProvider), reference: ref.watch(catalogProvider));
  ref.onDispose(service.stop);
  if (!Platform.environment.containsKey('FLUTTER_TEST')) service.start();
  return service;
});

final reminderPrefsProvider = StreamProvider<ReminderPrefs>(
  (ref) => ref.watch(databaseProvider).watchSetting('reminders').map(ReminderPrefs.decode),
);

final autoSyncEnabledProvider = StreamProvider<bool>(
  (ref) => ref.watch(databaseProvider).watchSetting('autoSync').map((v) => v != 'false'),
);

final lanClientProvider = Provider<LanSyncClient>(
  (ref) => LanSyncClient(ref.watch(syncServiceProvider), ref.watch(databaseProvider).deviceId),
);

/// Cameras are for phones and tablets; computers use paste, a file or Share instead.
/// Opens a web link in the browser. Replaced in tests.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>((ref) => (uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
});

/// Routes from outside the app (Android shortcut, tile, widget). Replaced in tests.
final launchRoutesProvider = Provider<LaunchRoutes>((ref) => LaunchRoutes());

final cameraScannerAvailableProvider = Provider<bool>((ref) => Platform.isAndroid || Platform.isIOS);

/// Picks a sync package file and returns its text. Replaced in tests.
final packageFilePickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final file = await FilePicker.pickFile(dialogTitle: 'Choose a sync package (.sjsync)');
      final path = file?.path;
      return path == null ? null : File(path).readAsString();
    });

/// Saves package text to a file the user chooses; returns where, or null if cancelled.
final packageSaverProvider = Provider<Future<String?> Function(String fileName, String text)>((ref) => (fileName, text) async {
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(text)),
        dialogTitle: 'Save sync package',
      );
      return saved?.toFilePath();
    });

/// Saves a binary file (a PDF) where the person chooses. Replaced in tests.
final fileSaverProvider = Provider<Future<String?> Function(String fileName, Uint8List bytes)>((ref) => (fileName, bytes) async {
      final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, dialogTitle: 'Save summary');
      return saved?.toFilePath();
    });

/// Shares a binary file through the system share sheet. Replaced in tests.
final fileSharerProvider = Provider<Future<void> Function(String fileName, Uint8List bytes)>((ref) => (fileName, bytes) async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Substance Journal summary'));
    });

/// Shares package text as a file through the system share sheet.
final packageSharerProvider = Provider<Future<void> Function(String fileName, String text)>((ref) => (fileName, text) async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Substance Journal sync'));
    });
