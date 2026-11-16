import 'dart:math';

import 'package:sj_core/sj_core.dart';

/// What the shared tolerance model (sj_core tolerance.dart) says about one compound in the
/// abstract: one common dose at [origin], or a common dose every N days, with nobody's journal
/// involved. The compound page draws it; the numbers come from the same functions the tolerance
/// card on the experience page uses, so the two always agree.

/// The repeat schedules shown on the compound page, in days between common doses.
const List<int> toleranceRepeatDays = [1, 3, 7, 14];

/// A fixed, arbitrary moment the hypothetical doses are placed at (only differences matter).
final DateTime toleranceOrigin = DateTime.utc(2000, 1, 3, 12);

/// One point on a projection: the generic score, or a profile's loss of effect with its band.
class ProjectionPoint {
  const ProjectionPoint(this.at, this.value, {this.low, this.high});
  final DateTime at;

  /// Profile: estimated loss of effect for a same-size dose, 0 to 1. Generic: the tolerance score.
  final double value;
  final double? low;
  final double? high;
}

/// How a repeat schedule settles: what a dose meets just before it is taken, once the pattern has
/// run for [settleDays].
class ScheduleOutcome {
  const ScheduleOutcome(this.everyDays, this.beforeDose, {this.low, this.high, this.afterDose});
  final int everyDays;

  /// Profile: loss of effect (0-1) for the next dose, taken on schedule. Generic: the score then.
  final double beforeDose;
  final double? low;
  final double? high;

  /// Generic only: the score just after a dose (the top of each saw tooth).
  final double? afterDose;
}

class ToleranceProjection {
  ToleranceProjection._({
    required this.substance,
    required this.trackKey,
    required this.profile,
    required this.byKey,
  });

  /// Null when [substance] publishes no tolerance at all.
  static ToleranceProjection? of(Substance substance, Map<String, Substance> byKey) {
    if (!substance.hasTolerance) return null;
    final track = toleranceTrackKey(substance);
    ToleranceProfile? profile;
    if (hasToleranceProfile(byKey, track)) {
      // Counted by a profile only when it has one or a profile cites cross-tolerance with it;
      // otherwise the profile model would leave it out, so the generic shape is shown instead.
      final probe = [UseEvent(substance.key, toleranceOrigin)];
      if (uncountedInProfile(probe, byKey, track).isEmpty) {
        profile = substance.toleranceProfile ?? trackProfile(byKey, track, preferSubstance: substance.key);
      }
    }
    return ToleranceProjection._(substance: substance, trackKey: track, profile: profile, byKey: byKey);
  }

  final Substance substance;
  final String trackKey;
  final Map<String, Substance> byKey;

  /// The published profile behind the estimate, or null for the generic shape from a half-life.
  final ToleranceProfile? profile;

  bool get profiled => profile != null;

  /// Days for the generic score to halve (the published half-tolerance time, or a quarter of the
  /// time to zero). Meaningless for a profile, whose tolerance fades in a straight line.
  double get halfLifeDays => toleranceHalfLife(substance);

  /// Other catalog compounds that share tolerance with this one (same group).
  List<String> get groupMembers {
    final g = substance.toleranceGroup;
    if (g == null || g.isEmpty) return const [];
    return ([for (final s in byKey.values) if (s.key != substance.key && s.hasTolerance && s.toleranceGroup == g) s.name]..sort());
  }

  List<UseEvent> _events(int? everyDays, int days) => [
        if (everyDays == null)
          UseEvent(substance.key, toleranceOrigin)
        else
          for (var d = 0; d <= days; d += everyDays) UseEvent(substance.key, toleranceOrigin.add(Duration(days: d))),
      ];

  double _generic(List<UseEvent> events, DateTime at, {DateTime? upTo}) {
    final limit = upTo ?? at;
    return genericToleranceLevel([for (final e in events) if (!e.at.isAfter(limit)) e], byKey, trackKey, at);
  }

