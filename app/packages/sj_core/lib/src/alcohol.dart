// Dart port of Alcohol Tracker's estimation model (alcohol_tracker/core/calculations.py).
//
// One-compartment pharmacokinetics: each drink enters the gut (optionally spread over the
// time spent drinking it), moves to the bloodstream by first-order absorption after a lag,
// and the bloodstream pool drains by Michaelis-Menten elimination. BAC uses the Watson
// total-body-water regressions by default, or Widmark's fixed ratios. Tolerance is driven by
// CNS exposure (%BAC-hours above 0.02).
//
// This is a journaling estimate, not a medical or legal measurement. The port is checked
// against golden vectors from the Python implementation (scripts/export_alcohol_golden.py),
// so the numbers must match it exactly. Keep the order of floating-point operations the same
// as the Python when editing.
import 'dart:math';

const String bacModelWatson = 'watson';
const String bacModelWidmark = 'widmark';

const double standardDrinkPureAlcoholOzDefault = 0.6; // US standard drink
const double shotVolumeOz = 1.5;
const double alcoholDensityGramsPerFlOz = 23.36;
const double poundsPerKilogram = 2.20462;
const double bloodWaterFraction = 0.806;
const double absorptionCompletionFraction = 0.95;
const double toleranceBacThreshold = 0.02;
const double ethanolMichaelisConstantBac = 0.0082;
const double _emptyPoolStandardDrinks = 1e-3;
const double _absorptionSettledFraction = 1e-6;

class EstimateSettings {
  const EstimateSettings({
    this.absorptionMinutes = 45,
    this.absorptionLagMinutes = 15.0,
    this.eliminationStandardDrinksPerHour = 0.67,
    this.toleranceHalfLifeDays = 7.0,
    this.toleranceMaxExtraDose = 1.0,
    this.toleranceHalfSaturationExposure = 3.0,
    this.standardDrinkVolumeOz = 1.5,
    this.standardDrinkAbvPercent = 40.0,
    this.userWeightLbs = 150.0,
    this.userGender = 'M',
    this.userHeightCm = 178.0,
    this.userAgeYears = 30.0,
    this.bacModel = bacModelWatson,
  });

  final int absorptionMinutes;
  final double absorptionLagMinutes;
  final double eliminationStandardDrinksPerHour;
  final double toleranceHalfLifeDays;
  final double toleranceMaxExtraDose;
  final double toleranceHalfSaturationExposure;
  final double standardDrinkVolumeOz;
  final double standardDrinkAbvPercent;
  final double userWeightLbs;
  final String userGender;
  final double userHeightCm;
  final double userAgeYears;
  final String bacModel;

  double get standardDrinkPureAlcoholOz => standardDrinkVolumeOz * (standardDrinkAbvPercent / 100.0);

  EstimateSettings copyWith({
    int? absorptionMinutes,
    double? absorptionLagMinutes,
    double? eliminationStandardDrinksPerHour,
    double? toleranceHalfLifeDays,
    double? toleranceMaxExtraDose,
    double? toleranceHalfSaturationExposure,
    double? standardDrinkVolumeOz,
    double? standardDrinkAbvPercent,
    double? userWeightLbs,
    String? userGender,
    double? userHeightCm,
    double? userAgeYears,
    String? bacModel,
  }) =>
      EstimateSettings(
        absorptionMinutes: absorptionMinutes ?? this.absorptionMinutes,
        absorptionLagMinutes: absorptionLagMinutes ?? this.absorptionLagMinutes,
        eliminationStandardDrinksPerHour: eliminationStandardDrinksPerHour ?? this.eliminationStandardDrinksPerHour,
        toleranceHalfLifeDays: toleranceHalfLifeDays ?? this.toleranceHalfLifeDays,
        toleranceMaxExtraDose: toleranceMaxExtraDose ?? this.toleranceMaxExtraDose,
        toleranceHalfSaturationExposure: toleranceHalfSaturationExposure ?? this.toleranceHalfSaturationExposure,
        standardDrinkVolumeOz: standardDrinkVolumeOz ?? this.standardDrinkVolumeOz,
        standardDrinkAbvPercent: standardDrinkAbvPercent ?? this.standardDrinkAbvPercent,
        userWeightLbs: userWeightLbs ?? this.userWeightLbs,
        userGender: userGender ?? this.userGender,
        userHeightCm: userHeightCm ?? this.userHeightCm,
        userAgeYears: userAgeYears ?? this.userAgeYears,
        bacModel: bacModel ?? this.bacModel,
      );
}

