import 'dart:math';

import 'package:sj_core/sj_core.dart';

import '../ui/journal/tolerance_card.dart' show ToleranceTrend;
import 'alcohol_data.dart';
import 'database.dart';
import 'tolerance_events.dart';

/// Grams of ethanol in one standard drink (US), the unit alcohol amounts are shown in here.
const gramsPerStandardDrink = 14.0;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// An amount of something at a moment, tied to the experience it belongs to.
class AmountAt {
  const AmountAt(this.amount, this.unit, this.at, this.experienceId, {this.route});
  final double amount;
  final String unit;
  final DateTime at;
  final String experienceId;
  final String? route;
}

/// One experience's change in tolerance for one substance.
class SessionGainRow {
  const SessionGainRow({required this.experienceId, required this.start, required this.end, required this.before, required this.after, required this.alcohol, required this.settings});
  final String experienceId;
  final DateTime start;
  final DateTime end;

  /// Score before and after (for alcohol, the exposure score; see [multiplierBefore]).
  final double before;
  final double after;
  final bool alcohol;
  final EstimateSettings settings;

  double get added => after - before;
  double? get percent => before < 0.05 ? null : (after - before) / before * 100;
  double get multiplierBefore => toleranceMultiplier(before, settings);
  double get multiplierAfter => toleranceMultiplier(after, settings);
}

/// When tolerance reaches each milestone with no more use, from a moment (null: already there).
class BreakPlan {
  const BreakPlan({required this.from, this.half, this.quarter, this.low, this.baseline});
  final DateTime from;
  final DateTime? half;
  final DateTime? quarter;

  /// Down to "Low" (score 0.5). Not used for alcohol, which is shown as a multiplier.
  final DateTime? low;
  final DateTime? baseline;
}

/// Tolerance over time for one substance's track, ready to chart.
class ToleranceView {
  const ToleranceView({
    required this.trackKey,
    required this.alcohol,
    required this.points,
    required this.now,
    required this.word,
    required this.trend,
    required this.plan,
    required this.sharedWith,
    this.multiplierNow,
  });
  final String trackKey;
  final bool alcohol;

  /// (time, value): the score, or for alcohol the dose multiplier.
  final List<(DateTime, double)> points;

  /// The value now (score, or multiplier for alcohol).
  final double now;
  final String word;
  final ToleranceTrend trend;
  final BreakPlan plan;

  /// Other substances that share this track (cross-tolerance), by name.
  final List<String> sharedWith;
  final double? multiplierNow;
}

/// Everything known about one substance in one person's journal.
class SubstanceHistory {
  const SubstanceHistory({
    required this.key,
    required this.name,
    required this.doses,
    required this.mainUnit,
    required this.totalByUnit,
    required this.first,
    required this.last,
    required this.averageDose,
    required this.daysUsed,
    required this.longestBreakDays,
    required this.longestBreakFrom,
    required this.currentRunDays,
    required this.largestByRoute,
    required this.largestSession,
    required this.most24h,
    required this.highestPeak,
    required this.peakUnit,
    required this.sessionTotals,
    required this.byWeekday,
    required this.byHour,
    required this.routes,
    required this.combos,
    required this.gains,
    required this.experiences,
  });

  final String key;
  final String name;
  final int doses;

  /// The unit most doses were logged in ("std drinks" for alcohol); totals and trends use it.
  final String mainUnit;
  final Map<String, double> totalByUnit;
  final DateTime first;
  final DateTime last;
  final double? averageDose;
  final int daysUsed;
  final int longestBreakDays;
  final DateTime? longestBreakFrom;

  /// Consecutive days with use, ending today or yesterday (0 when the last use was earlier).
  final int currentRunDays;
  final Map<String, AmountAt> largestByRoute;
  final AmountAt? largestSession;
  final AmountAt? most24h;

  /// Highest estimated curve intensity (1.0 = a common dose), or for alcohol the highest BAC.
  final AmountAt? highestPeak;
  final String peakUnit;

  /// Per experience: (start, total in [mainUnit]), oldest first.
  final List<(DateTime, double)> sessionTotals;
  final List<int> byWeekday; // Monday first
  final List<int> byHour;
  final Map<String, int> routes;

  /// Other substances taken in the same experiences, by name, most first.
  final List<MapEntry<String, int>> combos;

