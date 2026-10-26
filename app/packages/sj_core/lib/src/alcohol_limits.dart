import 'dart:convert';

/// Drinking limits a person sets for themselves, in standard drinks.
class DrinkLimits {
  const DrinkLimits({this.daily, this.weekly, this.maxDrinkingDays});

  /// Most standard drinks in a day, or null for no limit.
  final double? daily;

  /// Most standard drinks in any 7 days (this day and the six before it).
  final double? weekly;

  /// Most days with any drinking in those 7 days (so the rest are alcohol-free).
  final int? maxDrinkingDays;

  bool get hasAny => daily != null || weekly != null || maxDrinkingDays != null;

  Map<String, Object?> toJson() => {'daily': daily, 'weekly': weekly, 'maxDrinkingDays': maxDrinkingDays};

  String encode() => jsonEncode(toJson());

  static DrinkLimits decode(String? text) {
    if (text == null || text.isEmpty) return const DrinkLimits();
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      double? positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;
      final days = json['maxDrinkingDays'];
      return DrinkLimits(
        daily: positive(json['daily']),
        weekly: positive(json['weekly']),
        maxDrinkingDays: days is num && days >= 0 && days <= 7 ? days.toInt() : null,
      );
    } on Object {
      return const DrinkLimits();
    }
  }
}

/// How today and the last week compare with the limits.
class LimitStatus {
  const LimitStatus({required this.limits, required this.today, required this.week, required this.drinkingDays});

  final DrinkLimits limits;
  final double today;
  final double week;
  final int drinkingDays;

  bool get overDaily => limits.daily != null && today > limits.daily! + 1e-9;
  bool get overWeekly => limits.weekly != null && week > limits.weekly! + 1e-9;
  bool get overDays => limits.maxDrinkingDays != null && drinkingDays > limits.maxDrinkingDays!;
  bool get anyOver => overDaily || overWeekly || overDays;

  /// Standard drinks left today before the daily or weekly limit, whichever is first.
  double? get roomToday {
    final left = <double>[
      if (limits.daily != null) limits.daily! - today,
      if (limits.weekly != null) limits.weekly! - week,
    ];
    if (left.isEmpty) return null;
    final least = left.reduce((a, b) => a < b ? a : b);
    return least < 0 ? 0 : least;
  }

  String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// One line per limit that is set, e.g. "Today 3 of 4 standard drinks".
  List<String> get lines => [
        if (limits.daily != null) 'Today ${_n(today)} of ${_n(limits.daily!)} standard drinks',
        if (limits.weekly != null) 'Last 7 days ${_n(week)} of ${_n(limits.weekly!)}',
        if (limits.maxDrinkingDays != null) 'Drinking days this week $drinkingDays of ${limits.maxDrinkingDays}',
      ];

  /// What to say when a limit is passed, or null.
  String? get warning {
    if (overDaily) return 'Over your daily limit by ${_n(today - limits.daily!)} standard drinks.';
    if (overWeekly) return 'Over your weekly limit by ${_n(week - limits.weekly!)} standard drinks.';
    if (overDays) return 'That is more drinking days this week than you aimed for (${limits.maxDrinkingDays}).';
    return null;
  }
}

/// [standardByDay] maps a calendar day to the standard drinks logged on it.
LimitStatus limitStatus({required DrinkLimits limits, required Map<DateTime, double> standardByDay, required DateTime now}) {
  final today = DateTime(now.year, now.month, now.day);
  final todayTotal = standardByDay[today] ?? 0;
  var week = 0.0;
  var days = 0;
  for (var back = 0; back < 7; back++) {
    final day = DateTime(today.year, today.month, today.day - back);
    final total = standardByDay[day] ?? 0;
    week += total;
    if (total > 0) days++;
  }
  return LimitStatus(limits: limits, today: todayTotal, week: week, drinkingDays: days);
}