/// A logged drink. [unit] is `shots` or `oz` (fluid ounces).
class AlcoholIngestion {
  const AlcoholIngestion({
    required this.occurredAt,
    required this.amount,
    required this.unit,
    required this.abvPercent,
    this.label = '',
    this.durationMinutes = 0.0,
    this.consumer = 'Me',
  });

  final DateTime occurredAt;
  final double amount;
  final String unit;
  final double abvPercent;
  final String label;
  final double durationMinutes;
  final String consumer;

  double fluidOunces(EstimateSettings s) => unit == 'shots' ? amount * s.standardDrinkVolumeOz : amount;

  double pureAlcoholOz(EstimateSettings s) => fluidOunces(s) * (abvPercent / 100.0);

  double pureAlcoholGrams(EstimateSettings s) => pureAlcoholOz(s) * alcoholDensityGramsPerFlOz;

  double standardDrinks(EstimateSettings s) => pureAlcoholOz(s) / max(s.standardDrinkPureAlcoholOz, 1e-9);
}

// ---- body model ----

/// Total body water (litres) from the Watson (1980) regressions.
double totalBodyWaterLitres([EstimateSettings s = const EstimateSettings()]) {
  final weightKg = max(s.userWeightLbs, 1.0) / poundsPerKilogram;
  final heightCm = max(s.userHeightCm, 1.0);
  final ageYears = max(s.userAgeYears, 1.0);

  final male = 2.447 - 0.09516 * ageYears + 0.1074 * heightCm + 0.3362 * weightKg;
  final female = -2.097 + 0.1069 * heightCm + 0.2466 * weightKg;

  final gender = s.userGender.trim().toLowerCase();
  final double litres;
  if (gender.startsWith('m')) {
    litres = male;
  } else if (gender.startsWith('f')) {
    litres = female;
  } else {
    litres = (male + female) / 2.0;
  }
  return max(litres, 1.0);
}

/// The Widmark distribution ratio r implied by the Watson body-water estimate.
double bodyWaterDistributionRatio([EstimateSettings s = const EstimateSettings()]) {
  final weightKg = max(s.userWeightLbs, 1.0) / poundsPerKilogram;
  return totalBodyWaterLitres(s) / (bloodWaterFraction * weightKg);
}

/// Blood alcohol concentration in percent (g ethanol per 100 mL blood).
double estimateBac(double activeStandardDrinks, [EstimateSettings s = const EstimateSettings()]) {
  if (activeStandardDrinks <= 0) return 0.0;
  final grams = activeStandardDrinks * s.standardDrinkPureAlcoholOz * alcoholDensityGramsPerFlOz;

  if (s.bacModel == bacModelWidmark) {
    final ratio = s.userGender.trim().toLowerCase().startsWith('m') ? 0.68 : 0.55;
    final weightGrams = max(s.userWeightLbs, 1.0) * 453.592;
    return max(0.0, grams / (weightGrams * ratio) * 100.0);
  }
  return max(0.0, bloodWaterFraction * grams / totalBodyWaterLitres(s) / 10.0);
}

// ---- pharmacokinetic simulation ----

double _absorptionRateConstant(EstimateSettings s) {
  final minutes = max(s.absorptionMinutes.toDouble(), 1.0);
  return -log(1.0 - absorptionCompletionFraction) / minutes;
}

