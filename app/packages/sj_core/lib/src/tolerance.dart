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

/// The score tolerance can approach but never pass. Receptor adaptation levels off with steady use
/// rather than growing without limit, so each session adds in proportion to the room left.
const double toleranceCeiling = 3.0;

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

/// One session of a track: its doses (time, running total of weights) and how much room was left
/// under the ceiling when it started.
class _Session {
  _Session(this.start);
  final DateTime start;
  final List<(DateTime, double)> doses = [];
  double weight = 0;
  double halfLifeWeighted = 0;
  double headroom = 1;

  double get halfLife => weight <= 0 ? _defaultHalfLifeDays : halfLifeWeighted / weight;
}

double _days(Duration d) => d.inMicroseconds / Duration.microsecondsPerDay;

/// A track's sessions, built once from the events and then read at any time.
class _TrackModel {
  _TrackModel(this.sessions);
  final List<_Session> sessions;

  /// The score at [t], counting only doses up to [upTo] (default: up to [t]).
  double levelAt(DateTime t, {DateTime? upTo}) {
    final limit = upTo == null || upTo.isAfter(t) ? t : upTo;
    var score = 0.0;
    for (final s in sessions) {
      if (s.start.isAfter(limit)) break;
      var w = 0.0;
      for (final (at, cumulative) in s.doses) {
        if (at.isAfter(limit)) break;
        w = cumulative;
      }
      if (w <= 0) continue;
      score += min(sqrt(w), maxSessionContribution) * s.headroom * pow(2, -_days(t.difference(s.start)) / s.halfLife);
    }
    return score;
  }
}

_TrackModel _buildModel(List<UseEvent> events, Map<String, Substance> byKey, String trackKey) {
  final mine = <(UseEvent, double)>[];
  for (final e in events) {
    final s = byKey[e.substanceKey];
    if (s == null || !s.hasTolerance || toleranceTrackKey(s) != trackKey) continue;
    mine.add((e, halfLifeDays(s)));
  }
  mine.sort((a, b) => a.$1.at.compareTo(b.$1.at));

  final sessions = <_Session>[];
  DateTime? last;
  for (final (e, halfLife) in mine) {
    final w = max(e.weight, 0.0);
    if (last == null || e.at.difference(last) >= toleranceClusterGap) sessions.add(_Session(e.at));
    final s = sessions.last;
    s.weight += w;
    s.halfLifeWeighted += w * halfLife;
    s.doses.add((e.at, s.weight));
    last = e.at;
  }

  // Room left under the ceiling at the start of each session, from the full earlier sessions.
  for (var i = 0; i < sessions.length; i++) {
    var before = 0.0;
    for (var j = 0; j < i; j++) {
      final p = sessions[j];
      if (p.weight <= 0) continue;
      before += min(sqrt(p.weight), maxSessionContribution) * p.headroom * pow(2, -_days(sessions[i].start.difference(p.start)) / p.halfLife);
    }
    sessions[i].headroom = max(0.0, 1 - before / toleranceCeiling);
  }
  return _TrackModel(sessions);
}

// Screens ask for the same events many times (a chart, its markers, the readout), so each events
// list keeps its models until it is garbage collected.
final _models = Expando<Map<String, (Map<String, Substance>, _TrackModel)>>('toleranceModels');

_TrackModel _model(List<UseEvent> events, Map<String, Substance> byKey, String trackKey) {
  final perTrack = _models[events] ??= {};
  final cached = perTrack[trackKey];
  if (cached != null && identical(cached.$1, byKey)) return cached.$2;
  final built = _buildModel(events, byKey, trackKey);
  perTrack[trackKey] = (byKey, built);
  return built;
}

/// Pooled tolerance score for [trackKey] at [at].
///
/// Doses less than [toleranceClusterGap] apart form one session. A session adds the square root of
/// its summed dose weights (one common dose = 1, four = 2, at most [maxSessionContribution]), scaled
/// by the room left under [toleranceCeiling] when it started, and that halves every half-life from
/// the session's first dose. So redosing has diminishing returns and steady use levels off instead
/// of growing without limit. Well-spaced single doses on no prior tolerance each count fully.
double currentToleranceLevel(
  List<UseEvent> events,
  Map<String, Substance> substancesByKey,
  String trackKey,
  DateTime at,
) =>
    _model(events, substancesByKey, trackKey).levelAt(at);

/// The score for [trackKey] at every [step] from [from] to [to] (inclusive).
List<(DateTime, double)> toleranceTimeline(
  List<UseEvent> events,
  Map<String, Substance> byKey,
  String trackKey,
  DateTime from,
  DateTime to, {
  Duration step = const Duration(hours: 6),
}) {
  final model = _model(events, byKey, trackKey);
  final out = <(DateTime, double)>[];
  var t = from;
  while (!t.isAfter(to)) {
    out.add((t, model.levelAt(t)));
    t = t.add(step);
  }
  if (out.isEmpty || out.last.$1 != to) out.add((to, model.levelAt(to)));
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
  final model = _model(events, byKey, trackKey);
  double level(double days) => model.levelAt(at.add(Duration(minutes: (days * 1440).round())), upTo: at);
  if (level(0) <= target) return null;
  var lo = 0.0;
  var hi = 1.0;
  while (level(hi) > target) {
    lo = hi;
    hi *= 2;
    if (hi > maxDays) return null;
  }
  for (var n = 0; n < 24; n++) {
    final mid = (lo + hi) / 2;
    if (level(mid) > target) {
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
  final model = _model(events, byKey, trackKey);
  final before = model.levelAt(start, upTo: start.subtract(const Duration(microseconds: 1)));
  return SessionGain(before, model.levelAt(end));
}
