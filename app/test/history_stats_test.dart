import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/history_stats.dart';

import 'helpers.dart';

void main() {
  testWidgets('history: lifetime figures, records, patterns, gains and the break plan', (tester) async {
    final app = await buildTestApp(tester);
    final day1 = DateTime(testNow.year, testNow.month, testNow.day - 10, 20);
    final rows = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e1 = await app.db.addExperience(personId: me.id, sortDate: day1);
      for (var n = 0; n < 3; n++) {
        await app.db.addIngestion(experience: e1, substanceKey: 'cannabis', route: 'smoked', time: day1.add(Duration(minutes: 30 * n)), dose: 2.7, unit: 'mg');
      }
      await app.db.addIngestion(
        experience: e1,
        substanceKey: 'alcohol',
        route: 'oral',
        time: day1.add(const Duration(minutes: 10)),
        dose: 28,
        unit: 'g',
        details: {'drink': 'Two beers', 'volume': 24.0, 'volumeUnit': 'oz', 'abv': 5.0},
      );
      // A second experience the same night: the rolling 24 hours spans both.
      final e2 = await app.db.addExperience(personId: me.id, sortDate: day1.add(const Duration(hours: 3)));
      await app.db.addIngestion(experience: e2, substanceKey: 'cannabis', route: 'smoked', time: day1.add(const Duration(hours: 3)), dose: 5, unit: 'mg');
      // Four days later, an edible.
      final day5 = day1.add(const Duration(days: 4));
      final e3 = await app.db.addExperience(personId: me.id, sortDate: day5);
      await app.db.addIngestion(experience: e3, substanceKey: 'cannabis', route: 'oral', time: day5, dose: 10, unit: 'mg');
      return app.db.ingestionsForPerson(me.id);
    });

    const settings = EstimateSettings();
    final histories = buildHistories(ingestions: rows, byKey: app.reference.byKey, settings: settings, now: testNow);
    final cannabis = histories.firstWhere((h) => h.key == 'cannabis');
    expect(histories.first.key, 'cannabis'); // most used first

    expect(cannabis.doses, 5);
    expect(cannabis.mainUnit, 'mg');
    expect(cannabis.totalByUnit['mg'], closeTo(23.1, 1e-9));
    expect(cannabis.daysUsed, 2);
    expect(cannabis.longestBreakDays, 3);
    expect(cannabis.experiences, 3);
    expect(cannabis.largestByRoute.keys, containsAll(['smoked', 'oral']));
    expect(cannabis.largestByRoute['smoked']!.amount, 5);
    expect(cannabis.largestSession!.amount, closeTo(10, 1e-9));
    expect(cannabis.most24h!.amount, closeTo(13.1, 1e-9));
    expect(cannabis.highestPeak!.amount, greaterThan(0));
    expect(cannabis.sessionTotals, hasLength(3));
    expect(cannabis.byHour[20], 3);
    expect(cannabis.routes['smoked'], 4);
    expect(cannabis.combos.single.key, 'Alcohol');
    expect(cannabis.gains, hasLength(3));
    expect(cannabis.gains.first.start, day1.add(const Duration(days: 4))); // newest first
    final evening = cannabis.gains.firstWhere((g) => g.start == day1);
    expect(evening.after, greaterThan(evening.before));

    final alcohol = histories.firstWhere((h) => h.key == 'alcohol');
    expect(alcohol.mainUnit, 'std drinks');
    expect(alcohol.totalByUnit['std drinks'], closeTo(2, 1e-9));
    expect(alcohol.peakUnit, '% BAC');
    expect(alcohol.highestPeak!.amount, greaterThan(0.01));
    expect(alcohol.gains.single.alcohol, isTrue);
    expect(alcohol.gains.single.multiplierAfter, greaterThanOrEqualTo(alcohol.gains.single.multiplierBefore));

    // Tolerance over time with the break plan, in each substance's own units.
    final view = toleranceView(
      substance: app.reference.byKey['cannabis']!,
      ingestions: rows,
      byKey: app.reference.byKey,
      settings: settings,
      from: day1.subtract(const Duration(days: 1)),
      to: testNow.add(const Duration(days: 14)),
      now: testNow,
    );
    expect(view.alcohol, isFalse);
    expect(view.points, isNotEmpty);
    expect(view.now, greaterThan(0));
    expect(view.plan.half!.isAfter(testNow), isTrue);
    expect(view.plan.quarter!.isAfter(view.plan.half!), isTrue);

    final alcoholView = toleranceView(
      substance: app.reference.byKey['alcohol']!,
      ingestions: rows,
      byKey: app.reference.byKey,
      settings: settings,
      from: day1,
      to: testNow,
      now: testNow,
    );
    expect(alcoholView.alcohol, isTrue);
    expect(alcoholView.multiplierNow, greaterThanOrEqualTo(1.0));
    expect(alcoholView.word, endsWith('x'));
    await disposeApp(tester, app);
  });
}