double _cumulativeAbsorbed(
  AlcoholIngestion ingestion,
  double elapsedMinutes,
  double rateConstant,
  double lagMinutes,
  EstimateSettings s,
) {
  final dose = ingestion.standardDrinks(s);
  final tau = elapsedMinutes - lagMinutes;
  if (dose <= 0 || tau <= 0) return 0.0;

  final duration = max(ingestion.durationMinutes, 0.0);
  if (duration <= 0) return dose * (1.0 - exp(-rateConstant * tau));
  if (tau <= duration) {
    return (dose / duration) * (tau - (1.0 - exp(-rateConstant * tau)) / rateConstant);
  }
  final tail = exp(-rateConstant * (tau - duration)) - exp(-rateConstant * tau);
  return dose - (dose / (rateConstant * duration)) * tail;
}

double _settledAfterMinutes(AlcoholIngestion ingestion, EstimateSettings s) {
  final rateConstant = _absorptionRateConstant(s);
  final tailMinutes = -log(_absorptionSettledFraction) / rateConstant;
  return max(s.absorptionLagMinutes, 0.0) + max(ingestion.durationMinutes, 0.0) + tailMinutes;
}

double _minutesBetween(DateTime later, DateTime earlier) =>
    later.difference(earlier).inMicroseconds / Duration.microsecondsPerSecond / 60.0;

/// Python's stable `sorted(..., key=occurred_at)`; Dart's List.sort is not stable.
List<AlcoholIngestion> _sortedByTime(List<AlcoholIngestion> items) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = a.$2.occurredAt.compareTo(b.$2.occurredAt);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

DateTime _plusMinutes(DateTime t, double minutes) =>
    t.add(Duration(microseconds: (minutes * Duration.microsecondsPerMinute).round()));

/// Minute-by-minute standard drinks present in the body; index i is i minutes after [simStart].
List<double> _simulatePool(
  List<AlcoholIngestion> ingestions,
  DateTime simStart,
  DateTime simEnd,
  EstimateSettings s,
) {
  final sorted = _sortedByTime(ingestions);
  final rateConstant = _absorptionRateConstant(s);
  final lag = max(s.absorptionLagMinutes, 0.0);
  final eliminationPerMinute = max(s.eliminationStandardDrinksPerHour, 0.0) / 60.0;

  final bacPerDrink = estimateBac(1.0, s);
  final michaelisPool = bacPerDrink > 0 ? ethanolMichaelisConstantBac / bacPerDrink : 0.0;

  final totalMinutes = max((simEnd.difference(simStart).inMicroseconds / Duration.microsecondsPerSecond / 60.0).floor(), 0);
  final settledAt = [for (final item in sorted) _plusMinutes(item.occurredAt, _settledAfterMinutes(item, s))];

  var pool = 0.0;
  var previousAbsorbed = 0.0;
  var firstUnsettled = 0;
  var settledTotal = 0.0;

  final values = List<double>.filled(totalMinutes + 1, 0.0);
  for (var minute = 0; minute <= totalMinutes; minute++) {
    final current = simStart.add(Duration(minutes: minute));

    while (firstUnsettled < sorted.length && !settledAt[firstUnsettled].isAfter(current)) {
      settledTotal += sorted[firstUnsettled].standardDrinks(s);
      firstUnsettled++;
    }

    var absorbed = settledTotal;
    for (var index = firstUnsettled; index < sorted.length; index++) {
      final item = sorted[index];
      if (item.occurredAt.isAfter(current)) break;
      absorbed += _cumulativeAbsorbed(item, _minutesBetween(current, item.occurredAt), rateConstant, lag, s);
    }

    final gained = max(absorbed - previousAbsorbed, 0.0);
    previousAbsorbed = absorbed;
    pool += gained;
    pool -= pool > 0 ? eliminationPerMinute * pool / (michaelisPool + pool) : 0.0;
    if (pool < _emptyPoolStandardDrinks) pool = 0.0;
    values[minute] = pool;
  }
  return values;
}

