// Drink maths, daily summaries and settings storage for the Alcohol mode.
//
// Daily summaries port alcohol_tracker/core/analytics.py (checked against Python goldens).
import 'alcohol.dart';

const double millilitresPerFlOz = 29.5735;

/// Units a drink's volume can be entered in.
const List<String> drinkVolumeUnits = ['oz', 'ml', 'shots'];

/// Volume of a drink in US fluid ounces. A shot is [shotOz] (the user's standard-drink volume).
double drinkFluidOunces(double volume, String unit, {double shotOz = shotVolumeOz}) => switch (unit) {
      'shots' => volume * shotOz,
      'ml' => volume / millilitresPerFlOz,
      _ => volume,
    };

/// Pure alcohol in grams, with Alcohol Tracker's density (23.36 g per fl oz of pure ethanol).
double drinkGrams(double volume, String unit, double abvPercent, {double shotOz = shotVolumeOz}) =>
    drinkFluidOunces(volume, unit, shotOz: shotOz) * (abvPercent / 100.0) * alcoholDensityGramsPerFlOz;

/// How many standard drinks a number of grams is under [settings]' standard drink.
double standardDrinksFromGrams(double grams, [EstimateSettings settings = const EstimateSettings()]) =>
    grams / alcoholDensityGramsPerFlOz / settings.standardDrinkPureAlcoholOz;

/// A logged drink as the estimation model wants it. Pass the volume, unit and ABV when they are
/// known (identical to Alcohol Tracker's records); otherwise [grams] of ethanol are used.
AlcoholIngestion alcoholIngestionFor({
  required DateTime at,
  double? volume,
  String? volumeUnit,
  double? abvPercent,
  double? grams,
  double durationMinutes = 0,
  String consumer = 'Me',
  EstimateSettings settings = const EstimateSettings(),
}) {
  if (volume != null && volumeUnit != null && abvPercent != null) {
    final shots = volumeUnit == 'shots';
    return AlcoholIngestion(
      occurredAt: at,
      amount: shots ? volume : drinkFluidOunces(volume, volumeUnit),
      unit: shots ? 'shots' : 'oz',
      abvPercent: abvPercent,
      durationMinutes: durationMinutes,
      consumer: consumer,
    );
  }
  return AlcoholIngestion(
    occurredAt: at,
    amount: (grams ?? 0) / alcoholDensityGramsPerFlOz,
    unit: 'oz',
    abvPercent: 100.0,
    durationMinutes: durationMinutes,
    consumer: consumer,
  );
}

// ---- daily summaries (analytics.py) ----

DateTime dateOnly(DateTime t) => t.isUtc ? DateTime.utc(t.year, t.month, t.day) : DateTime(t.year, t.month, t.day);

DateTime _nextDay(DateTime d) => d.isUtc ? DateTime.utc(d.year, d.month, d.day + 1) : DateTime(d.year, d.month, d.day + 1);

/// Every date from the first logged day through [today], gaps filled with zero.
Map<DateTime, double> fillDailyTotals(Map<DateTime, double> totals, {required DateTime today}) {
  final normalized = {for (final e in totals.entries) dateOnly(e.key): e.value};
  if (normalized.isEmpty) return {};
  var first = normalized.keys.first;
  var last = normalized.keys.first;
  for (final d in normalized.keys) {
    if (d.isBefore(first)) first = d;
    if (d.isAfter(last)) last = d;
  }
  final end = dateOnly(today).isAfter(last) ? dateOnly(today) : last;
  final result = <DateTime, double>{};
  for (var day = first; !day.isAfter(end); day = _nextDay(day)) {
    result[day] = normalized[day] ?? 0.0;
  }
  return result;
}

int _daysInclusive(DateTime start, DateTime end) =>
    DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;

Iterable<double> _inRange(Map<DateTime, double> totals, DateTime start, DateTime end) sync* {
  for (final e in totals.entries) {
    final day = dateOnly(e.key);
    if (!day.isBefore(start) && !day.isAfter(end)) yield e.value;
  }
}

/// Average drinking days per week over the inclusive date range.
double averageDrinkingDays(Map<DateTime, double> totals, DateTime start, DateTime end) {
  start = dateOnly(start);
  end = dateOnly(end).isBefore(start) ? start : dateOnly(end);
  final span = _daysInclusive(start, end);
  return 7 * _inRange(totals, start, end).where((v) => v > 0).length / span;
}

