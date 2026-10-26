import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:path/path.dart' as p;
import 'package:sj_core/sj_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'database.dart';
import 'sync.dart';

/// Backups and exports.
///
/// - Encrypted backup: the whole journal as one passphrase-protected text file. Restoring merges
///   it in with the same rules as sync (the later edit of each row wins, deletes included), so
///   restoring an old backup never wipes newer entries.
/// - Export: plain CSV (opens in a spreadsheet) or JSON, for your own use. Not encrypted.
/// - Automatic copies: a daily copy of the database file kept on this device, plus one before the
///   database is upgraded to a newer version of the app.
class BackupService {
  BackupService(this.db, this.sync);

  final AppDatabase db;
  final SyncService sync;

  Future<String> createEncryptedBackup(String passphrase) async {
    final changes = await sync.buildChangeset();
    final body = {
      'kind': 'substance-journal-backup',
      'v': 1,
      'created': DateTime.now().toIso8601String(),
      'device': db.deviceId,
      ...changes,
    };
    return sealBackup(utf8.encode(jsonEncode(body)), passphrase);
  }

  /// Merges a backup into the journal. Throws [SyncCryptoException] for a wrong passphrase.
  Future<ApplyResult> restoreEncryptedBackup(String text, String passphrase) async {
    final plain = await openBackup(text, passphrase);
    final body = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    if (body['kind'] != 'substance-journal-backup') throw const SyncException('This file is not a Substance Journal backup.');
    return sync.mergeBackup(body);
  }

  // ---- plain exports ----

  /// Every ingestion of every person, one row each, for a spreadsheet.
  Future<String> exportCsv() async {
    final people = {for (final p in await db.select(db.people).get()) p.id: p.name};
    final experiences = {for (final e in await db.select(db.experiences).get()) e.id: e};
    final rows = await (db.select(db.ingestions)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.time)]))
        .get();
    final out = StringBuffer('person,date,time,substance,route,dose,unit,dose_is_estimate,experience,notes\r\n');
    for (final i in rows) {
      final e = experiences[i.experienceId];
      if (e == null || e.deleted) continue;
      final t = i.time;
      String two(int n) => n.toString().padLeft(2, '0');
      out.write([
        people[i.personId] ?? '',
        '${t.year}-${two(t.month)}-${two(t.day)}',
        '${two(t.hour)}:${two(t.minute)}',
        i.substanceKey,
        i.route,
        i.dose ?? '',
        i.unit ?? '',
        i.doseIsEstimate ? 'yes' : '',
        e.title,
        i.notes,
      ].map(_csvCell).join(','));
      out.write('\r\n');
    }
    return out.toString();
  }

  /// All rows as readable JSON.
  Future<String> exportJson() async {
    final changes = await sync.buildChangeset();
    return const JsonEncoder.withIndent('  ').convert({
      'kind': 'substance-journal-export',
      'created': DateTime.now().toIso8601String(),
      ...changes,
    });
  }

  // ---- automatic copies ----

  /// Backup folder next to the database file.
  static Directory folderFor(File databaseFile) => Directory(p.join(databaseFile.parent.path, 'backups'));

  /// Copies the database file when it is about to be upgraded to [targetVersion], and once a day.
  /// Keeps the newest [keepDaily] daily copies; upgrade copies are never deleted automatically.
  /// Call before the database is opened. Never throws: a backup problem must not stop the app.
  static Future<void> autoBackup(File databaseFile, {required int targetVersion, DateTime? now, int keepDaily = 14}) async {
    try {
      if (!databaseFile.existsSync() || databaseFile.lengthSync() == 0) return;
      final folder = folderFor(databaseFile);
      await folder.create(recursive: true);
      final stamp = now ?? DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final day = '${stamp.year}-${two(stamp.month)}-${two(stamp.day)}';

      final current = _userVersion(databaseFile);
      if (current != null && current < targetVersion) {
        final upgrade = File(p.join(folder.path, 'before-upgrade-from-v$current.db'));
        if (!upgrade.existsSync()) await databaseFile.copy(upgrade.path);
      }

      final daily = File(p.join(folder.path, 'daily-$day.db'));
      if (!daily.existsSync()) await databaseFile.copy(daily.path);

      final dailies = [
        for (final f in folder.listSync().whereType<File>())
          if (p.basename(f.path).startsWith('daily-')) f,
      ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final old in dailies.skip(keepDaily)) {
        await old.delete();
      }
    } on Object {
      // Ignored on purpose.
    }
  }

  static int? _userVersion(File file) {
    try {
      final raw = sql.sqlite3.open(file.path, mode: sql.OpenMode.readOnly);
      try {
        return raw.select('PRAGMA user_version').first.values.first as int;
      } finally {
        raw.close();
      }
    } on Object {
      return null;
    }
  }

  /// The automatic copies kept in [folder], newest first.
  static List<File> listCopies(Directory folder) {
    if (!folder.existsSync()) return const [];
    return [for (final f in folder.listSync().whereType<File>()) if (f.path.endsWith('.db')) f]
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }
}

String _csvCell(Object? value) {
  final text = '$value';
  // Cells starting with these are read as formulas by spreadsheets; neutralise them.
  final safe = text.isNotEmpty && '=+-@'.contains(text[0]) && double.tryParse(text) == null ? "'$text" : text;
  return safe.contains(RegExp(r'[",\r\n]')) ? '"${safe.replaceAll('"', '""')}"' : safe;
}
