import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

RouteOfAdministration roa({List<DurationPhase>? durations, bool bands = true}) => RouteOfAdministration(
      id: 'x:oral',
      substanceKey: 'x',
      route: 'oral',
      unit: 'mg',
      doseLight: bands ? const DoseRange(5, 10) : null,
      doseCommon: bands ? const DoseRange(10, 20) : null,
      doseStrong: bands ? const DoseRange(20, 40) : null,
      durations: durations ??
          const [
            DurationPhase('onset', 20, 40),
            DurationPhase('comeup', 30, 60),
            DurationPhase('peak', 60, 120),
            DurationPhase('offset', 60, 120),
            DurationPhase('afterglow', 60, 240),
          ],
    );

void main() {
  test('rises from nothing, peaks, falls away, and the phase marks add up from the longest timings', () {
    final p = routeProfile(roa())!;
    expect(p.common.first, 0);
    expect(p.common.reduce((a, b) => a > b ? a : b), greaterThan(0));
    expect(p.onsetEnd, 40);
    expect(p.comeupEnd, 100);
    expect(p.peakEnd, 220);
    expect(p.offsetEnd, 340);
    expect(p.end, 544); // plus the after-effects, drawn at most 60% of the main experience (204 of 240 minutes)
    expect(p.length, p.fastest.length);
    expect(p.length, p.slowest.length);
    // Peak plateau sits in the middle of the peak phase, not at the start.
    final atPeak = p.common[((p.comeupEnd + 30) / p.step).round()];
    final atOnset = p.common[(p.onsetEnd / 2 / p.step).round()];
    expect(atPeak, greaterThan(atOnset));
  });

  test('stronger doses draw taller than common, lighter ones shorter, all within 0 to 1', () {
    final p = routeProfile(roa())!;
    double top(List<double> l) => l.reduce((a, b) => a > b ? a : b);
    expect(top(p.strong!), 1.0);
    expect(top(p.light!), lessThan(top(p.common)));
    expect(top(p.common), lessThan(top(p.strong!)));
    for (final l in [p.common, p.light!, p.strong!, p.fastest, p.slowest]) {
      expect(l.every((v) => v >= 0 && v <= 1.0000001), isTrue);
    }
  });

  test('the fastest timing finishes sooner than the slowest', () {
    final p = routeProfile(roa())!;
    int lastAbove(List<double> l) => l.lastIndexWhere((v) => v > 0.05);
    expect(lastAbove(p.fastest), lessThan(lastAbove(p.slowest)));
  });

  test('no timings means nothing to draw, and no dose bands means one curve', () {
    expect(routeProfile(roa(durations: const [])), isNull);
    final p = routeProfile(roa(bands: false))!;
    expect(p.light, isNull);
    expect(p.strong, isNull);
  });
}