  /// The curve after one common dose ([everyDays] null) or a common dose every [everyDays] days,
  /// from a day before the first dose to [days] after it.
  List<ProjectionPoint> series({int? everyDays, required int days, Duration? step}) {
    final events = _events(everyDays, days);
    final from = toleranceOrigin.subtract(const Duration(days: 1));
    final to = toleranceOrigin.add(Duration(days: days));
    final s = step ?? Duration(hours: max(1, (days + 1) * 24 ~/ 240));
    if (profiled) {
      return [
        for (final (t, l) in effectLossTimeline(events, byKey, trackKey, from, to, step: s)) ProjectionPoint(t, l.expected, low: l.low, high: l.high),
      ];
    }
    final out = <ProjectionPoint>[];
    for (var t = from; !t.isAfter(to); t = t.add(s)) {
      out.add(ProjectionPoint(t, _generic(events, t)));
    }
    // The generic score jumps at each dose; make sure the tops are drawn, not stepped over.
    for (final e in events) {
      if (!e.at.isAfter(to)) out.add(ProjectionPoint(e.at, _generic(events, e.at)));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// After one common dose: when tolerance is largest and how large.
  (DateTime, double) get peak {
    final events = _events(null, 0);
    if (!profiled) return (toleranceOrigin, _generic(events, toleranceOrigin));
    final (at, _) = projectedPeak(events, byKey, trackKey, toleranceOrigin);
    return (at, effectLossAt(events, byKey, trackKey, at).expected);
  }

  /// The loss of effect at the peak with its band (profile only).
  EffectLoss get peakLoss {
    if (!profiled) return EffectLoss.none;
    final events = _events(null, 0);
    return effectLossAt(events, byKey, trackKey, peak.$1);
  }

  /// After one common dose: when it has halved from its peak.
  DateTime? get halfAt {
    final events = _events(null, 0);
    if (profiled) return timeToFraction(events, byKey, trackKey, toleranceOrigin, 0.5);
    return _scanDown(events, (v) => v <= peak.$2 / 2);
  }

  /// After one common dose: back to baseline (the same line the tolerance card uses).
  DateTime? baselineAt({ToleranceBand band = ToleranceBand.expected}) {
    final events = _events(null, 0);
    if (profiled) return effectRecoveredAt(events, byKey, trackKey, toleranceOrigin, band: band);
    return _scanDown(events, (v) => v < baselineLevel);
  }

  DateTime? _scanDown(List<UseEvent> events, bool Function(double) done) {
    for (var h = 1; h <= 730 * 24; h += 1) {
      final t = toleranceOrigin.add(Duration(hours: h));
      if (done(_generic(events, t))) return t;
    }
    return null;
  }

  /// How each repeat schedule settles after [settleDays] (eight weeks by default).
  List<ScheduleOutcome> schedules({int settleDays = 56}) => [
        for (final n in toleranceRepeatDays) _outcome(n, settleDays),
      ];

  ScheduleOutcome _outcome(int n, int settleDays) {
    final doses = settleDays ~/ n; // the dose after the last one in the window is the one we ask about
    final next = toleranceOrigin.add(Duration(days: doses * n));
    final events = _events(n, (doses - 1) * n);
    final before = next.subtract(const Duration(microseconds: 1));
    if (profiled) {
      final l = effectLossAt(events, byKey, trackKey, next, upTo: before);
      return ScheduleOutcome(n, l.expected, low: l.low, high: l.high);
    }
    final last = toleranceOrigin.add(Duration(days: (doses - 1) * n));
    return ScheduleOutcome(n, _generic(events, next, upTo: before), afterDose: _generic(events, last));
  }
}

/// Days for the generic score to halve: [halfLifeDays] from sj_core, under a name that does not
/// clash with the projection's getter.
double toleranceHalfLife(Substance s) => halfLifeDays(s);
