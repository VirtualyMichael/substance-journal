import 'dart:math';

import 'reference.dart';
import 'tolerance_profile.dart';

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

/// What every track model answers: the score at a moment, counting only doses up to [upTo].
abstract class _Model {
  double levelAt(DateTime t, {DateTime? upTo});

  /// How long after the last dose the score can still be rising (zero for the generic model,
  /// whose score is largest the moment a dose is taken).
  Duration get lookahead;
}

/// A track's sessions, built once from the events and then read at any time.
class _TrackModel implements _Model {
  _TrackModel(this.sessions);
  final List<_Session> sessions;

  @override
  Duration get lookahead => Duration.zero;

  /// The score at [t], counting only doses up to [upTo] (default: up to [t]).
  @override
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

/// A track whose substances have a published tolerance profile (see tolerance_profile.dart). Its
/// score is the estimated loss of effect for a same-size dose, scaled onto the generic score's
/// 0 to [toleranceCeiling] range so words and charts elsewhere keep working: 1.5 ("High") is a
/// 50% weaker effect.
class _ProfileModel implements _Model {
  _ProfileModel(this.doses, this.uncounted);
  final List<ProfileDose> doses;

  /// Substances in this track that were used but have no published cross-tolerance figure, so the
  /// estimate leaves them out.
  final Set<String> uncounted;

  @override
  Duration get lookahead {
    var hours = 0.0;
    for (final d in doses) {
      for (final band in ToleranceBand.values) {
        hours = max(hours, d.profile.peakHours.pick(band));
      }
    }
    return Duration(minutes: (hours * 60).ceil());
  }

  EffectLoss lossAt(DateTime t, {DateTime? upTo}) => EffectLoss(
        combinedLoss(doses, t, ToleranceBand.expected, upTo: upTo),
        combinedLoss(doses, t, ToleranceBand.low, upTo: upTo),
        combinedLoss(doses, t, ToleranceBand.high, upTo: upTo),
      );

