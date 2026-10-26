import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Sealed, portable sync packages and the QR framing that carries them.
///
/// A package is compressed, then encrypted with AES-256-GCM under a key two devices share (set up
/// when they pair). Anyone who handles the text, a messaging app or a clipboard, sees only
/// ciphertext, and a changed byte fails the authentication tag. The sender's device id travels
/// in the clear (and is authenticated) so the receiver knows which key to try.

class SyncCryptoException implements Exception {
  const SyncCryptoException(this.message);
  final String message;
  @override
  String toString() => message;
}

const String _packagePrefix = 'SJSYNC1:';
const String _pairingPrefix = 'SJPAIR1:';
const List<int> _magic = [0x53, 0x4a, 0x53, 0x31]; // "SJS1"

final AesGcm _aes = AesGcm.with256bits();

/// A fresh random 256-bit key for a pairing.
Uint8List generateSyncKey() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List _unb64(String text) {
  final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

/// Compresses and encrypts [plain] (JSON bytes) for the peer who holds [key].
Future<String> sealSyncPackage({required String senderId, required Uint8List key, required List<int> plain}) async {
  final id = utf8.encode(senderId);
  if (id.length > 255) throw const SyncCryptoException('Device id too long');
  final header = Uint8List.fromList([..._magic, id.length, ...id]);
  final nonce = _aes.newNonce();
  final box = await _aes.encrypt(gzip.encode(plain), secretKey: SecretKey(key), nonce: nonce, aad: header);
  return _packagePrefix + _b64([...header, ...nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// The device id a package claims to come from, or null if [text] is not a package.
String? senderOfPackage(String text) {
  final body = text.trim();
  if (!body.startsWith(_packagePrefix)) return null;
  try {
    final bytes = _unb64(body.substring(_packagePrefix.length));
    if (bytes.length < 5 || !_startsWithMagic(bytes)) return null;
    final length = bytes[4];
    return utf8.decode(bytes.sublist(5, 5 + length));
  } on Object {
    return null;
  }
}

bool _startsWithMagic(List<int> bytes) {
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return false;
  }
  return true;
}

/// Decrypts and decompresses a package. Throws [SyncCryptoException] on a wrong key, damage or tampering.
Future<Uint8List> openSyncPackage(String text, Uint8List key) async {
  final body = text.trim();
  if (!body.startsWith(_packagePrefix)) throw const SyncCryptoException('This is not a Substance Journal sync package.');
  try {
    final bytes = _unb64(body.substring(_packagePrefix.length));
    if (!_startsWithMagic(bytes)) throw const SyncCryptoException('Unknown package version.');
    final headerLength = 5 + bytes[4];
    final header = bytes.sublist(0, headerLength);
    final nonce = bytes.sublist(headerLength, headerLength + 12);
    final cipher = bytes.sublist(headerLength + 12, bytes.length - 16);
    final mac = bytes.sublist(bytes.length - 16);
    final clear = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: SecretKey(key), aad: header);
    return Uint8List.fromList(gzip.decode(clear));
  } on SyncCryptoException {
    rethrow;
  } on Object {
    throw const SyncCryptoException('Could not open this package: wrong pairing or the text was damaged.');
  }
}

// ---- pairing codes ----

class PairingCode {
  const PairingCode({required this.deviceId, required this.deviceName, required this.key});
  final String deviceId;
  final String deviceName;
  final Uint8List key;

  /// Short text for a QR code or for typing between devices.
  String encode() => _pairingPrefix + _b64(utf8.encode(jsonEncode({'id': deviceId, 'name': deviceName, 'key': _b64(key)})));

  static PairingCode? decode(String text) {
    final body = text.trim();
    if (!body.startsWith(_pairingPrefix)) return null;
    try {
      final json = jsonDecode(utf8.decode(_unb64(body.substring(_pairingPrefix.length)))) as Map<String, dynamic>;
      final key = _unb64(json['key'] as String);
      if (key.length != 32) return null;
      return PairingCode(deviceId: json['id'] as String, deviceName: json['name'] as String, key: key);
    } on Object {
      return null;
    }
  }
}

// ---- QR frames ----

/// Splits [payload] into frames small enough for a QR code. Show them one after another; the
/// receiver collects them in any order and repeats are harmless.
List<String> splitIntoFrames(String payload, {int frameSize = 700, String? transferId}) {
  final id = transferId ?? _b64(List.generate(4, (_) => Random.secure().nextInt(256)));
  final parts = <String>[];
  for (var i = 0; i < payload.length; i += frameSize) {
    parts.add(payload.substring(i, min(i + frameSize, payload.length)));
  }
  if (parts.isEmpty) parts.add('');
  return [for (var i = 0; i < parts.length; i++) 'SJF1|$id|$i|${parts.length}|${parts[i]}'];
}

/// Collects frames from a camera until the whole payload has arrived.
class FrameAssembler {
  String? _id;
  int _total = 0;
  final Map<int, String> _parts = {};

  int get received => _parts.length;
  int get total => _total;
  bool get isComplete => _total > 0 && _parts.length == _total;
  double get progress => _total == 0 ? 0 : _parts.length / _total;

  /// Returns false for text that is not a frame (or belongs to a different transfer once one started).
  bool add(String frame) {
    final pieces = frame.split('|');
    if (pieces.length < 5 || pieces[0] != 'SJF1') return false;
    final id = pieces[1];
    final index = int.tryParse(pieces[2]);
    final total = int.tryParse(pieces[3]);
    if (index == null || total == null || total <= 0 || index < 0 || index >= total) return false;
    if (_id != null && _id != id) return false;
    _id = id;
    _total = total;
    _parts[index] = pieces.sublist(4).join('|');
    return true;
  }

  /// The reassembled payload; only valid when [isComplete].
  String get payload => [for (var i = 0; i < _total; i++) _parts[i]!].join();

  void reset() {
    _id = null;
    _total = 0;
    _parts.clear();
  }
}
