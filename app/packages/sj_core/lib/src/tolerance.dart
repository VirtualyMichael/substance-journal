import 'dart:math';

import 'reference.dart';

/// One logged use, reduced to what the tolerance model needs.
class UseEvent {
  const UseEvent(this.substanceKey, this.at);
  final String substanceKey;
  final DateTime at;
}

const double _defaultHalfLifeDays = 3.0;

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

/// Pooled tolerance score for [trackKey] at [at]: each past use adds 2^(-elapsed/halfLife).
double currentToleranceLevel(
  List<UseEvent> events,
  Map<String, Substance> substancesByKey,
  String trackKey,
  DateTime at,
) {
  var score = 0.0;
  for (final e in events) {
    final s = substancesByKey[e.substanceKey];
    if (s == null || !s.hasTolerance || toleranceTrackKey(s) != trackKey) continue;
    if (e.at.isAfter(at)) continue;
    final elapsedDays = at.difference(e.at).inMicroseconds / Duration.microsecondsPerDay;
    score += pow(2, -elapsedDays / halfLifeDays(s));
  }
  return score;
}
