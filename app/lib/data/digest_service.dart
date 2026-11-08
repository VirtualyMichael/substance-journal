import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sj_core/sj_core.dart';

import 'database.dart';
import 'digest.dart';

/// Where the digest is written unless the person picked a folder: beside the journal database, in
/// the app's own data folder. Not Documents, which OneDrive and other backups often copy to the cloud.
Future<Directory> defaultDigestFolder() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'digest'));

String _slug(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'person' : s;
}

/// Builds one person's digest from the database.
Future<Digest> buildDigestForPerson(AppDatabase db, Person person, Map<String, Substance> byKey, DateTime now, {DigestOptions options = DigestOptions.full}) async {
  final experiences = await db.watchExperiences(person.id).first;
  final ids = {for (final e in experiences) e.id};
  return buildDigest(
    person: person,
    experiences: experiences,
    ingestions: await db.ingestionsForPerson(person.id),
    notes: [for (final n in await db.select(db.timedNotes).get()) if (ids.contains(n.experienceId)) n],
    ratings: [for (final r in await db.select(db.ratings).get()) if (ids.contains(r.experienceId)) r],
    products: await db.select(db.products).get(),
    byKey: byKey,
    now: now,
    alcoholSettings: await db.getEstimateSettings(person.id),
    options: options,
  );
}

/// Writes every person's digest under `root/person/` (replacing the previous one) and returns how
/// many files were written. A small `people.json` lists the people.
Future<int> writeDigestFolder(Directory root, AppDatabase db, Map<String, Substance> byKey, DateTime now, {DigestOptions options = DigestOptions.full}) async {
  final people = await db.activePeople();
  var written = 0;
  final names = <String>[];
  for (final person in people) {
    final digest = await buildDigestForPerson(db, person, byKey, now, options: options);
    final dir = Directory(p.join(root.path, _slug(person.name)));
    for (final sub in ['experiences', 'months']) {
      final d = Directory(p.join(dir.path, sub));
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    for (final entry in digest.files.entries) {
      final file = File(p.join(dir.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      written++;
    }
    names.add(_slug(person.name));
  }
  File(p.join(root.path, 'people.json')).writeAsStringSync('{"people": [${names.map((n) => '"$n"').join(', ')}]}');
  return written;
}

/// Keeps the digest folder current on a computer while the app is open: after the app starts and a
/// little after the journal changes. Off unless the person turned it on (it is readable text).
class DigestAutoWriter {
  DigestAutoWriter(this.db, this.byKey, this.now, {this.debounce = const Duration(seconds: 30)});

  final AppDatabase db;
  final Map<String, Substance> byKey;
  final DateTime Function() now;
  final Duration debounce;

  Timer? _timer;
  StreamSubscription<Object?>? _updates;
  bool _running = false;

  void start() {
    _timer = Timer(const Duration(seconds: 6), run);
    _updates = db
        .tableUpdates(TableUpdateQuery.onAllTables([db.ingestions, db.experiences, db.timedNotes, db.ratings, db.products]))
        .listen((_) {
      _timer?.cancel();
      _timer = Timer(debounce, run);
    });
  }

  void stop() {
    _timer?.cancel();
    _updates?.cancel();
  }

  Future<void> run() async {
    if (_running || await db.getSetting('digestAuto') != 'true') return;
    _running = true;
    try {
      final folder = await db.getSetting('digestFolder');
      final root = folder == null || folder.isEmpty ? await defaultDigestFolder() : Directory(folder);
      await writeDigestFolder(root, db, byKey, now());
    } on Object {
      // The folder may be missing or locked; the next change tries again.
    } finally {
      _running = false;
    }
  }
}
