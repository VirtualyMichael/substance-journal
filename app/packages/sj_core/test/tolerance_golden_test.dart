import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

// Golden vectors come from the Python implementation: python scripts/export_golden.py
void main() {
  final golden = jsonDecode(File('test/golden/tolerance.json').readAsStringSync()) as Map<String, dynamic>;
  final substances = parseSubstances(File('../../../data/substances.json').readAsStringSync());
  final byKey = {for (final s in substances) s.key: s};

  test('half-life and track keys match Python for every substance with tolerance', () {
    final halfLives = (golden['half_life_days'] as Map<String, dynamic>).cast<String, num>();
    final tracks = (golden['tracks'] as Map<String, dynamic>).cast<String, String>();
    expect(halfLives, isNotEmpty);
    halfLives.forEach((key, expected) {
      expect(halfLifeDays(byKey[key]!), closeTo(expected.toDouble(), 1e-12), reason: key);
      expect(toleranceTrackKey(byKey[key]!), tracks[key], reason: key);
    });
    expect(halfLives.containsKey('dmt'), isFalse);
  });

  // The Python reference has only the generic model. LSD and psilocybin mushrooms now have a
  // published tolerance profile in the Dart app (tolerance_profile.dart), so the port is checked
  // against the generic model, which is still what every other substance uses.
  for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
    test('generic tolerance levels match Python: ${c['name']}', () {
      final events = [
        for (final e in (c['events'] as List).cast<Map<String, dynamic>>())
          UseEvent(e['substance'] as String, DateTime.parse(e['at'] as String)),
      ];
      for (final sample in (c['samples'] as List).cast<Map<String, dynamic>>()) {
        final at = DateTime.parse(sample['at'] as String);
        (sample['levels'] as Map<String, dynamic>).forEach((track, expected) {
          final actual = genericToleranceLevel(events, byKey, track, at);
          if (!hasToleranceProfile(byKey, track)) {
            expect(currentToleranceLevel(events, byKey, track, at), closeTo(actual, 1e-12), reason: '$track uses the generic model');
          }
          expect(actual, closeTo((expected as num).toDouble(), 1e-9), reason: '$track at ${sample['at']}');
        });
      }
    });
  }

  test('2C-B does not share a track with LSD', () {
    final events = [UseEvent('lsd', DateTime(2026, 7, 1))];
    // A day later, when LSD tolerance is at its largest (the profile; it is near zero in the first hours).
    final at = DateTime(2026, 7, 2);
    expect(currentToleranceLevel(events, byKey, '2c-b', at), 0.0);
    expect(currentToleranceLevel(events, byKey, 'psychedelics', at), greaterThan(1.0));
    expect(genericToleranceLevel(events, byKey, 'psychedelics', DateTime(2026, 7, 1, 0, 1)), closeTo(1.0, 1e-3));
  });
}
