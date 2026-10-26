import 'dart:convert';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final key = generateSyncKey();
  final plain = utf8.encode(jsonEncode({'rows': List.generate(200, (i) => 'row $i')}));

  test('a package round-trips and says who sent it', () async {
    final text = await sealSyncPackage(senderId: 'phone-1', key: key, plain: plain);
    expect(text, startsWith('SJSYNC1:'));
    expect(senderOfPackage(text), 'phone-1');
    expect(await openSyncPackage(text, key), plain);
  });

  test('the text reveals nothing readable', () async {
    final text = await sealSyncPackage(senderId: 'd', key: key, plain: utf8.encode('secret ingestion data'));
    expect(text.contains('secret'), isFalse);
    expect(text.contains('ingestion'), isFalse);
  });

  test('a wrong key, a changed character or a changed sender all fail', () async {
    final text = await sealSyncPackage(senderId: 'phone-1', key: key, plain: plain);
    await expectLater(openSyncPackage(text, generateSyncKey()), throwsA(isA<SyncCryptoException>()));
    final i = text.length ~/ 2;
    final flipped = text.substring(0, i) + (text[i] == 'A' ? 'B' : 'A') + text.substring(i + 1);
    await expectLater(openSyncPackage(flipped, key), throwsA(isA<SyncCryptoException>()));
    final forged = await sealSyncPackage(senderId: 'phone-2', key: key, plain: plain);
    // Swap the claimed sender in the header: the header is authenticated.
    final spliced = text.substring(0, 20) + forged.substring(20, 24) + text.substring(24);
    await expectLater(openSyncPackage(spliced, key), throwsA(isA<SyncCryptoException>()));
    await expectLater(openSyncPackage('hello', key), throwsA(isA<SyncCryptoException>()));
  });

  test('packages are compressed', () async {
    final text = await sealSyncPackage(senderId: 'd', key: key, plain: plain);
    expect(text.length, lessThan(plain.length));
  });

  test('pairing codes round-trip and reject junk', () {
    final code = PairingCode(deviceId: 'pc-1', deviceName: "Michael's PC", key: key);
    final back = PairingCode.decode(code.encode())!;
    expect(back.deviceId, 'pc-1');
    expect(back.deviceName, "Michael's PC");
    expect(back.key, key);
    expect(PairingCode.decode('nonsense'), isNull);
    expect(PairingCode.decode('SJPAIR1:@@@'), isNull);
  });

  test('frames reassemble in any order, tolerate repeats, and ignore other transfers', () async {
    final text = await sealSyncPackage(senderId: 'd', key: key, plain: plain);
    final frames = splitIntoFrames(text, frameSize: 120);
    expect(frames.length, greaterThan(3));
    final assembler = FrameAssembler();
    for (final f in frames.reversed) {
      expect(assembler.add(f), isTrue);
      assembler.add(f); // a repeat
    }
    expect(assembler.isComplete, isTrue);
    expect(assembler.progress, 1.0);
    expect(assembler.payload, text);
    expect(await openSyncPackage(assembler.payload, key), plain);

    final other = splitIntoFrames('abcdef', frameSize: 3, transferId: 'zzzz');
    final partial = FrameAssembler()..add(frames.first);
    expect(partial.add(other.first), isFalse);
    expect(partial.isComplete, isFalse);
    expect(FrameAssembler().add('not a frame'), isFalse);
  });

  test('frames can carry text containing the separator', () {
    final frames = splitIntoFrames('a|b|c|d|e', frameSize: 4);
    final assembler = FrameAssembler();
    for (final f in frames) {
      assembler.add(f);
    }
    expect(assembler.payload, 'a|b|c|d|e');
  });
}