/// Samples the modelled amount of alcohol in the body between two times.
List<(DateTime, double)> simulateActiveDrinks(
  List<AlcoholIngestion> ingestions,
  DateTime start,
  DateTime end, [
  EstimateSettings s = const EstimateSettings(),
  int stepMinutes = 10,
]) {
  if (end.isBefore(start)) end = start;

  var simStart = start;
  for (final item in ingestions) {
    if (item.occurredAt.isBefore(simStart)) simStart = item.occurredAt;
  }
  final pool = _simulatePool(ingestions, simStart, end, s);

  final step = max(stepMinutes, 1);
  final points = <(DateTime, double)>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    final index = (_minutesBetween(cursor, simStart)).floor();
    points.add((cursor, index >= 0 && index < pool.length ? pool[index] : 0.0));
    cursor = cursor.add(Duration(minutes: step));
  }
  return points;
}

/// Standard drinks still in the bloodstream pool at [when].
double estimateActiveStandardDrinks(
  List<AlcoholIngestion> ingestions,
  DateTime when, [
  EstimateSettings s = const EstimateSettings(),
]) {
  final relevant = [for (final i in ingestions) if (!i.occurredAt.isAfter(when)) i];
  if (relevant.isEmpty) return 0.0;
  var simStart = relevant.first.occurredAt;
  for (final i in relevant) {
    if (i.occurredAt.isBefore(simStart)) simStart = i.occurredAt;
  }
  return _simulatePool(relevant, simStart, when, s).last;
}

/// Estimated effect curve for a session (BAC-driven timeline), sampled every 10 minutes.
List<(DateTime, double)> effectSeries(
  List<AlcoholIngestion> ingestions,
  DateTime selectedDay, [
  EstimateSettings s = const EstimateSettings(),
  DateTime? startOverride,
  DateTime? endOverride,
]) {
  DateTime defaultStart;
  DateTime defaultEnd;
  if (ingestions.isNotEmpty) {
    var first = ingestions.first.occurredAt;
    var last = _plusMinutes(ingestions.first.occurredAt, max(ingestions.first.durationMinutes, 0));
    var total = 0.0;
    for (final item in ingestions) {
      if (item.occurredAt.isBefore(first)) first = item.occurredAt;
      final end = _plusMinutes(item.occurredAt, max(item.durationMinutes, 0));
      if (end.isAfter(last)) last = end;
      total += item.standardDrinks(s);
    }
    defaultStart = first.subtract(const Duration(minutes: 30));
    final clearanceHours = total / max(s.eliminationStandardDrinksPerHour, 0.1);
    final tailHours = max(8.0, clearanceHours + 2.0 + s.absorptionLagMinutes / 60.0);
    defaultEnd = _plusMinutes(last, tailHours * 60.0);
  } else {
    defaultStart = _startOfDay(selectedDay);
    defaultEnd = defaultStart.add(const Duration(hours: 12));
  }
  return simulateActiveDrinks(
    ingestions,
    startOverride ?? defaultStart,
    endOverride ?? defaultEnd,
    s,
    10,
  );
}

/// Alcohol drunk but not yet absorbed into the bloodstream at [when].
double estimateUnabsorbedStandardDrinks(
  List<AlcoholIngestion> ingestions,
  DateTime when, [
  EstimateSettings s = const EstimateSettings(),
]) {
  final rateConstant = _absorptionRateConstant(s);
  final lag = max(s.absorptionLagMinutes, 0.0);
  var total = 0.0;
  for (final item in ingestions) {
    if (item.occurredAt.isAfter(when)) continue;
    final elapsed = _minutesBetween(when, item.occurredAt);
    final absorbed = _cumulativeAbsorbed(item, elapsed, rateConstant, lag, s);
    total += max(item.standardDrinks(s) - absorbed, 0.0);
  }
  return total;
}

