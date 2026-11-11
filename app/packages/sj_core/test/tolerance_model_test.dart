import 'dart:io';
import 'dart:math';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final substances = parseSubstances(File('../../../data/substances.json').readAsStringSync());
  final byKey = {for (final s in substances) s.key: s};
  final cannabis = byKey['cannabis']!;
  final track = toleranceTrackKey(cannabis);
  final hl = halfLifeDays(cannabis);
  final t0 = DateTime(2026, 7, 1, 20);
  double decay(Duration d) => pow(2, -(d.inMicroseconds / Duration.microsecondsPerDay) / hl).toDouble();

  group('dose-weighted, session-clustered tolerance', () {
    test('one common dose counts 1', () {
      final level = currentToleranceLevel([UseEvent('cannabis', t0)], byKey, track, t0);
      expect(level, closeTo(1.0, 1e-9));
    });

    test('four common doses in one evening count 2, not 4', () {
      final events = [for (var n = 0; n < 4; n++) UseEvent('cannabis', t0.add(Duration(minutes: 40 * n)))];
      final at = t0.add(const Duration(minutes: 120));
      expect(currentToleranceLevel(events, byKey, track, at), closeTo(2 * decay(const Duration(minutes: 120)), 1e-9));
    });

    test('thirteen bowls in a session are capped at 3', () {
      final events = [for (var n = 0; n < 13; n++) UseEvent('cannabis', t0.add(Duration(minutes: 20 * n)))];
      final at = t0.add(const Duration(minutes: 240));
      expect(currentToleranceLevel(events, byKey, track, at), closeTo(maxSessionContribution * decay(const Duration(minutes: 240)), 1e-9));
    });

    test('a later session adds in proportion to the room left under the ceiling', () {
      final events = [UseEvent('cannabis', t0), UseEvent('cannabis', t0.add(const Duration(hours: 7)))];
      final at = t0.add(const Duration(hours: 7));
      final first = decay(const Duration(hours: 7));
      expect(currentToleranceLevel(events, byKey, track, at), closeTo(first + (1 - first / toleranceCeiling), 1e-9));
    });

    test('steady daily use levels off below the ceiling instead of growing without limit', () {
      final events = [
        for (var d = 0; d < 60; d++)
          for (var n = 0; n < 3; n++) UseEvent('cannabis', t0.add(Duration(days: d, hours: 8 * n)), weight: 2),
      ];
      final day30 = currentToleranceLevel(events, byKey, track, t0.add(const Duration(days: 30)));
      final day60 = currentToleranceLevel(events, byKey, track, t0.add(const Duration(days: 60)));
      expect(day60, lessThan(toleranceCeiling));
      expect(day60, greaterThan(1.5)); // High
      expect((day60 - day30).abs(), lessThan(0.1)); // a plateau
      // Stopping: about four weeks back to baseline with the 7-day cannabis half-life.
      final stop = t0.add(const Duration(days: 60));
      final baseline = timeToLevel(events, byKey, track, stop, baselineLevel)!;
      expect(baseline.difference(stop).inDays, inInclusiveRange(21, 40));
    });

    test('dose size scales the contribution', () {
      final half = currentToleranceLevel([UseEvent('cannabis', t0, weight: 0.5)], byKey, track, t0);
      final double_ = currentToleranceLevel([UseEvent('cannabis', t0, weight: 2)], byKey, track, t0);
      expect(half, closeTo(sqrt(0.5), 1e-9));
      expect(double_, closeTo(sqrt(2), 1e-9));
    });

    test('the level rises dose by dose during a session', () {
      final events = [for (var n = 0; n < 3; n++) UseEvent('cannabis', t0.add(Duration(minutes: 30 * n)))];
      final a = currentToleranceLevel(events, byKey, track, t0.add(const Duration(minutes: 1)));
      final b = currentToleranceLevel(events, byKey, track, t0.add(const Duration(minutes: 61)));
      expect(b, greaterThan(a));
    });
  });

  group('halving and session gains', () {
    test('half and quarter fall one and two half-lives later', () {
      final events = [UseEvent('cannabis', t0)];
      final half = timeToFraction(events, byKey, track, t0, 0.5)!;
      final quarter = timeToFraction(events, byKey, track, t0, 0.25)!;
      expect(half.difference(t0).inMinutes / 1440, closeTo(hl, 0.01));
      expect(quarter.difference(t0).inMinutes / 1440, closeTo(2 * hl, 0.01));
      expect(timeToLevel(events, byKey, track, t0, 5), isNull); // already below
    });

    test('later use is ignored when projecting from a point in time', () {
      final events = [UseEvent('cannabis', t0), UseEvent('cannabis', t0.add(const Duration(days: 1)))];
      final half = timeToFraction(events, byKey, track, t0, 0.5)!;
      expect(half.difference(t0).inMinutes / 1440, closeTo(hl, 0.01));
    });

    test('a session gain reports before, after and percent', () {
      final events = [
        UseEvent('cannabis', t0.subtract(const Duration(days: 2))),
        for (var n = 0; n < 4; n++) UseEvent('cannabis', t0.add(Duration(minutes: 30 * n))),
      ];
      final gain = sessionGain(events, byKey, track, t0, t0.add(const Duration(minutes: 90)));
      expect(gain.before, closeTo(decay(const Duration(days: 2)), 1e-9));
      expect(gain.after, greaterThan(gain.before + 1.0));
      expect(gain.percent, greaterThan(100));
      expect(sessionGain([UseEvent('cannabis', t0)], byKey, track, t0, t0).percent, isNull);
    });

    test('a timeline spans the range at the step', () {
      final line = toleranceTimeline([UseEvent('cannabis', t0)], byKey, track, t0, t0.add(const Duration(days: 1)));
      expect(line.first.$2, closeTo(1.0, 1e-9));
      expect(line, hasLength(5));
      expect(line.last.$2, lessThan(1.0));
    });
  });

  group('alcohol tolerance between days', () {
    const s = EstimateSettings();
    final loads = {DateTime(2026, 7, 1): 4.0};

    test('the score halves every tolerance half-life', () {
      final at = DateTime(2026, 7, 2);
      final half = alcoholTimeToScore(loads, at, alcoholToleranceScoreAt(loads, at, s) / 2, s)!;
      expect(half.difference(at).inMinutes / 1440, closeTo(s.toleranceHalfLifeDays, 0.01));
    });

    test('the baseline score maps to a 1.02x multiplier', () {
      expect(toleranceMultiplier(alcoholBaselineScore(s), s), closeTo(1.02, 1e-9));
    });

    test('the timeline carries score and multiplier', () {
      final line = alcoholToleranceTimeline(loads, DateTime(2026, 7, 1), DateTime(2026, 7, 3), settings: s);
      expect(line.first.$2, closeTo(4.0, 1e-9));
      expect(line.first.$3, closeTo(toleranceMultiplier(4.0, s), 1e-9));
      expect(line.last.$2, lessThan(4.0));
    });
  });
}
