import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  UsageEntry e(String key, DateTime t, {double? dose, String? unit}) => UsageEntry(substanceKey: key, time: t, dose: dose, unit: unit);

  final entries = [
    e('lsd', DateTime(2026, 7, 4, 20), dose: 100, unit: 'µg'),
    e('lsd', DateTime(2026, 7, 18, 20), dose: 80, unit: 'µg'),
    e('cannabis', DateTime(2026, 7, 4, 22), dose: 5, unit: 'mg'),
    e('cannabis', DateTime(2026, 7, 5, 22), dose: 4, unit: 'mg'),
    e('cannabis', DateTime(2026, 7, 5, 23)),
    e('mdma', DateTime(2026, 7, 5, 23), dose: 80, unit: 'mg'),
    e('lsd', DateTime(2026, 6, 10), dose: 100, unit: 'µg'),
    e('lsd', DateTime(2026, 6, 11), dose: 100, unit: 'µg'),
    e('lsd', DateTime(2026, 5, 1), dose: 100, unit: 'µg'), // two months back: ignored
  ];

  test('counts doses, days with use and per-day doses for the month', () {
    final s = monthSummary(entries, 2026, 7);
    expect(s.doses, 6);
    expect(s.daysWithUse, 3); // the 4th, 5th and 18th
    expect(s.daysInMonth, 31);
    expect(s.perDay[3], 2);
    expect(s.perDay[4], 3);
    expect(s.perDay[17], 1);
    expect(s.perDay.fold(0, (a, b) => a + b), 6);
  });

  test('per-substance totals, days and unknown doses; most used first', () {
    final s = monthSummary(entries, 2026, 7);
    expect(s.bySubstance.map((u) => u.key), ['cannabis', 'lsd', 'mdma']); // 3, 2, 1
    final cannabis = s.bySubstance.first;
    expect(cannabis.doses, 3);
    expect(cannabis.days, 2);
    expect(cannabis.totalDose, 9);
    expect(cannabis.unit, 'mg');
    expect(cannabis.unknownDoses, 1);
    expect(s.bySubstance[1].totalDose, 180);
  });

  test('compares with the previous month, including across a year boundary', () {
    final s = monthSummary(entries, 2026, 7);
    expect(s.previousDoses, 2);
    expect(s.previousDaysWithUse, 2);
    expect(s.change, 4);
    expect(s.dayChange, 1);
    final jan = monthSummary([e('lsd', DateTime(2025, 12, 31)), e('lsd', DateTime(2026, 1, 2))], 2026, 1);
    expect(jan.previousDoses, 1);
    expect(jan.doses, 1);
  });

  test('weekday pattern and busiest weekday', () {
    final s = monthSummary(entries, 2026, 7); // July 4 2026 is a Saturday
    expect(s.weekdayDoses[5], 3); // Saturdays: two on the 4th, one on the 18th
    expect(s.weekdayDoses[6], 3); // Sunday the 5th
    expect(s.weekdayDoses.reduce((a, b) => a + b), 6);
    expect(s.busiestWeekday, 5); // a tie goes to the earlier weekday
    expect(monthSummary(const [], 2026, 7).busiestWeekday, isNull);
  });

  test('mixed units give no total, an empty month is all zeros', () {
    final s = monthSummary([e('x', DateTime(2026, 7, 1), dose: 1, unit: 'mg'), e('x', DateTime(2026, 7, 2), dose: 1, unit: 'g')], 2026, 7);
    expect(s.bySubstance.single.totalDose, isNull);
    final empty = monthSummary(const [], 2026, 2);
    expect(empty.daysInMonth, 28);
    expect(empty.doses, 0);
    expect(empty.bySubstance, isEmpty);
  });
}