  /// Tolerance added per experience, newest first.
  final List<SessionGainRow> gains;
  final int experiences;
}

double _amount(Ingestion i) => i.substanceKey == 'alcohol' ? (i.dose ?? 0) / gramsPerStandardDrink : (i.dose ?? 0);
String _unit(Ingestion i) => i.substanceKey == 'alcohol' ? 'std drinks' : (i.unit ?? '');

/// Alcohol's tolerance input: the CNS exposure of each drinking session, keyed by when it started
/// (the same exposure the day view uses, placed at the session's start instead of midnight).
///
/// Simulating every session is the slowest calculation in the app, and screens ask for it every
/// tick, so the last answer is kept until the drinks or settings change.
Map<DateTime, double> alcoholLoads(List<Ingestion> drinks, EstimateSettings settings) {
  // Sorted, so callers that list the same drinks in a different order share the cached answer.
  final live = [for (final d in drinks) if (!d.deleted) d]..sort((a, b) => a.time != b.time ? a.time.compareTo(b.time) : a.id.compareTo(b.id));
  final key = Object.hashAll([for (final d in live) Object.hash(d.id, d.time, d.endTime, d.dose, d.detailsJson)]);
  final cached = _loadsCache;
  if (cached != null && cached.$1 == key && identical(cached.$2, settings)) return cached.$3;
  final converted = [for (final d in live) alcoholDrinkFrom(d, settings)];
  final loads = <DateTime, double>{};
  if (converted.isNotEmpty) {
    for (final session in groupIntoSessions(converted, settings)) {
      final e = sessionExposure(session, settings);
      loads[e.start] = (loads[e.start] ?? 0) + e.exposureBacHours;
    }
  }
  _loadsCache = (key, settings, loads);
  return loads;
}

(int, EstimateSettings, Map<DateTime, double>)? _loadsCache;

ToleranceTrend _trend(double now, double weekAgo) {
  if (weekAgo <= 0.01) return now > 0.2 ? ToleranceTrend.rising : ToleranceTrend.steady;
  final change = now / weekAgo;
  return change > 1.1 ? ToleranceTrend.rising : (change < 0.9 ? ToleranceTrend.falling : ToleranceTrend.steady);
}

/// Tolerance over [from]..[to] for [substance]'s track, with the break plan from [now].
ToleranceView toleranceView({
  required Substance substance,
  required List<Ingestion> ingestions,
  required Map<String, Substance> byKey,
  required EstimateSettings settings,
  required DateTime from,
  required DateTime to,
  required DateTime now,
  Duration? step,
}) {
  final span = to.difference(from);
  final st = step ?? Duration(minutes: max(30, span.inMinutes ~/ 240));
  final live = [for (final i in ingestions) if (!i.deleted) i];

  if (substance.key == 'alcohol') {
    final loads = alcoholLoads([for (final i in live) if (i.substanceKey == 'alcohol') i], settings);
    final line = alcoholToleranceTimeline(loads, from, to, step: st, settings: settings);
    final score = alcoholToleranceScoreAt({for (final e in loads.entries) if (!e.key.isAfter(now)) e.key: e.value}, now, settings);
    final weekAgo = alcoholToleranceScoreAt(loads, now.subtract(const Duration(days: 7)), settings);
    final multiplier = toleranceMultiplier(score, settings);
    return ToleranceView(
      trackKey: 'alcohol',
      alcohol: true,
      points: [for (final p in line) (p.$1, p.$3)],
      now: multiplier,
      multiplierNow: multiplier,
      word: '${multiplier.toStringAsFixed(2)}x',
      trend: _trend(score, weekAgo),
      plan: BreakPlan(
        from: now,
        half: alcoholTimeToScore(loads, now, score / 2, settings),
        quarter: alcoholTimeToScore(loads, now, score / 4, settings),
        baseline: alcoholTimeToScore(loads, now, alcoholBaselineScore(settings), settings),
      ),
      sharedWith: const [],
    );
  }

  final track = toleranceTrackKey(substance);
  final events = useEventsFor(live, byKey);
  final level = currentToleranceLevel(events, byKey, track, now);
  final weekAgo = currentToleranceLevel(events, byKey, track, now.subtract(const Duration(days: 7)));
  final shared = <String>{
    for (final s in byKey.values)
      if (s.key != substance.key && s.hasTolerance && toleranceTrackKey(s) == track && live.any((i) => i.substanceKey == s.key)) s.name,
  }.toList()
    ..sort();
  return ToleranceView(
    trackKey: track,
    alcohol: false,
    points: toleranceTimeline(events, byKey, track, from, to, step: st),
    now: level,
    word: toleranceWord(level),
    trend: _trend(level, weekAgo),
    plan: BreakPlan(
      from: now,
      half: timeToFraction(events, byKey, track, now, 0.5),
      quarter: timeToFraction(events, byKey, track, now, 0.25),
      low: timeToLevel(events, byKey, track, now, 0.5),
      baseline: timeToLevel(events, byKey, track, now, baselineLevel),
    ),
    sharedWith: shared,
  );
}

