import 'cannabis_products.dart';
import 'database.dart';

/// The last seven days (today and the six before it) for one person, next to the seven before that.
class WeekSummary {
  const WeekSummary({
    required this.from,
    required this.doses,
    required this.daysWithUse,
    required this.bySubstance,
    required this.spend,
    required this.previousDoses,
    required this.previousDaysWithUse,
  });

  /// The first day of the window (midnight).
  final DateTime from;
  final int doses;
  final int daysWithUse;
  int get daysWithout => 7 - daysWithUse;

  /// Doses per substance key, most first.
  final List<MapEntry<String, int>> bySubstance;

  /// Money spent on products with a saved cost per gram, from the grams actually used. Null when
  /// nothing used this week has a cost saved, so it never reads as "spent nothing".
  final double? spend;
  final int previousDoses;
  final int previousDaysWithUse;
  int get previousDaysWithout => 7 - previousDaysWithUse;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

WeekSummary weekSummary({required Iterable<Ingestion> ingestions, required Iterable<Product> products, required DateTime now}) {
  final today = _day(now);
  final from = DateTime(today.year, today.month, today.day - 6);
  final prevFrom = DateTime(today.year, today.month, today.day - 13);
  final end = DateTime(today.year, today.month, today.day + 1);

  final live = [for (final i in ingestions) if (!i.deleted) i];
  final thisWeek = [for (final i in live) if (!i.time.isBefore(from) && i.time.isBefore(end)) i];
  final lastWeek = [for (final i in live) if (!i.time.isBefore(prevFrom) && i.time.isBefore(from)) i];

  final counts = <String, int>{};
  for (final i in thisWeek) {
    counts[i.substanceKey] = (counts[i.substanceKey] ?? 0) + 1;
  }

  double? spend;
  for (final p in products) {
    if (ProductDetails.of(p).costPerGram == null) continue;
    final s = ProductUsage.of(p, thisWeek).spend;
    if (s != null) spend = (spend ?? 0) + s;
  }

  return WeekSummary(
    from: from,
    doses: thisWeek.length,
    daysWithUse: {for (final i in thisWeek) _day(i.time)}.length,
    bySubstance: counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    spend: spend,
    previousDoses: lastWeek.length,
    previousDaysWithUse: {for (final i in lastWeek) _day(i.time)}.length,
  );
}