/// Mean standard drinks per day over the inclusive range, counting zero days.
double averageStandardDrinksPerDay(Map<DateTime, double> totals, DateTime start, DateTime end) {
  start = dateOnly(start);
  end = dateOnly(end).isBefore(start) ? start : dateOnly(end);
  final span = _daysInclusive(start, end);
  var sum = 0.0;
  for (final v in _inRange(totals, start, end)) {
    sum += v;
  }
  return sum / span;
}

// ---- settings storage ----

extension EstimateSettingsJson on EstimateSettings {
  Map<String, Object> toJson() => {
        'absorptionMinutes': absorptionMinutes,
        'absorptionLagMinutes': absorptionLagMinutes,
        'eliminationStandardDrinksPerHour': eliminationStandardDrinksPerHour,
        'toleranceHalfLifeDays': toleranceHalfLifeDays,
        'toleranceMaxExtraDose': toleranceMaxExtraDose,
        'toleranceHalfSaturationExposure': toleranceHalfSaturationExposure,
        'standardDrinkVolumeOz': standardDrinkVolumeOz,
        'standardDrinkAbvPercent': standardDrinkAbvPercent,
        'userWeightLbs': userWeightLbs,
        'userGender': userGender,
        'userHeightCm': userHeightCm,
        'userAgeYears': userAgeYears,
        'bacModel': bacModel,
      };
}

/// Reads settings saved by [EstimateSettingsJson.toJson]; anything missing or invalid keeps its default.
EstimateSettings estimateSettingsFromJson(Map<String, dynamic> json) {
  const d = EstimateSettings();
  double num_(String key, double fallback) => (json[key] is num) ? (json[key] as num).toDouble() : fallback;
  final model = json['bacModel'];
  return EstimateSettings(
    absorptionMinutes: (json['absorptionMinutes'] is num) ? (json['absorptionMinutes'] as num).toInt() : d.absorptionMinutes,
    absorptionLagMinutes: num_('absorptionLagMinutes', d.absorptionLagMinutes),
    eliminationStandardDrinksPerHour: num_('eliminationStandardDrinksPerHour', d.eliminationStandardDrinksPerHour),
    toleranceHalfLifeDays: num_('toleranceHalfLifeDays', d.toleranceHalfLifeDays),
    toleranceMaxExtraDose: num_('toleranceMaxExtraDose', d.toleranceMaxExtraDose),
    toleranceHalfSaturationExposure: num_('toleranceHalfSaturationExposure', d.toleranceHalfSaturationExposure),
    standardDrinkVolumeOz: num_('standardDrinkVolumeOz', d.standardDrinkVolumeOz),
    standardDrinkAbvPercent: num_('standardDrinkAbvPercent', d.standardDrinkAbvPercent),
    userWeightLbs: num_('userWeightLbs', d.userWeightLbs),
    userGender: json['userGender'] is String ? json['userGender'] as String : d.userGender,
    userHeightCm: num_('userHeightCm', d.userHeightCm),
    userAgeYears: num_('userAgeYears', d.userAgeYears),
    bacModel: (model == bacModelWatson || model == bacModelWidmark) ? model as String : d.bacModel,
  );
}

/// Problems with a set of estimate settings, for the settings form. Empty means valid.
List<String> validateEstimateSettings(EstimateSettings s) {
  final problems = <String>[];
  if (s.userWeightLbs < 50 || s.userWeightLbs > 700) problems.add('Weight must be between 50 and 700 lb.');
  if (s.userHeightCm < 100 || s.userHeightCm > 250) problems.add('Height must be between 100 and 250 cm.');
  if (s.userAgeYears < 18 || s.userAgeYears > 120) problems.add('Age must be between 18 and 120.');
  if (s.absorptionMinutes < 5 || s.absorptionMinutes > 240) problems.add('Absorption time must be between 5 and 240 minutes.');
  if (s.absorptionLagMinutes < 0 || s.absorptionLagMinutes > 120) problems.add('Absorption lag must be between 0 and 120 minutes.');
  if (s.eliminationStandardDrinksPerHour < 0.2 || s.eliminationStandardDrinksPerHour > 1.5) {
    problems.add('Elimination must be between 0.2 and 1.5 standard drinks per hour.');
  }
  if (s.standardDrinkVolumeOz <= 0 || s.standardDrinkAbvPercent <= 0 || s.standardDrinkAbvPercent > 100) {
    problems.add('The standard drink needs a positive volume and an ABV up to 100%.');
  }
  if (s.toleranceHalfLifeDays < 0.5 || s.toleranceHalfLifeDays > 90) problems.add('Tolerance half-life must be between 0.5 and 90 days.');
  return problems;
}
