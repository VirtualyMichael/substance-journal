import 'dart:math';

import 'reference.dart';

/// One logged use, reduced to what the tolerance model needs. [weight] is the dose's size against a
/// common dose for its route (1.0 = a common dose, or when the dose is unknown).
class UseEvent {
  const UseEvent(this.substanceKey, this.at, {this.weight = 1.0});
  final String substanceKey;
  final DateTime at;
  final double weight;
}

const double _defaultHalfLifeDays = 3.0;

/// Doses of one track closer together than this are one session for tolerance.
const Duration toleranceClusterGap = Duration(hours: 6);

/// The most one session can add, in common-dose units: redosing has diminishing returns.
const double maxSessionContribution = 3.0;

/// Substances sharing a tolerance group pool into one track; others get their own.
String toleranceTrackKey(Substance s) => s.toleranceGroup ?? s.key;

/// Decay half-life in days: the published "half tolerance" time when present,
/// otherwise the "time to zero" estimate treated as ~4 half-lives.
double halfLifeDays(Substance s) {
  final half = s.toleranceHalfDays;
  if (half != null && half > 0) return max(half, 0.25);
  final zero = s.toleranceZeroDays;
  if (zero != null && zero > 0) return max(zero / 4.0, 0.25);
  return _defaultHalfLifeDays;
}

/// The events of one track up to [at], oldest first, each with its substance's half-life.
List<(UseEvent, double)> _trackEvents(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at) {
  final out = <(UseEvent, double)>[];
  for (final e in events) {
    final s = byKey[e.substanceKey];
    if (s == null || !s.hasTolerance || toleranceTrackKey(s) != trackKey) continue;
    if (e.at.isAfter(at)) continue;
    out.add((e, halfLifeDays(s)));
  }
  out.sort((a, b) => a.$1.at.compareTo(b.$1.at));
  return out;
}

/// Pooled tolerance score for [trackKey] at [at].
///
/// Doses less than [toleranceClusterGap] apart form one session. A session adds the square root of
/// its summed dose weights (one common dose = 1, four = 2), at most [maxSessionContribution], and
/// that halves every half-life from the session's first dose. So redosing raises tolerance with
/// diminishing returns instead of counting every bowl or drink as a full new use. Doses spaced
/// further apart than the gap each count fully, as before.
double currentToleranceLevel(
  List<UseEvent> events,
  Map<String, Substance> substancesByKey,
  String trackKey,
  DateTime at,
) {
  final mine = _trackEvents(events, substancesByKey, trackKey, at);
  var score = 0.0;
  var i = 0;
  while (i < mine.length) {
    final start = mine[i].$1.at;
    var last = start;
    var weight = 0.0;
    var halfLifeWeighted = 0.0;
    while (i < mine.length && mine[i].$1.at.difference(last) < toleranceClusterGap) {
      final w = max(mine[i].$1.weight, 0.0);
      weight += w;
      halfLifeWeighted += w * mine[i].$2;
      last = mine[i].$1.at;
      i++;
    }
    if (weight <= 0) continue;
    final halfLife = halfLifeWeighted / weight;
    final elapsedDays = at.difference(start).inMicroseconds / Duration.microsecondsPerDay;
    score += min(sqrt(weight), maxSessionContribution) * pow(2, -elapsedDays / halfLife);
  }
  return score;
}

/// The score for [trackKey] at every [step] from [from] to [to] (inclusive).
List<(DateTime, double)> toleranceTimeline(
  List<UseEvent> events,
  Map<String, Substance> byKey,
  String trackKey,
  DateTime from,
  DateTime to, {
  Duration step = const Duration(hours: 6),
}) {
  final out = <(DateTime, double)>[];
  var t = from;
  while (!t.isAfter(to)) {
    out.add((t, currentToleranceLevel(events, byKey, trackKey, t)));
    t = t.add(step);
  }
  if (out.isEmpty || out.last.$1 != to) out.add((to, currentToleranceLevel(events, byKey, trackKey, to)));
  return out;
}

/// When the score falls to [target] if nothing more is taken after [at], or null if it is already
/// there (or not within [maxDays]). Found by bisection: with no new use the score only falls.
DateTime? timeToLevel(
  List<UseEvent> events,
  Map<String, Substance> byKey,
  String trackKey,
  DateTime at,
  double target, {
  int maxDays = 730,
}) {
  final past = [for (final e in events) if (!e.at.isAfter(at)) e];
  double level(DateTime t) => currentToleranceLevel(past, byKey, trackKey, t);
  if (level(at) <= target) return null;
  var lo = 0.0;
  var hi = 1.0;
  while (level(at.add(Duration(minutes: (hi * 1440).round()))) > target) {
    lo = hi;
    hi *= 2;
    if (hi > maxDays) return null;
  }
  for (var n = 0; n < 24; n++) {
    final mid = (lo + hi) / 2;
    if (level(at.add(Duration(minutes: (mid * 1440).round()))) > target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return at.add(Duration(minutes: (hi * 1440).round()));
}

/// When the score is down to [fraction] of what it is at [at] (0.5 for half), with no further use.
DateTime? timeToFraction(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at, double fraction) {
  final now = currentToleranceLevel(events, byKey, trackKey, at);
  if (now <= 0) return null;
  return timeToLevel(events, byKey, trackKey, at, now * fraction);
}

/// How much one session moved the score: just before [start] and at [end] (its last dose).
class SessionGain {
  const SessionGain(this.before, this.after);
  final double before;
  final double after;
  double get added => after - before;

  /// The rise as a percent of what it was, or null when it started from (almost) nothing.
  double? get percent => before < 0.05 ? null : (after - before) / before * 100;
}

SessionGain sessionGain(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime start, DateTime end) {
  final before = currentToleranceLevel([for (final e in events) if (e.at.isBefore(start)) e], byKey, trackKey, start);
  final after = currentToleranceLevel(events, byKey, trackKey, end);
  return SessionGain(before, after);
}