/// Lifetime figures, records, patterns and session gains for every substance in one person's
/// journal, most used first. Pass ONE person's ingestions.
List<SubstanceHistory> buildHistories({
  required List<Ingestion> ingestions,
  required Map<String, Substance> byKey,
  required EstimateSettings settings,
  required DateTime now,
}) {
  final live = [for (final i in ingestions) if (!i.deleted) i]..sort((a, b) => a.time.compareTo(b.time));
  final byExperience = <String, List<Ingestion>>{};
  for (final i in live) {
    byExperience.putIfAbsent(i.experienceId, () => []).add(i);
  }
  final events = useEventsFor(live, byKey);
  final drinksAll = [for (final i in live) if (i.substanceKey == 'alcohol') i];
  final loads = drinksAll.isEmpty ? const <DateTime, double>{} : alcoholLoads(drinksAll, settings);

  final result = <SubstanceHistory>[];
  final keys = {for (final i in live) i.substanceKey};
  for (final key in keys) {
    final mine = [for (final i in live) if (i.substanceKey == key) i];
    final s = byKey[key];
    final name = s?.name ?? key;

    final units = <String, int>{};
    final totals = <String, double>{};
    for (final i in mine) {
      if (i.dose == null) continue;
      units[_unit(i)] = (units[_unit(i)] ?? 0) + 1;
      totals[_unit(i)] = (totals[_unit(i)] ?? 0) + _amount(i);
    }
    final mainUnit = units.isEmpty ? '' : (units.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final inMain = [for (final i in mine) if (i.dose != null && _unit(i) == mainUnit) i];

    // Days, breaks and the current run.
    final days = {for (final i in mine) _day(i.time)}.toList()..sort();
    var longest = 0;
    DateTime? longestFrom;
    for (var n = 1; n < days.length; n++) {
      final gap = days[n].difference(days[n - 1]).inHours ~/ 24 - 1;
      if (gap > longest) {
        longest = gap;
        longestFrom = days[n - 1];
      }
    }
    var run = 0;
    final today = _day(now);
    final daySet = days.toSet();
    var cursor = daySet.contains(today) ? today : DateTime(today.year, today.month, today.day - 1);
    while (daySet.contains(cursor)) {
      run++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }

    // Records.
    final largestByRoute = <String, AmountAt>{};
    for (final i in inMain) {
      final current = largestByRoute[i.route];
      if (current == null || _amount(i) > current.amount) {
        largestByRoute[i.route] = AmountAt(_amount(i), mainUnit, i.time, i.experienceId, route: i.route);
      }
    }
    AmountAt? largestSession;
    final sessionTotals = <(DateTime, double)>[];
    final expIds = <String>{for (final i in mine) i.experienceId};
    for (final id in expIds) {
      final doses = [for (final i in byExperience[id]!) if (i.substanceKey == key && i.dose != null && _unit(i) == mainUnit) i];
      if (doses.isEmpty) continue;
      final sum = doses.fold<double>(0, (a, i) => a + _amount(i));
      sessionTotals.add((doses.first.time, sum));
      if (largestSession == null || sum > largestSession.amount) largestSession = AmountAt(sum, mainUnit, doses.first.time, id);
    }
    sessionTotals.sort((a, b) => a.$1.compareTo(b.$1));

    AmountAt? most24h;
    var lo = 0;
    var window = 0.0;
    for (var hi = 0; hi < inMain.length; hi++) {
      window += _amount(inMain[hi]);
      while (inMain[hi].time.difference(inMain[lo].time) >= const Duration(hours: 24)) {
        window -= _amount(inMain[lo]);
        lo++;
      }
      if (most24h == null || window > most24h.amount + 1e-9) most24h = AmountAt(window, mainUnit, inMain[lo].time, inMain[hi].experienceId);
    }

    AmountAt? peak;
    var peakUnit = 'x a common dose';
    if (key == 'alcohol') {
      peakUnit = '% BAC';
      for (final id in expIds) {
        final drinks = [for (final i in byExperience[id]!) if (i.substanceKey == 'alcohol') alcoholDrinkFrom(i, settings)];
        if (drinks.isEmpty) continue;
        final e = sessionExposure(drinks, settings);
        if (peak == null || e.peakBac > peak.amount) peak = AmountAt(e.peakBac, peakUnit, e.peakAt ?? e.start, id);
      }
    } else if (s != null) {
      for (final id in expIds) {
        final curve = <CurveIngestion>[];
        for (final i in byExperience[id]!) {
          if (i.substanceKey != key) continue;
          final roa = s.nearestRoute(i.route);
          if (roa == null) continue;
          curve.add(CurveIngestion(substanceKey: key, roaId: roa.id, amount: i.dose ?? roa.doseCommon?.min ?? 1.0, occurredAt: i.time));
        }
        if (curve.isEmpty) continue;
        final pts = sessionEffectSeries(curve, byKey, now: curve.first.occurredAt.add(const Duration(days: 3)));
        for (final (t, v) in pts) {
          if (peak == null || v > peak.amount) peak = AmountAt(v, peakUnit, t, id);
        }
      }
    }

    // Patterns.
    final weekday = List<int>.filled(7, 0);
    final hour = List<int>.filled(24, 0);
    final routes = <String, int>{};
    for (final i in mine) {
      weekday[i.time.weekday - 1]++;
      hour[i.time.hour]++;
      routes[i.route] = (routes[i.route] ?? 0) + 1;
    }
    final combos = <String, int>{};
    for (final id in expIds) {
      for (final other in {for (final i in byExperience[id]!) if (i.substanceKey != key) i.substanceKey}) {
        final n = byKey[other]?.name ?? other;
        combos[n] = (combos[n] ?? 0) + 1;
      }
    }

    // Tolerance added by each experience.
    final gains = <SessionGainRow>[];
    for (final id in expIds) {
      final doses = [for (final i in byExperience[id]!) if (i.substanceKey == key) i];
      final start = doses.first.time;
      final end = doses.last.endTime ?? doses.last.time;
      if (key == 'alcohol') {
        final before = alcoholToleranceScoreAt({for (final e in loads.entries) if (e.key.isBefore(start)) e.key: e.value}, start, settings);
        final after = alcoholToleranceScoreAt({for (final e in loads.entries) if (!e.key.isAfter(end)) e.key: e.value}, end, settings);
        gains.add(SessionGainRow(experienceId: id, start: start, end: end, before: before, after: after, alcohol: true, settings: settings));
      } else if (s != null && s.hasTolerance) {
        final g = sessionGain(events, byKey, toleranceTrackKey(s), start, end);
        gains.add(SessionGainRow(experienceId: id, start: start, end: end, before: g.before, after: g.after, alcohol: false, settings: settings));
      }
    }
    gains.sort((a, b) => b.start.compareTo(a.start));

    result.add(SubstanceHistory(
      key: key,
      name: name,
      doses: mine.length,
      mainUnit: mainUnit,
      totalByUnit: totals,
      first: mine.first.time,
      last: mine.last.time,
      averageDose: inMain.isEmpty ? null : inMain.fold<double>(0, (a, i) => a + _amount(i)) / inMain.length,
      daysUsed: days.length,
      longestBreakDays: longest,
      longestBreakFrom: longestFrom,
      currentRunDays: run,
      largestByRoute: largestByRoute,
      largestSession: largestSession,
      most24h: most24h,
      highestPeak: peak,
      peakUnit: peakUnit,
      sessionTotals: sessionTotals,
      byWeekday: weekday,
      byHour: hour,
      routes: routes,
      combos: combos.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      gains: gains,
      experiences: expIds.length,
    ));
  }
  result.sort((a, b) => b.doses.compareTo(a.doses));
  return result;
}
