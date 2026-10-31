import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';

/// Everything the Alcohol mode day view shows for one person on one day.
class AlcoholDaySummary {
  const AlcoholDaySummary({
    required this.drinksOfDay,
    required this.standardDrinks,
    required this.bacSeries,
    required this.peakBac,
    required this.peakAt,
    this.bacNow,
    this.inBodyNow,
    this.clearTime,
  });

  /// The drinks logged on the day itself, oldest first.
  final List<Ingestion> drinksOfDay;
  final double standardDrinks;

  /// Estimated BAC (percent) over time, including drinks from before the day that still count.
  final List<(DateTime, double)> bacSeries;
  final double peakBac;
  final DateTime? peakAt;

  /// Only for today: BAC right now, alcohol still in the body (gut plus blood, in standard
  /// drinks) and when it is estimated to be gone.
  final double? bacNow;
  final double? inBodyNow;
  final DateTime? clearTime;

  bool get isEmpty => drinksOfDay.isEmpty && bacSeries.isEmpty;
}

/// Summarises [day] (null means today) from ONE person's [allDrinks].
///
/// Today looks back 36 hours so a night that runs past midnight stays one curve; a past day
/// includes drinks from the 12 hours around it that still affect it.
AlcoholDaySummary summarizeAlcoholDay({
  required List<Ingestion> allDrinks,
  required EstimateSettings settings,
  required DateTime now,
  DateTime? day,
}) {
  final isToday = day == null || dateOnly(day) == dateOnly(now);
  final anchor = isToday ? now : dateOnly(day);
  final dayStart = dateOnly(anchor);
  final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);

  final drinksOfDay = [
    for (final d in allDrinks)
      if (!d.time.isBefore(dayStart) && d.time.isBefore(dayEnd)) d,
  ]..sort((a, b) => a.time.compareTo(b.time));

  final windowStart = isToday ? now.subtract(const Duration(hours: 36)) : dayStart.subtract(const Duration(hours: 12));
  final windowEnd = isToday ? now.add(const Duration(days: 1)) : dayEnd.add(const Duration(hours: 12));
  final relevant = [
    for (final d in allDrinks)
      if (!d.time.isBefore(windowStart) && d.time.isBefore(windowEnd)) alcoholDrinkFrom(d, settings),
  ];

  var standard = 0.0;
  for (final d in drinksOfDay) {
    standard += standardDrinksOf(d, settings);
  }

  if (relevant.isEmpty) {
    return AlcoholDaySummary(
      drinksOfDay: drinksOfDay,
      standardDrinks: standard,
      bacSeries: const [],
      peakBac: 0,
      peakAt: null,
      bacNow: isToday ? 0.0 : null,
      inBodyNow: isToday ? 0.0 : null,
    );
  }

  final pool = effectSeries(relevant, anchor, settings);
  final bac = [for (final (t, v) in pool) (t, estimateBac(v, settings))];
  final (peakAt, peak) = peakValue(bac);

  double? bacNow;
  double? inBody;
  DateTime? clear;
  if (isToday) {
    bacNow = estimateBac(estimateActiveStandardDrinks(relevant, now, settings), settings);
    inBody = estimateAlcoholInBody(relevant, now, settings);
    if (inBody > 0.05) {
      clear = estimatedClearTime(pool);
      // The chart window is a guess at how long the drinks last; if it ended first, look further ahead.
      clear ??= estimatedClearTime(effectSeries(relevant, anchor, settings, null, now.add(const Duration(days: 3))));
    }
  }
  return AlcoholDaySummary(
    drinksOfDay: drinksOfDay,
    standardDrinks: standard,
    bacSeries: bac,
    peakBac: peak,
    peakAt: peakAt,
    bacNow: bacNow,
    inBodyNow: inBody,
    clearTime: clear,
  );
}

/// The presets to offer as one-tap buttons: the ones used most in the last 90 days, topped up
/// with the rest in list order.
List<Preset> topPresets(List<Preset> presets, List<Ingestion> drinks, DateTime now, {int count = 4}) {
  final cutoff = now.subtract(const Duration(days: 90));
  final uses = <String, int>{};
  for (final d in drinks) {
    if (d.time.isBefore(cutoff)) continue;
    final name = DrinkDetails.of(d).name;
    if (name.isNotEmpty) uses[name] = (uses[name] ?? 0) + 1;
  }
  final used = [for (final p in presets) if ((uses[p.name] ?? 0) > 0) p]
    ..sort((a, b) {
      final byUse = uses[b.name]!.compareTo(uses[a.name]!);
      return byUse != 0 ? byUse : a.name.compareTo(b.name);
    });
  final rest = [for (final p in presets) if (!used.contains(p))p];
  return [...used, ...rest].take(count).toList();
}

/// Days with at least one drink, newest first, with their totals.
List<({DateTime day, int drinks, double standardDrinks})> drinkingDays(List<Ingestion> allDrinks, EstimateSettings settings) {
  final byDay = <DateTime, ({int drinks, double standard})>{};
  for (final d in allDrinks) {
    final day = dateOnly(d.time);
    final current = byDay[day] ?? (drinks: 0, standard: 0.0);
    byDay[day] = (drinks: current.drinks + 1, standard: current.standard + standardDrinksOf(d, settings));
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final day in days) (day: day, drinks: byDay[day]!.drinks, standardDrinks: byDay[day]!.standard)];
}
