import 'dart:convert';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final plain = utf8.encode(jsonEncode({'ingestions': List.generate(50, (i) => 'dose $i')}));

  test('a backup opens with its passphrase and not without it', () async {
    final text = await sealBackup(plain, 'correct horse');
    expect(looksLikeBackup(text), isTrue);
    expect(text.contains('dose'), isFalse);
    expect(await openBackup(text, 'correct horse'), plain);
    await expectLater(openBackup(text, 'wrong passphrase'), throwsA(isA<SyncCryptoException>()));
    await expectLater(openBackup('SJBAK1|x', 'correct horse'), throwsA(isA<SyncCryptoException>()));
    await expectLater(openBackup('nope', 'correct horse'), throwsA(isA<SyncCryptoException>()));
  });

  test('each backup uses a fresh salt, and short passphrases are refused', () async {
    final a = await sealBackup(plain, 'passphrase');
    final b = await sealBackup(plain, 'passphrase');
    expect(a, isNot(b));
    await expectLater(sealBackup(plain, 'abc'), throwsA(isA<SyncCryptoException>()));
  });

  test('a changed character fails', () async {
    final text = await sealBackup(plain, 'passphrase');
    final i = text.length - 20;
    final flipped = text.substring(0, i) + (text[i] == 'A' ? 'B' : 'A') + text.substring(i + 1);
    await expectLater(openBackup(flipped, 'passphrase'), throwsA(isA<SyncCryptoException>()));
  });
}
