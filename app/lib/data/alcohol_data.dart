import 'dart:convert';

import 'package:sj_core/sj_core.dart';

import 'database.dart';

/// Drink details stored on an alcohol ingestion (see [AppDatabase.logDrink]).
class DrinkDetails {
  const DrinkDetails({this.name = '', this.volume, this.volumeUnit, this.abv});

  final String name;
  final double? volume;
  final String? volumeUnit;
  final double? abv;

  bool get hasVolume => volume != null && volumeUnit != null && abv != null;

  static DrinkDetails of(Ingestion ingestion) {
    if (ingestion.detailsJson.isEmpty) return const DrinkDetails();
    final json = jsonDecode(ingestion.detailsJson) as Map<String, dynamic>;
    return DrinkDetails(
      name: json['drink'] as String? ?? '',
      volume: (json['volume'] as num?)?.toDouble(),
      volumeUnit: json['volumeUnit'] as String?,
      abv: (json['abv'] as num?)?.toDouble(),
    );
  }
}

/// The ingestion as the estimation model wants it. Uses the recorded volume, unit and ABV when
/// present, otherwise the grams of ethanol.
AlcoholIngestion alcoholDrinkFrom(Ingestion ingestion, EstimateSettings settings) {
  final d = DrinkDetails.of(ingestion);
  final duration = ingestion.endTime == null ? 0.0 : ingestion.endTime!.difference(ingestion.time).inSeconds / 60.0;
  return alcoholIngestionFor(
    at: ingestion.time,
    volume: d.volume,
    volumeUnit: d.volumeUnit,
    abvPercent: d.abv,
    grams: ingestion.dose,
    durationMinutes: duration < 0 ? 0 : duration,
    settings: settings,
  );
}

/// Human text for a drink: "Beer 12 oz 5%" or, without details, "14 g ethanol".
String describeDrink(Ingestion ingestion) {
  final d = DrinkDetails.of(ingestion);
  final amount = d.hasVolume ? '${_n(d.volume!)} ${d.volumeUnit} ${_n(d.abv!)}%' : '${_n(ingestion.dose ?? 0)} g ethanol';
  return d.name.isEmpty ? amount : d.name;
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Standard drinks in one logged drink.
double standardDrinksOf(Ingestion ingestion, EstimateSettings settings) =>
    alcoholDrinkFrom(ingestion, settings).standardDrinks(settings);

/// Total standard drinks per calendar day (by the time each drink was logged).
Map<DateTime, double> dailyStandardDrinks(Iterable<Ingestion> drinks, EstimateSettings settings) {
  final totals = <DateTime, double>{};
  for (final d in drinks) {
    final day = dateOnly(d.time);
    totals[day] = (totals[day] ?? 0) + standardDrinksOf(d, settings);
  }
  return totals;
}

/// Estimated BAC curve over a window, from the drinks that could still matter in it.
List<(DateTime, double)> bacSeries(
  List<Ingestion> drinks,
  EstimateSettings settings, {
  required DateTime from,
  required DateTime to,
  int stepMinutes = 10,
}) {
  final relevant = [
    for (final d in drinks)
      if (!d.time.isAfter(to)) alcoholDrinkFrom(d, settings),
  ];
  if (relevant.isEmpty) return const [];
  return [
    for (final (t, pool) in simulateActiveDrinks(relevant, from, to, settings, stepMinutes)) (t, estimateBac(pool, settings)),
  ];
}
