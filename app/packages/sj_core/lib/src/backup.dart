import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'sync_package.dart';

/// Password-protected backup text: a sealed package whose key comes from a passphrase.
///
/// Format: `SJBAK1|<salt>|<sealed package>`. The key is PBKDF2-HMAC-SHA256 of the passphrase with
/// a random salt, so the same passphrase gives a different key for every backup.
const String _backupPrefix = 'SJBAK1|';
const int _iterations = 150000;

Future<Uint8List> _deriveKey(String passphrase, List<int> salt) {
  // PBKDF2 is slow in pure Dart; keep it off the calling isolate so a screen does not freeze.
  return Isolate.run(() async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  });
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List _unb64(String text) => Uint8List.fromList(base64Url.decode(text.padRight((text.length + 3) ~/ 4 * 4, '=')));

/// Encrypts [plain] (JSON bytes) under [passphrase].
Future<String> sealBackup(List<int> plain, String passphrase) async {
  if (passphrase.length < 6) throw const SyncCryptoException('Use a passphrase of at least 6 characters.');
  final random = Random.secure();
  final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  final key = await _deriveKey(passphrase, salt);
  final sealed = await sealSyncPackage(senderId: 'backup', key: key, plain: plain);
  return '$_backupPrefix${_b64(salt)}|$sealed';
}

bool looksLikeBackup(String text) => text.trimLeft().startsWith(_backupPrefix);

/// Opens a backup. Throws [SyncCryptoException] for a wrong passphrase or a damaged file.
Future<Uint8List> openBackup(String text, String passphrase) async {
  final body = text.trim();
  if (!body.startsWith(_backupPrefix)) throw const SyncCryptoException('This is not a Substance Journal backup.');
  final parts = body.substring(_backupPrefix.length).split('|');
  if (parts.length != 2) throw const SyncCryptoException('This backup is damaged.');
  final Uint8List key;
  try {
    key = await _deriveKey(passphrase, _unb64(parts[0]));
  } on FormatException {
    throw const SyncCryptoException('This backup is damaged.');
  }
  try {
    return await openSyncPackage(parts[1], key);
  } on SyncCryptoException {
    throw const SyncCryptoException('Wrong passphrase, or the backup is damaged.');
  }
}
