import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

void main() {
  Future<(TestApp, Person)> alcoholApp(WidgetTester tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await dbRun(tester, app.db.ensureDefaultDrinkPresets);
    await dbRun(tester, () => app.db.setSetting('alcoholMode', 'true'));
    return (app, me);
  }

  testWidgets('limits are saved per person and shown on Today with progress', (tester) async {
    final (app, me) = await alcoholApp(tester);
    await dbRun(tester, () => app.db.setLimits(me.id, const DrinkLimits(daily: 4, weekly: 14)));
    await dbRun(tester, () => app.db.logDrink(personId: me.id, at: testNow.subtract(const Duration(hours: 1)), volume: 12, volumeUnit: 'oz', abvPercent: 5));
    await startApp(tester, app);
    expect(find.byKey(const ValueKey('limits-status')), findsOneWidget);
    expect(find.textContaining('of 4 standard drinks'), findsOneWidget);
    expect(find.textContaining('Last 7 days'), findsOneWidget);
    expect(find.byKey(const ValueKey('limit-warning')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('no limits set: no limits block', (tester) async {
    final (app, _) = await alcoholApp(tester);
    await startApp(tester, app);
    expect(find.byKey(const ValueKey('limits-status')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('going over the daily limit is shown, and quick add says so', (tester) async {
    final (app, me) = await alcoholApp(tester);
    await dbRun(tester, () => app.db.setLimits(me.id, const DrinkLimits(daily: 1)));
    await dbRun(tester, () => app.db.logDrink(personId: me.id, at: testNow.subtract(const Duration(minutes: 30)), volume: 12, volumeUnit: 'oz', abvPercent: 5));
    await startApp(tester, app);
    expect(find.byKey(const ValueKey('limit-warning')), findsNothing); // 0.9 of 1

    await tapKey(tester, 'quick-add-selected');
    expect(find.textContaining('Over your daily limit'), findsWidgets);
    expect(find.byKey(const ValueKey('limit-warning')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('settings form saves, validates and keeps people apart', (tester) async {
    final (app, me) = await alcoholApp(tester);
    final other = await dbRun(tester, () => app.db.addPerson('Alex'));
    await startApp(tester, app);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    final daily = find.byKey(const ValueKey('limit-daily'));
    await tester.scrollUntilVisible(daily, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(daily);
    await tester.pumpAndSettle();

    await tester.enterText(daily, 'abc');
    await tapKey(tester, 'limits-save');
    expect(find.textContaining('must be positive numbers'), findsOneWidget);
    expect((await dbRun(tester, () => app.db.getLimits(me.id))).hasAny, isFalse);

    await tester.enterText(daily, '3');
    await tester.enterText(find.byKey(const ValueKey('limit-days')), '5');
    await tapKey(tester, 'limits-save');
    expect(find.text('Saved'), findsOneWidget);
    final saved = await dbRun(tester, () => app.db.getLimits(me.id));
    expect(saved.daily, 3);
    expect(saved.maxDrinkingDays, 5);
    expect((await dbRun(tester, () => app.db.getLimits(other.id))).hasAny, isFalse); // another person is untouched
    await disposeApp(tester, app);
  });
}
