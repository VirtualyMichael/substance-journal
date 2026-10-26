import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final byKey = {for (final s in parseSubstances(File('../../assets/data/substances.json').readAsStringSync())) s.key: s};
  final now = DateTime(2026, 7, 10, 12);

  test('recent use gives a track with a projected return to baseline', () {
    final tracks = toleranceTracks(events: [UseEvent('lsd', now.subtract(const Duration(days: 1)))], byKey: byKey, now: now);
    expect(tracks, hasLength(1));
    final t = tracks.single;
    expect(t.label.toLowerCase(), contains('psychedelic')); // pooled with its group
    expect(t.level, greaterThan(0.5));
    expect(t.baselineAt, isNotNull);
    expect(t.baselineAt!.isAfter(now), isTrue);
    expect(t.lastUse, now.subtract(const Duration(days: 1)));
    expect(t.projection.first.$1.isBefore(now), isTrue);
    expect(t.projection.last.$2, lessThan(t.level)); // falls over the projection
  });

  test('group members pool: LSD and psilocybin share one psychedelic track', () {
    final tracks = toleranceTracks(
      events: [UseEvent('lsd', now.subtract(const Duration(days: 2))), UseEvent('psilocybin_mushrooms', now.subtract(const Duration(days: 3)))],
      byKey: byKey,
      now: now,
    );
    expect(tracks, hasLength(1));
    expect(tracks.single.substances.length, 2);
  });

  test('old use is not a track, a baseline track has no date, and the future is ignored', () {
    expect(toleranceTracks(events: [UseEvent('lsd', now.subtract(const Duration(days: 200)))], byKey: byKey, now: now), isEmpty);
    final faded = toleranceTracks(events: [UseEvent('lsd', now.subtract(const Duration(days: 60)))], byKey: byKey, now: now);
    expect(faded.single.baselineAt, isNull);
    expect(faded.single.word, 'None');
    expect(toleranceTracks(events: [UseEvent('lsd', now.add(const Duration(days: 1)))], byKey: byKey, now: now), isEmpty);
  });

  test('strongest first, and substances without tolerance are left out', () {
    final tracks = toleranceTracks(
      events: [
        UseEvent('lsd', now.subtract(const Duration(days: 10))),
        for (var d = 1; d <= 5; d++) UseEvent('cannabis', now.subtract(Duration(days: d))),
        UseEvent('alcohol', now.subtract(const Duration(days: 1))),
      ],
      byKey: byKey,
      now: now,
    );
    expect(tracks.map((t) => t.level).toList(), orderedEquals([...tracks.map((t) => t.level)]..sort((a, b) => b.compareTo(a))));
    expect(tracks.every((t) => !t.substances.contains('Alcohol') || byKey['alcohol']!.hasTolerance), isTrue);
  });

  test('words', () {
    expect(toleranceWord(0.05), 'None');
    expect(toleranceWord(0.3), 'Low');
    expect(toleranceWord(1.0), 'Moderate');
    expect(toleranceWord(2.5), 'High');
  });
}
