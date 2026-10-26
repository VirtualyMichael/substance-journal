import 'effect_curve.dart';
import 'reference.dart';

/// An illustrative "what does a typical dose feel like over time" shape for one route, drawn from
/// the route's published onset, come-up, peak, come-down and after-effect durations. It is the same
/// curve the journal draws for real doses, so what you see here is what you will see there.
///
/// Intensity is relative (0 to 1 against the strongest dose shown), never a measured level.
class RouteProfile {
  const RouteProfile({
    required this.step,
    required this.common,
    this.light,
    this.strong,
    required this.fastest,
    required this.slowest,
    required this.onsetEnd,
    required this.comeupEnd,
    required this.peakEnd,
    required this.offsetEnd,
    required this.end,
  });

  /// Minutes between samples.
  final double step;

  /// Samples, one per [step], for a common dose and, where the route has such bands, light and strong ones.
  final List<double> common;
  final List<double>? light;
  final List<double>? strong;

  /// The same common-dose curve built from the shortest and the longest published timings: the
  /// real timeline falls somewhere between them.
  final List<double> fastest;
  final List<double> slowest;

  /// Minutes after dosing when each phase ends (using the longest published durations), the last
  /// being the end of the lingering after-effects.
  final double onsetEnd;
  final double comeupEnd;
  final double peakEnd;
  final double offsetEnd;
  final double end;

  int get length => common.length;
}

RouteOfAdministration _withTimings(RouteOfAdministration roa, {required bool longest}) => RouteOfAdministration(
      id: roa.id,
      substanceKey: roa.substanceKey,
      route: roa.route,
      unit: roa.unit,
      doseThreshold: roa.doseThreshold,
      doseLight: roa.doseLight,
      doseCommon: roa.doseCommon,
      doseStrong: roa.doseStrong,
      doseHeavy: roa.doseHeavy,
      durations: [
        for (final d in roa.durations)
          if ((longest ? d.maxMinutes ?? d.minMinutes : d.minMinutes ?? d.maxMinutes) case final v?) DurationPhase(d.phase, v, v),
      ],
    );

double _phase(RouteOfAdministration roa, String phase) {
  final d = roa.duration(phase);
  return d?.maxMinutes ?? d?.minMinutes ?? 0;
}

/// The profile for [roa], or null when it has no timing data to draw.
RouteProfile? routeProfile(RouteOfAdministration roa) {
  final hasTiming = ['onset', 'comeup', 'peak', 'offset'].any((p) => roa.duration(p) != null);
  if (!hasTiming) return null;

  final onset = _phase(roa, 'onset');
  final comeup = _phase(roa, 'comeup');
  final peak = _phase(roa, 'peak');
  final offset = _phase(roa, 'offset');
  final core = onset + comeup + peak + offset;
  if (core <= 0) return null;
  // After-effects can last many times longer than the main experience; drawing all of it would
  // squash the part people want to read, so the tail is capped and the full length is in the text.
  final tail = _phase(roa, 'afterglow').clamp(0.0, core * 0.6).toDouble();
  final end = core + tail;
  final step = (end / 120).clamp(0.25, 60.0);
  final count = (end / step).ceil() + 1;
  final t0 = DateTime.utc(2000);

  List<double> sample(RouteOfAdministration r, double amount) {
    final curve = buildCurve(CurveIngestion(substanceKey: r.substanceKey, roaId: r.id, amount: amount, occurredAt: t0), r);
    final coreEnd = curve.endsAt.difference(t0).inMicroseconds / Duration.microsecondsPerMinute;
    final peakValue = curve.intensity(t0.add(Duration(microseconds: ((onset + comeup + peak / 2) * Duration.microsecondsPerMinute).round())));
    return [
      for (var i = 0; i < count; i++)
        () {
          final m = i * step;
          final at = t0.add(Duration(microseconds: (m * Duration.microsecondsPerMinute).round()));
          final v = curve.intensity(at);
          if (tail <= 0) return v;
          // The come-down lands on the lingering after-effects rather than dropping to nothing.
          final offsetStart = onset + comeup + peak;
          if (m <= coreEnd) return m > offsetStart && offset > 0 ? v + 0.15 * peakValue * ((m - offsetStart) / offset).clamp(0.0, 1.0) : v;
          // Lingering after-effects: a faint fading tail, a fraction of the peak.
          return (0.15 * peakValue * (1 - (m - coreEnd) / tail)).clamp(0.0, 1.0);
        }(),
    ];
  }

  final commonAmount = roa.doseCommon?.min ?? 1.0;
  final lightAmount = roa.doseLight?.min;
  final strongAmount = roa.doseStrong?.min;
  var common = sample(roa, commonAmount);
  var light = lightAmount != null && roa.doseCommon != null && lightAmount != commonAmount ? sample(roa, lightAmount) : null;
  var strong = strongAmount != null && roa.doseCommon != null && strongAmount != commonAmount ? sample(roa, strongAmount) : null;
  var fastest = sample(_withTimings(roa, longest: false), commonAmount);
  var slowest = sample(_withTimings(roa, longest: true), commonAmount);
  // The fastest timing can be shorter than the sampled window; pad with zeros so lists line up.
  List<double> fit(List<double> l) => l.length == count ? l : [...l, for (var i = l.length; i < count; i++) 0.0];
  common = fit(common);
  fastest = fit(fastest);
  slowest = fit(slowest);

  var top = 0.0;
  for (final l in [common, ?light, ?strong, fastest, slowest]) {
    for (final v in l) {
      if (v > top) top = v;
    }
  }
  if (top <= 0) return null;
  List<double> norm(List<double> l) => [for (final v in l) v / top];

  return RouteProfile(
    step: step,
    common: norm(common),
    light: light == null ? null : norm(fit(light)),
    strong: strong == null ? null : norm(fit(strong)),
    fastest: norm(fastest),
    slowest: norm(slowest),
    onsetEnd: onset,
    comeupEnd: onset + comeup,
    peakEnd: onset + comeup + peak,
    offsetEnd: core,
    end: end,
  );
}
