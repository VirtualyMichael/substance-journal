import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'database.dart';

/// How long the app may sit in the background before it asks again.
const lockTimeouts = <int, String>{
  0: 'Every time',
  60: 'After 1 minute',
  300: 'After 5 minutes',
  900: 'After 15 minutes',
};

const _settingKey = 'appLock';
const _iterations = 20000;

/// The app lock: a PIN (stored only as a salted hash, on this device) and whether the device's own
/// unlock (fingerprint, face or screen lock) may open the app too. It keeps people who pick up an
/// unlocked phone or computer out of the journal; it does not encrypt the data on disk.
class LockConfig {
  const LockConfig({this.hash, this.salt, this.useDevice = false, this.timeoutSeconds = 60});

  final String? hash;
  final String? salt;

  /// Also accept the device's fingerprint, face or screen lock.
  final bool useDevice;
  final int timeoutSeconds;

  bool get enabled => hash != null && salt != null;

  LockConfig copyWith({bool? useDevice, int? timeoutSeconds}) =>
      LockConfig(hash: hash, salt: salt, useDevice: useDevice ?? this.useDevice, timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds);

  String encode() => jsonEncode({'hash': hash, 'salt': salt, 'useDevice': useDevice, 'timeout': timeoutSeconds});

  static LockConfig decode(String? raw) {
    if (raw == null) return const LockConfig();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = j['timeout'];
      return LockConfig(
        hash: j['hash'] as String?,
        salt: j['salt'] as String?,
        useDevice: j['useDevice'] == true,
        timeoutSeconds: t is int && lockTimeouts.containsKey(t) ? t : 60,
      );
    } on Object {
      return const LockConfig();
    }
  }
}

/// Four to eight digits.
bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

Future<String> _hash(String pin, List<int> salt) async {
  final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256);
  final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
  return base64Encode(await key.extractBytes());
}

/// A config with this PIN set, keeping the other choices.
Future<LockConfig> lockWithPin(String pin, {LockConfig previous = const LockConfig()}) async {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  return LockConfig(hash: await _hash(pin, salt), salt: base64Encode(salt), useDevice: previous.useDevice, timeoutSeconds: previous.timeoutSeconds);
}

Future<bool> pinMatches(LockConfig config, String pin) async {
  if (!config.enabled) return false;
  final mine = await _hash(pin, base64Decode(config.salt!));
  // Compare every character so the time taken does not say how much matched.
  var diff = mine.length ^ config.hash!.length;
  for (var i = 0; i < mine.length && i < config.hash!.length; i++) {
    diff |= mine.codeUnitAt(i) ^ config.hash!.codeUnitAt(i);
  }
  return diff == 0;
}

/// Stored on this device only (never shared in a sync).
extension LockSettings on AppDatabase {
  Stream<LockConfig> watchLockConfig() => watchSetting(_settingKey).map(LockConfig.decode);
  Future<void> saveLockConfig(LockConfig c) => setSetting(_settingKey, c.encode());
  Future<void> clearLockConfig() => setSetting(_settingKey, const LockConfig().encode());
}