/// Everything not yet eliminated: in the bloodstream plus still in the stomach.
double estimateAlcoholInBody(
  List<AlcoholIngestion> ingestions,
  DateTime when, [
  EstimateSettings s = const EstimateSettings(),
]) =>
    estimateActiveStandardDrinks(ingestions, when, s) + estimateUnabsorbedStandardDrinks(ingestions, when, s);

DateTime _lastInput(List<AlcoholIngestion> session) {
  var last = _plusMinutes(session.first.occurredAt, max(session.first.durationMinutes, 0));
  for (final item in session) {
    final end = _plusMinutes(item.occurredAt, max(item.durationMinutes, 0));
    if (end.isAfter(last)) last = end;
  }
  return last;
}

bool _sessionClearedBy(List<AlcoholIngestion> session, DateTime when, EstimateSettings s, double threshold) {
  final lastInput = _lastInput(session);
  if (!when.isAfter(lastInput)) return false;

  final eliminationPerMinute = max(s.eliminationStandardDrinksPerHour, 0.0) / 60.0;
  if (eliminationPerMinute > 0) {
    var totalDrinks = 0.0;
    for (final item in session) {
      totalDrinks += item.standardDrinks(s);
    }
    final tailMinutes = -log(_absorptionSettledFraction) / _absorptionRateConstant(s);
    final latestPossible = _plusMinutes(
      lastInput,
      max(s.absorptionLagMinutes, 0.0) + tailMinutes + totalDrinks / eliminationPerMinute,
    );
    if (!when.isBefore(latestPossible)) return true;
  }
  return estimateAlcoholInBody(session, when, s) <= threshold;
}

/// Groups ingestions into continuous drinking sessions (a night past midnight stays one).
List<List<AlcoholIngestion>> groupIntoSessions(
  List<AlcoholIngestion> ingestions, [
  EstimateSettings s = const EstimateSettings(),
  double threshold = 0.05,
]) {
  final ordered = _sortedByTime(ingestions);
  final sessions = <List<AlcoholIngestion>>[];
  var current = <AlcoholIngestion>[];
  for (final ingestion in ordered) {
    if (current.isNotEmpty && _sessionClearedBy(current, ingestion.occurredAt, s, threshold)) {
      sessions.add(current);
      current = <AlcoholIngestion>[];
    }
    current.add(ingestion);
  }
  if (current.isNotEmpty) sessions.add(current);
  return sessions;
}

// ---- tolerance ----

class SessionExposure {
  const SessionExposure({required this.start, required this.peakBac, required this.peakAt, required this.exposureBacHours});
  final DateTime start;
  final double peakBac;
  final DateTime? peakAt;
  final double exposureBacHours;
}

/// Integrates a session's BAC curve above the CNS threshold (%BAC-hours).
SessionExposure sessionExposure(
  List<AlcoholIngestion> session, [
  EstimateSettings s = const EstimateSettings(),
  int stepMinutes = 5,
]) {
  if (session.isEmpty) {
    return SessionExposure(start: DateTime.now(), peakBac: 0.0, peakAt: null, exposureBacHours: 0.0);
  }
  var start = session.first.occurredAt;
  var totalDrinks = 0.0;
  for (final item in session) {
    if (item.occurredAt.isBefore(start)) start = item.occurredAt;
    totalDrinks += item.standardDrinks(s);
  }
  final lastInput = _lastInput(session);
  final clearanceHours = totalDrinks / max(s.eliminationStandardDrinksPerHour, 0.1);
  final end = _plusMinutes(lastInput, (clearanceHours + 2.0) * 60.0);

  final points = simulateActiveDrinks(session, start, end, s, stepMinutes);
  final stepHours = max(stepMinutes, 1) / 60.0;
  var peakBac = 0.0;
  DateTime? peakAt;
  var exposure = 0.0;
  for (final (timestamp, active) in points) {
    final bac = estimateBac(active, s);
    if (bac > peakBac) {
      peakBac = bac;
      peakAt = timestamp;
    }
    exposure += max(bac - toleranceBacThreshold, 0.0) * stepHours;
  }
  return SessionExposure(start: start, peakBac: peakBac, peakAt: peakAt, exposureBacHours: exposure);
}

