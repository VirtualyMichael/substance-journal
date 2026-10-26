/// One logged dose, reduced to what the monthly summary needs.
class UsageEntry {
  const UsageEntry({required this.substanceKey, required this.time, this.dose, this.unit});
  final String substanceKey;
  final DateTime time;
  final double? dose;
  final String? unit;
}

/// What one substance looked like over a month.
class SubstanceUsage {
  const SubstanceUsage({required this.key, required this.doses, required this.days, this.totalDose, this.unit, this.unknownDoses = 0});

  final String key;
  final int doses;
  final int days;

  /// Sum of the known doses, when they share one unit; otherwise null.
  final double? totalDose;
  final String? unit;

  /// Doses logged without an amount.
  final int unknownDoses;
}

class MonthSummary {
  const MonthSummary({
    required this.year,
    required this.month,
    required this.doses,
    required this.daysWithUse,
    required this.perDay,
    required this.weekdayDoses,
    required this.bySubstance,
    required this.previousDoses,
    required this.previousDaysWithUse,
  });

  final int year;
  final int month;
  final int doses;
  final int daysWithUse;

  /// Doses on each day of the month (index 0 is the 1st).
  final List<int> perDay;

  /// Doses by weekday, Monday first.
  final List<int> weekdayDoses;

  /// Most used first.
  final List<SubstanceUsage> bySubstance;
  final int previousDoses;
  final int previousDaysWithUse;

  int get daysInMonth => perDay.length;
  int get change => doses - previousDoses;
  int get dayChange => daysWithUse - previousDaysWithUse;
  int? get busiestWeekday {
    var best = -1;
    var index = 0;
    for (var i = 0; i < 7; i++) {
      if (weekdayDoses[i] > best) {
        best = weekdayDoses[i];
        index = i;
      }
    }
    return best <= 0 ? null : index;
  }
}

/// Summarises [entries] (ONE person's) for the calendar month [year]-[month], with the month
/// before it for comparison.
MonthSummary monthSummary(List<UsageEntry> entries, int year, int month) {
  final daysIn = DateTime(year, month + 1, 0).day;
  final prev = DateTime(year, month - 1, 1);

  bool inMonth(DateTime t, int y, int m) => t.year == y && t.month == m;

  final perDay = List.filled(daysIn, 0);
  final weekday = List.filled(7, 0);
  final grouped = <String, List<UsageEntry>>{};
  var previousDoses = 0;
  final previousDays = <int>{};
  for (final e in entries) {
    if (inMonth(e.time, year, month)) {
      perDay[e.time.day - 1]++;
      weekday[e.time.weekday - 1]++;
      grouped.putIfAbsent(e.substanceKey, () => []).add(e);
    } else if (inMonth(e.time, prev.year, prev.month)) {
      previousDoses++;
      previousDays.add(e.time.day);
    }
  }

  final usage = <SubstanceUsage>[];
  for (final entry in grouped.entries) {
    final list = entry.value;
    final known = [for (final e in list) if (e.dose != null) e];
    final units = {for (final e in known) e.unit};
    usage.add(SubstanceUsage(
      key: entry.key,
      doses: list.length,
      days: {for (final e in list) e.time.day}.length,
      totalDose: known.isNotEmpty && units.length == 1 ? known.fold<double>(0, (s, e) => s + e.dose!) : null,
      unit: units.length == 1 ? units.single : null,
      unknownDoses: list.length - known.length,
    ));
  }
  usage.sort((a, b) => b.doses != a.doses ? b.doses.compareTo(a.doses) : a.key.compareTo(b.key));

  return MonthSummary(
    year: year,
    month: month,
    doses: perDay.fold(0, (s, n) => s + n),
    daysWithUse: perDay.where((n) => n > 0).length,
    perDay: perDay,
    weekdayDoses: weekday,
    bySubstance: usage,
    previousDoses: previousDoses,
    previousDaysWithUse: previousDays.length,
  );
}
