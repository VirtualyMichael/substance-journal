import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 7, 10, 22);
  DateTime day(int back) => DateTime(2026, 7, 10 - back);

  test('limits round-trip and ignore junk', () {
    const limits = DrinkLimits(daily: 4, weekly: 14, maxDrinkingDays: 5);
    final back = DrinkLimits.decode(limits.encode());
    expect(back.daily, 4);
    expect(back.weekly, 14);
    expect(back.maxDrinkingDays, 5);
    expect(DrinkLimits.decode('nonsense').hasAny, isFalse);
    expect(DrinkLimits.decode(null).hasAny, isFalse);
    expect(DrinkLimits.decode('{"daily": -3, "maxDrinkingDays": 12}').hasAny, isFalse);
  });

  test('status counts today, the last seven days and the days with drinks', () {
    final status = limitStatus(
      limits: const DrinkLimits(daily: 4, weekly: 14, maxDrinkingDays: 3),
      standardByDay: {day(0): 3, day(1): 2, day(3): 5, day(6): 1, day(7): 9}, // day 7 is outside the window
      now: now,
    );
    expect(status.today, 3);
    expect(status.week, 11);
    expect(status.drinkingDays, 4);
    expect(status.overDaily, isFalse);
    expect(status.overWeekly, isFalse);
    expect(status.overDays, isTrue);
    expect(status.warning, contains('drinking days'));
    expect(status.roomToday, 1); // the daily limit is the nearer one
    expect(status.lines, ['Today 3 of 4 standard drinks', 'Last 7 days 11 of 14', 'Drinking days this week 4 of 3']);
  });

  test('over the daily and weekly limits', () {
    final daily = limitStatus(limits: const DrinkLimits(daily: 2), standardByDay: {day(0): 3.5}, now: now);
    expect(daily.overDaily, isTrue);
    expect(daily.warning, 'Over your daily limit by 1.5 standard drinks.');
    expect(daily.roomToday, 0);
    final weekly = limitStatus(limits: const DrinkLimits(weekly: 10), standardByDay: {day(0): 6, day(2): 6}, now: now);
    expect(weekly.overWeekly, isTrue);
    expect(weekly.overDaily, isFalse);
  });

  test('exactly at a limit is not over it, and no limits means no lines', () {
    expect(limitStatus(limits: const DrinkLimits(daily: 4), standardByDay: {day(0): 4}, now: now).anyOver, isFalse);
    final none = limitStatus(limits: const DrinkLimits(), standardByDay: {day(0): 10}, now: now);
    expect(none.lines, isEmpty);
    expect(none.warning, isNull);
    expect(none.roomToday, isNull);
  });
}
