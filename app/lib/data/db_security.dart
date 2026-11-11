import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// Encryption at rest for the journal database (SQLite3 Multiple Ciphers, ChaCha20-Poly1305).
///
/// The key is random, never typed, and lives in the operating system's credential store (Android
/// Keystore, Windows Credential Manager, the Linux keyring). The database file, its automatic
/// copies and its journal are unreadable without it, so copying the file off the device, or
/// reading it from another program that cannot reach the credential store, gets nothing.
///
/// This is not a defence against malware running as you on an unlocked, already signed-in
/// computer: such a program can ask the credential store for the key too.

const _keyName = 'sj.db.key';
const _plainHeader = 'SQLite format 3\u0000';

/// Where the key is kept. Replaced in tests.
abstract class KeyVault {
  Future<String?> read();
  Future<void> write(String hex);
}

class SecureKeyVault implements KeyVault {
  SecureKeyVault(this.fallbackFolder);

  /// Used only when the credential store cannot be reached at all (a Linux desktop without a
  /// keyring). The file is readable by this user alone.
  final Directory fallbackFolder;
  final _store = const FlutterSecureStorage();

  File get _file => File(p.join(fallbackFolder.path, 'db.key'));

  @override
  Future<String?> read() async {
    try {
      final v = await _store.read(key: _keyName);
      if (v != null && v.isNotEmpty) return v;
    } on Object {
      // Fall through to the file.
    }
    try {
      if (_file.existsSync()) {
        final v = _file.readAsStringSync().trim();
        if (v.isNotEmpty) return v;
      }
    } on Object {
      // No key.
    }
    return null;
  }

  @override
  Future<void> write(String hex) async {
    try {
      await _store.write(key: _keyName, value: hex);
      if ((await _store.read(key: _keyName)) == hex) return;
    } on Object {
      // Use the file.
    }
    await fallbackFolder.create(recursive: true);
    _file.writeAsStringSync(hex, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', _file.path]);
  }
}

class KeyUnavailable implements Exception {
  const KeyUnavailable();
  @override
  String toString() => 'The key that protects the journal could not be found on this device.';
}

String newKeyHex() {
  final random = Random.secure();
  return [for (var i = 0; i < 32; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// True when [file] starts with the plain SQLite header (so it is not encrypted yet).
bool isPlainSqlite(File file) {
  try {
    final raf = file.openSync();
    try {
      final head = raf.readSync(16);
      return head.length == 16 && String.fromCharCodes(head) == _plainHeader;
    } finally {
      raf.closeSync();
    }
  } on Object {
    return false;
  }
}

/// Unlocks an open connection with [hex]. Throws if the key is wrong.
void applyKey(sql.Database raw, String hex) {
  raw.execute("PRAGMA hexkey = '$hex'");
  raw.select('SELECT count(*) FROM sqlite_master'); // fails here, not later, on a wrong key
}

/// A background connection to [file] opened with [hex].
QueryExecutor openEncrypted(File file, String hex) => NativeDatabase.createInBackground(file, setup: (raw) => applyKey(raw, hex));

/// The key to use for [file]: the stored one, or a new one when there is nothing to lose.
/// Never makes a new key for a database that is already encrypted.
Future<String> loadOrCreateKey(KeyVault vault, File file) async {
  final stored = await vault.read();
  if (stored != null) return stored;
  if (file.existsSync() && file.lengthSync() > 0 && !isPlainSqlite(file)) throw const KeyUnavailable();
  final fresh = newKeyHex();
  await vault.write(fresh);
  if (await vault.read() != fresh) throw const KeyUnavailable();
  return fresh;
}

/// Encrypts a plain database in place. Returns false if it was already encrypted or missing.
/// Keeps a temporary plain copy until the result has been checked, then wipes it.
Future<bool> encryptInPlace(File file, String hex, {bool keepSafetyCopy = true}) async {
  if (!file.existsSync() || file.lengthSync() == 0 || !isPlainSqlite(file)) return false;
  final safety = File('${file.path}.pre-encrypt');
  if (keepSafetyCopy) await file.copy(safety.path);
  try {
    final raw = sql.sqlite3.open(file.path);
    int before;
    try {
      raw.execute('PRAGMA journal_mode = DELETE');
      before = raw.select('PRAGMA user_version').first.values.first as int;
      raw.execute("PRAGMA hexrekey = '$hex'");
    } finally {
      raw.close();
    }
    if (isPlainSqlite(file)) throw StateError('The database is still readable without a key.');
    final check = sql.sqlite3.open(file.path, mode: sql.OpenMode.readOnly);
    try {
      applyKey(check, hex);
      if (check.select('PRAGMA user_version').first.values.first != before) throw StateError('The encrypted copy does not match.');
    } finally {
      check.close();
    }
  } on Object {
    if (keepSafetyCopy && safety.existsSync()) await safety.copy(file.path);
    rethrow;
  } finally {
    if (keepSafetyCopy) wipe(safety);
  }
  return true;
}

/// Overwrites a file with zeros before deleting it, so a plain copy does not linger on disk.
void wipe(File file) {
  try {
    if (!file.existsSync()) return;
    final length = file.lengthSync();
    final raf = file.openSync(mode: FileMode.write);
    try {
      final zeros = Uint8List(64 * 1024);
      for (var done = 0; done < length; done += zeros.length) {
        raf.writeFromSync(zeros, 0, min(zeros.length, length - done));
      }
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    file.deleteSync();
  } on Object {
    try {
      file.deleteSync();
    } on Object {
      // Nothing more to do.
    }
  }
}

/// Encrypts the automatic copies that earlier versions left as plain files. Best effort.
Future<void> encryptCopies(Directory folder, String hex) async {
  try {
    if (!folder.existsSync()) return;
    for (final f in folder.listSync().whereType<File>()) {
      if (!f.path.endsWith('.db')) continue;
      try {
        await encryptInPlace(f, hex);
      } on Object {
        // Leave a copy that will not convert; it is only a convenience.
      }
    }
  } on Object {
    // Ignored on purpose.
  }
}