  @override
  double levelAt(DateTime t, {DateTime? upTo}) => combinedLoss(doses, t, ToleranceBand.expected, upTo: upTo) * toleranceCeiling;
}

// The profiles that apply to each track, worked out once per catalogue.
final _trackProfiles = Expando<Map<String, List<(String, ToleranceProfile)>>>('trackProfiles');

List<(String, ToleranceProfile)> _profilesFor(Map<String, Substance> byKey, String trackKey) {
  final all = _trackProfiles[byKey] ??= () {
    final map = <String, List<(String, ToleranceProfile)>>{};
    for (final s in byKey.values) {
      final p = s.toleranceProfile;
      if (p == null || !s.hasTolerance) continue;
      map.putIfAbsent(toleranceTrackKey(s), () => []).add((s.key, p));
    }
    return map;
  }();
  return all[trackKey] ?? const [];
}

_Model _buildAny(List<UseEvent> events, Map<String, Substance> byKey, String trackKey) {
  final profiles = _profilesFor(byKey, trackKey);
  if (profiles.isEmpty) return _buildModel(events, byKey, trackKey);
  final doses = <ProfileDose>[];
  final uncounted = <String>{};
  for (final e in events) {
    final s = byKey[e.substanceKey];
    if (s == null || !s.hasTolerance || toleranceTrackKey(s) != trackKey) continue;
    final own = s.toleranceProfile;
    if (own != null) {
      doses.add(ProfileDose(e.at, max(e.weight, 0.0), own, 1.0));
      continue;
    }
    // Another substance of the track counts only where a profile cites cross-tolerance with it.
    (ToleranceProfile, double)? cross;
    for (final (_, p) in profiles) {
      final c = p.crossWith(e.substanceKey);
      if (c != null && (cross == null || c.factor > cross.$2)) cross = (p, c.factor);
    }
    if (cross == null) {
      uncounted.add(s.name);
    } else {
      doses.add(ProfileDose(e.at, max(e.weight, 0.0), cross.$1, cross.$2));
    }
  }
  doses.sort((a, b) => a.at.compareTo(b.at));
  return _ProfileModel(doses, uncounted);
}

// Screens ask for the same events many times (a chart, its markers, the readout), so each events
// list keeps its models until it is garbage collected.
final _models = Expando<Map<String, (Map<String, Substance>, _Model)>>('toleranceModels');

_Model _model(List<UseEvent> events, Map<String, Substance> byKey, String trackKey) {
  final perTrack = _models[events] ??= {};
  final cached = perTrack[trackKey];
  if (cached != null && identical(cached.$1, byKey)) return cached.$2;
  final built = _buildAny(events, byKey, trackKey);
  perTrack[trackKey] = (byKey, built);
  return built;
}

/// Pooled tolerance score for [trackKey] at [at].
///
/// Generic model (substances without a tolerance profile): doses less than [toleranceClusterGap]
/// apart form one session. A session adds the square root of its summed dose weights (one common
/// dose = 1, four = 2, at most [maxSessionContribution]), scaled by the room left under
/// [toleranceCeiling] when it started, and that halves every half-life from the session's first
/// dose. So redosing has diminishing returns and steady use levels off instead of growing without
/// limit. Well-spaced single doses on no prior tolerance each count fully.
///
/// Tracks with a tolerance profile (LSD and psilocybin mushrooms, pooled as "psychedelics") use the
/// profile instead: the score is the estimated loss of effect times [toleranceCeiling]. See
/// [effectLossAt] for the loss itself with its uncertainty band.
double currentToleranceLevel(
  List<UseEvent> events,
  Map<String, Substance> substancesByKey,
  String trackKey,
  DateTime at,
) =>
    _model(events, substancesByKey, trackKey).levelAt(at);

/// The generic score, ignoring any tolerance profile. Kept so the port can still be checked against
/// the Python reference implementation (scripts/export_golden.py), which has no profiles.
double genericToleranceLevel(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at) =>
    _buildModel(events, byKey, trackKey).levelAt(at);

/// True when [trackKey] is modelled from a published tolerance profile rather than the generic score.
bool hasToleranceProfile(Map<String, Substance> byKey, String trackKey) => _profilesFor(byKey, trackKey).isNotEmpty;

/// The profile that describes [trackKey] (the first substance with one, LSD before mushrooms by
/// catalogue order), or null for generic tracks.
ToleranceProfile? trackProfile(Map<String, Substance> byKey, String trackKey, {String? preferSubstance}) {
  final profiles = _profilesFor(byKey, trackKey);
  for (final (key, p) in profiles) {
    if (key == preferSubstance) return p;
  }
  return profiles.firstOrNull?.$2;
}

/// Estimated loss of effect for a same-size dose at [at], with its band, from doses up to [upTo]
/// (default: up to [at]). [EffectLoss.none] for generic tracks.
EffectLoss effectLossAt(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at, {DateTime? upTo}) {
  final m = _model(events, byKey, trackKey);
  return m is _ProfileModel ? m.lossAt(at, upTo: upTo) : EffectLoss.none;
}

/// [effectLossAt] at every [step] from [from] to [to] (inclusive).
List<(DateTime, EffectLoss)> effectLossTimeline(
  List<UseEvent> events,
  Map<String, Substance> byKey,
  String trackKey,
  DateTime from,
  DateTime to, {
  Duration step = const Duration(hours: 3),
}) {
  final m = _model(events, byKey, trackKey);
  if (m is! _ProfileModel) return const [];
  final out = <(DateTime, EffectLoss)>[];
  var t = from;
  while (!t.isAfter(to)) {
    out.add((t, m.lossAt(t)));
    t = t.add(step);
  }
  if (out.isEmpty || out.last.$1 != to) out.add((to, m.lossAt(to)));
  return out;
}

/// Names of substances used in [trackKey] that the profile estimate leaves out because no
/// published cross-tolerance figure covers them.
Set<String> uncountedInProfile(List<UseEvent> events, Map<String, Substance> byKey, String trackKey) {
  final m = _model(events, byKey, trackKey);
  return m is _ProfileModel ? m.uncounted : const {};
}

/// A loss of effect below this counts as back to baseline: the same line as the generic score's
/// baseline (0.1 of 3).
const double baselineEffectLoss = 0.1 / toleranceCeiling;

/// When the estimated loss of effect for [band] is back under [threshold] for good if nothing more
/// is taken after [at], or null if it already is (or not within [maxDays]). Scans hour by hour.
DateTime? effectRecoveredAt(
  List<UseEvent> events,
  Map<String, Substance> byKey,
  String trackKey,
  DateTime at, {
  ToleranceBand band = ToleranceBand.expected,
  double threshold = baselineEffectLoss,
  int maxDays = 30,
}) {
  final m = _model(events, byKey, trackKey);
  if (m is! _ProfileModel) return null;
  DateTime? lastAbove;
  for (var hour = 0; hour <= maxDays * 24; hour++) {
    final t = at.add(Duration(hours: hour));
    if (combinedLoss(m.doses, t, band, upTo: at) >= threshold) lastAbove = t;
  }
  return lastAbove?.add(const Duration(hours: 1));
}

/// The highest score reached from [at] onwards if nothing more is taken after [at], and when.
/// For the generic model that is the score at [at]; a profile's tolerance keeps rising for up to a
/// day after a dose.
(DateTime, double) projectedPeak(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at) =>
    _peakAhead(_model(events, byKey, trackKey), at);

(DateTime, double) _peakAhead(_Model model, DateTime at) {
  var best = (at, model.levelAt(at, upTo: at));
  final ahead = model.lookahead;
  if (ahead <= Duration.zero) return best;
  const step = Duration(minutes: 30);
  for (var t = at.add(step); !t.isAfter(at.add(ahead)); t = t.add(step)) {
    final v = model.levelAt(t, upTo: at);
    if (v > best.$2 + 1e-12) best = (t, v);
  }
  return best;
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
  // With a profile the score can still rise for a while after the last dose, so the search for when
  // it falls starts from its peak.
  final (peakAt, peak) = _peakAhead(model, at);
  double level(double days) => model.levelAt(peakAt.add(Duration(minutes: (days * 1440).round())), upTo: at);
  if (peak <= target) return null;
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
  return peakAt.add(Duration(minutes: (hi * 1440).round()));
}

/// When the score is down to [fraction] of what it is at [at] (0.5 for half), with no further use.
/// With a tolerance profile the reference is the peak still to come (tolerance from a dose taken
/// a few hours ago has not built up yet).
DateTime? timeToFraction(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime at, double fraction) {
  final (_, peak) = projectedPeak(events, byKey, trackKey, at);
  if (peak <= 0) return null;
  return timeToLevel(events, byKey, trackKey, at, peak * fraction);
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

/// For a profile track "after" is the peak the session leads to (about a day later), since its
/// tolerance builds after the doses rather than at them.
SessionGain sessionGain(List<UseEvent> events, Map<String, Substance> byKey, String trackKey, DateTime start, DateTime end) {
  final model = _model(events, byKey, trackKey);
  final before = model.levelAt(start, upTo: start.subtract(const Duration(microseconds: 1)));
  return SessionGain(before, _peakAhead(model, end).$2);
}
