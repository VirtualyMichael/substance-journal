import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

// Pins the published LSD tolerance figures (Buchborn et al. 2016 reviewing Isbell 1956, Isbell 1961,
// Wolbach 1962, Cholden 1955 and others) as the profile in substances.json encodes them.
void main() {
  final audited = parseSubstances(File('../../assets/data/substances.json').readAsStringSync());
  final extra = parseSubstances(File('../../assets/data/substances_extra.json').readAsStringSync());
  final taken = {for (final s in audited) s.key};
  final byKey = {for (final s in [...audited, ...extra.where((s) => !taken.contains(s.key))]) s.key: s};
  final t0 = DateTime(2026, 7, 1, 20);
  // 100 ug against the 75 ug start of the common band, as the app weighs doses.
  const w100 = 100 / 75;
  const track = 'psychedelics';
  DateTime h(double hours) => t0.add(Duration(minutes: (hours * 60).round()));
  EffectLoss loss(List<UseEvent> e, double hours) => effectLossAt(e, byKey, track, h(hours));

  group('the profile in the reference data', () {
    test('LSD and psilocybin mushrooms have one; other substances keep the generic model', () {
      final lsd = byKey['lsd']!.toleranceProfile!;
      expect(byKey['psilocybin_mushrooms']!.toleranceProfile, isNotNull);
      expect(byKey['cannabis']!.toleranceProfile, isNull);
      expect(hasToleranceProfile(byKey, track), isTrue);
      expect(hasToleranceProfile(byKey, toleranceTrackKey(byKey['cannabis']!)), isFalse);
      expect(lsd.singleDoseLoss.expected, 0.52);
      expect(lsd.recoveryDays.low, 3);
      expect(lsd.recoveryDays.high, 6);
      // Every measured value says where it came from; the dose scaling says it is an assumption.
      for (final v in [lsd.riseStartHours, lsd.peakHours, lsd.singleDoseLoss, lsd.maxLoss, lsd.recoveryDays]) {
        expect(v.sources, isNotEmpty);
      }
      expect(lsd.doseExponent.note, contains('assumption'));
      expect(lsd.allSources.any((s) => s.contains('Buchborn')), isTrue);
    });

    test('a substance without a profile parses as before', () {
      final s = parseSubstances('[{"key":"x","name":"X","has_tolerance":true,"roas":[]}]').single;
      expect(s.toleranceProfile, isNull);
    });
  });

  group('one 100 ug dose of LSD', () {
    final single = [UseEvent('lsd', t0, weight: w100)];

    test('little tolerance for the first hours, about half the effect lost a day later', () {
      expect(loss(single, 1).expected, 0);
      expect(loss(single, 6).expected, 0);
      expect(loss(single, 6).high, greaterThan(0)); // the earlier-rise reading
      expect(loss(single, 24).expected, closeTo(0.52, 0.005));
      expect(currentToleranceLevel(single, byKey, track, h(24)), closeTo(0.52 * toleranceCeiling, 0.02));
    });

    test('a repeat dose the next day is largely blunted; later ones less so', () {
      final next = [for (final d in [1, 2, 3, 5, 7, 14]) loss(single, 24.0 * d).expected];
      expect(next[0], greaterThanOrEqualTo(0.5));
      for (var i = 1; i < next.length; i++) {
        expect(next[i], lessThanOrEqualTo(next[i - 1]));
      }
      expect(next[3], 0); // 5 days
      expect(loss(single, 24.0 * 7).high, 0); // gone within the 6-day upper end
    });

    test('back near baseline within the cited 3 to 6 days', () {
      final baseline = timeToLevel(single, byKey, track, t0, baselineLevel)!;
      expect(baseline.difference(t0).inHours / 24, inInclusiveRange(3, 6));
    });

    test('the band always brackets the estimate', () {
      for (final (_, l) in effectLossTimeline(single, byKey, track, t0, h(24.0 * 8))) {
        expect(l.low, lessThanOrEqualTo(l.expected + 1e-12));
        expect(l.high, greaterThanOrEqualTo(l.expected - 1e-12));
      }
    });

    test('the peak is still ahead right after the dose', () {
      final (at, level) = projectedPeak(single, byKey, track, t0);
      expect(at.difference(t0).inHours, inInclusiveRange(23, 24));
      expect(level, greaterThan(1.5));
      expect(timeToFraction(single, byKey, track, t0, 0.5)!.isAfter(at), isTrue);
    });

    test('the route does not matter: only time and dose size are used', () {
      expect(loss([UseEvent('lsd', t0, weight: w100)], 24).expected, loss(single, 24).expected);
    });
  });

  test('daily dosing saturates near the measured 78-88%', () {
    final four = [for (var d = 0; d < 4; d++) UseEvent('lsd', t0.add(Duration(days: d)), weight: w100)];
    final beforeFifth = loss(four, 96).expected;
    expect(beforeFifth, inInclusiveRange(0.75, 0.88));
    final fortnight = [for (var d = 0; d < 14; d++) UseEvent('lsd', t0.add(Duration(days: d)), weight: w100)];
    for (var d = 1; d <= 14; d++) {
      expect(loss(fortnight, 24.0 * d).high, lessThanOrEqualTo(0.88 + 1e-9));
    }
    // Stopping after two weeks: gone within the upper end of 6 days after the last dose.
    expect(loss(fortnight, 24.0 * (13 + 6) + 1).high, 0);
  });

  test('a smaller dose leaves less tolerance; the band spans the dose-scaling assumption', () {
    final small = loss([UseEvent('lsd', t0, weight: 0.25)], 24);
    expect(small.expected, closeTo(0.52 * 0.5, 0.005));
    expect(small.low, closeTo(0.52 * 0.25, 0.005));
    expect(small.high, closeTo(0.52, 0.005));
    // Above a common dose the studies give no reason to add more.
    expect(loss([UseEvent('lsd', t0, weight: 2)], 24).expected, closeTo(0.52, 0.005));
  });

  test('cross-tolerance with psilocybin mushrooms is strong and symmetric', () {
    final lsdFirst = [UseEvent('lsd', t0, weight: w100), UseEvent('psilocybin_mushrooms', h(48), weight: 2)];
    final mushroomsFirst = [UseEvent('psilocybin_mushrooms', t0, weight: 2), UseEvent('lsd', h(48), weight: w100)];
    expect(loss([lsdFirst.first], 24).expected, closeTo(loss([mushroomsFirst.first], 24).expected, 1e-9));
    expect(loss([mushroomsFirst.first], 24).expected, greaterThanOrEqualTo(0.5));
    expect(loss(lsdFirst, 72).expected, closeTo(loss(mushroomsFirst, 72).expected, 1e-9));
    expect(byKey['lsd']!.toleranceProfile!.crossWith('psilocybin_mushrooms')!.sources, isNotEmpty);
    expect(byKey['psilocybin_mushrooms']!.toleranceProfile!.crossWith('lsd'), isNotNull);
  });

  test('mescaline counts through the published cross-tolerance; group members without a figure are named, not counted', () {
    final mescaline = [UseEvent('mescaline', t0)];
    expect(loss(mescaline, 24).expected, greaterThan(0.4));
    final other = byKey.values.firstWhere((s) =>
        s.hasTolerance && toleranceTrackKey(s) == track && s.toleranceProfile == null && byKey['lsd']!.toleranceProfile!.crossWith(s.key) == null);
    final events = [UseEvent(other.key, t0)];
    expect(loss(events, 24).expected, 0);
    expect(uncountedInProfile(events, byKey, track), contains(other.name));
  });

  test('unrelated substances do not interact', () {
    final events = [UseEvent('lsd', t0, weight: w100), for (var d = 0; d < 5; d++) UseEvent('cannabis', t0.add(Duration(days: d)))];
    final cannabisTrack = toleranceTrackKey(byKey['cannabis']!);
    expect(currentToleranceLevel(events, byKey, cannabisTrack, h(96)),
        closeTo(currentToleranceLevel([for (final e in events) if (e.substanceKey == 'cannabis') e], byKey, cannabisTrack, h(96)), 1e-12));
    expect(loss(events, 24).expected, closeTo(loss([events.first], 24).expected, 1e-12));
    expect(currentToleranceLevel([UseEvent('lsd', t0)], byKey, '2c-b', h(24)), 0);
  });

  test('the report carries the effect loss for profiled tracks only', () {
    final tracks = toleranceTracks(
      events: [UseEvent('lsd', t0, weight: w100), UseEvent('cannabis', t0)],
      byKey: byKey,
      now: h(24),
    );
    final psy = tracks.firstWhere((t) => t.key == track);
    expect(psy.effectLoss!.percent, 52);
    expect(tracks.firstWhere((t) => t.key != track).effectLoss, isNull);
    // Right after a dose the level is still low, yet a return-to-baseline date is given.
    final early = toleranceTracks(events: [UseEvent('lsd', t0, weight: w100)], byKey: byKey, now: h(1));
    expect(early.single.baselineAt, isNotNull);
  });
}
