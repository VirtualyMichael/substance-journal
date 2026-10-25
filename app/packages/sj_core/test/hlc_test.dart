import 'dart:math';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  group('Hlc', () {
    test('send uses wall time when it moves forward, resetting the counter', () {
      final a = Hlc(1000, 5, 'A').send(2000);
      expect(a, Hlc(2000, 0, 'A'));
    });

    test('send bumps the counter when the wall clock has not advanced', () {
      expect(Hlc(1000, 5, 'A').send(1000), Hlc(1000, 6, 'A'));
      expect(Hlc(1000, 5, 'A').send(900), Hlc(1000, 6, 'A'));
    });

    test('receive always produces a clock after both inputs', () {
      final local = Hlc(1000, 2, 'A');
      final remote = Hlc(1000, 7, 'B');
      final merged = local.receive(remote, 1000);
      expect(merged > local, isTrue);
      expect(merged > remote, isTrue);
      expect(merged.nodeId, 'A');
    });

    test('receive from a device with a fast clock moves us forward', () {
      final merged = Hlc(1000, 0, 'A').receive(Hlc(5000, 3, 'B'), 2000);
      expect(merged.wallMillis, 5000);
      expect(merged.counter, 4);
    });

    test('receive rejects a clock more than a day ahead', () {
      expect(
        () => Hlc(1000, 0, 'A').receive(Hlc(1000 + Hlc.maxDriftMillis + 1, 0, 'B'), 1000),
        throwsStateError,
      );
    });

    test('string form round-trips and sorts like compareTo', () {
      final clocks = [Hlc(5, 0, 'B'), Hlc(5, 1, 'A'), Hlc(4, 255, 'Z'), Hlc(5, 0, 'A'), Hlc(123456789012, 65535, 'node-1')];
      for (final c in clocks) {
        expect(Hlc.parse(c.toString()), c);
      }
      final byCompare = [...clocks]..sort();
      final byString = [...clocks]..sort((a, b) => a.toString().compareTo(b.toString()));
      expect(byString, byCompare);
    });

    test('two devices that edit alternately never produce equal or backwards clocks', () {
      var a = Hlc.zero('A');
      var b = Hlc.zero('B');
      final rng = Random(7);
      var now = 1000;
      Hlc? last;
      for (var i = 0; i < 500; i++) {
        now += rng.nextInt(3) - 1; // clocks can stall or even step back
        if (rng.nextBool()) {
          a = a.send(now);
          b = b.receive(a, now);
          if (last != null) expect(a > last, isTrue);
          last = a;
        } else {
          b = b.send(now);
          a = a.receive(b, now);
          if (last != null) expect(b > last, isTrue);
          last = b;
        }
      }
    });
  });

  group('newId', () {
    test('is a version 4 UUID', () {
      final id = newId();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue, reason: id);
    });

    test('does not repeat', () {
      final ids = {for (var i = 0; i < 5000; i++) newId()};
      expect(ids.length, 5000);
    });

    test('is deterministic for a seeded generator', () {
      expect(newId(Random(1)), newId(Random(1)));
    });
  });
}