DateTime _startOfDay(DateTime t) => t.isUtc ? DateTime.utc(t.year, t.month, t.day) : DateTime(t.year, t.month, t.day);

int _dayNumber(DateTime t) => DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// CNS exposure per day in %BAC-hours, keyed by the day each session started.
Map<DateTime, double> dailyToleranceLoad(
  List<AlcoholIngestion> ingestions, [
  EstimateSettings s = const EstimateSettings(),
]) {
  final loads = <DateTime, double>{};
  for (final session in groupIntoSessions(ingestions, s)) {
    final exposure = sessionExposure(session, s);
    final day = _startOfDay(exposure.start);
    loads[day] = (loads[day] ?? 0.0) + exposure.exposureBacHours;
  }
  return loads;
}

/// Recency-weighted exposure score per day, decaying with the tolerance half-life.
List<(DateTime, double)> toleranceSeries(
  Map<DateTime, double> dailyLoads,
  DateTime endDay, [
  EstimateSettings s = const EstimateSettings(),
]) {
  final startDay = endDay.subtract(const Duration(days: 42));
  final halfLife = max(s.toleranceHalfLifeDays, 0.25);
  final decayConstant = log(2) / halfLife;

  var cursor = _startOfDay(startDay);

  var forwardDays = 14.0;
  var totalRecent = 0.0;
  for (final v in dailyLoads.values) {
    totalRecent += v;
  }
  if (totalRecent > 0) {
    const epsilon = 0.001;
    forwardDays = min(max(forwardDays, halfLife * log(max(totalRecent, epsilon) / epsilon) / log(2)), 365.0);
  }
  final finalDay = _startOfDay(_plusMinutes(endDay, forwardDays * 24 * 60));

  final points = <(DateTime, double)>[];
  while (!cursor.isAfter(finalDay)) {
    var score = 0.0;
    dailyLoads.forEach((day, load) {
      final ageDays = _dayNumber(cursor) - _dayNumber(day);
      if (ageDays >= 0) score += load * exp(-decayConstant * ageDays);
    });
    points.add((cursor, score));
    cursor = _startOfDay(cursor.add(const Duration(hours: 36))); // next calendar day, DST-safe
  }
  return points;
}

/// Dose multiplier needed to match a drink at the tolerance-free baseline (bounded).
double toleranceMultiplier(double score, [EstimateSettings s = const EstimateSettings()]) {
  final halfSaturation = max(s.toleranceHalfSaturationExposure, 1e-3);
  final maxExtraDose = max(s.toleranceMaxExtraDose, 0.0);
  return 1.0 + maxExtraDose * (1.0 - exp(-log(2) * max(score, 0.0) / halfSaturation));
}

List<(DateTime, double)> toleranceMultiplierSeries(
  Map<DateTime, double> dailyLoads,
  DateTime endDay, [
  EstimateSettings s = const EstimateSettings(),
]) =>
    [for (final (t, score) in toleranceSeries(dailyLoads, endDay, s)) (t, toleranceMultiplier(score, s))];

// ---- series helpers ----

(DateTime?, double) peakValue(List<(DateTime, double)> points) {
  if (points.isEmpty) return (null, 0.0);
  var best = points.first;
  for (final p in points) {
    if (p.$2 > best.$2) best = p;
  }
  return (best.$1, best.$2);
}

DateTime? estimatedClearTime(List<(DateTime, double)> points, [double threshold = 0.05]) {
  if (points.isEmpty) return null;
  var peakIndex = 0;
  for (var i = 0; i < points.length; i++) {
    if (points[i].$2 > points[peakIndex].$2) peakIndex = i;
  }
  for (var i = peakIndex; i < points.length; i++) {
    if (points[i].$2 <= threshold) return points[i].$1;
  }
  return null;
}
