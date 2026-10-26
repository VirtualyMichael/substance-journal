import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

void main() {
  // testNow is 2026-07-03 21:00, so "this month" is July 2026.
  Future<void> dose(WidgetTester tester, TestApp app, Person who, String substance, DateTime at, {double? dose, String? unit}) async {
    await dbRun(tester, () async {
      final e = await app.db.addExperience(personId: who.id, sortDate: at);
      await app.db.addIngestion(experience: e, substanceKey: substance, route: 'oral', time: at, dose: dose, unit: unit);
    });
  }

  Future<void> openInsights(WidgetTester tester) async {
    await tester.tap(find.text('Insights'));
    await settle(tester);
  }

  testWidgets('shows the month, totals and per-substance rows for this person only', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final alex = await dbRun(tester, () => app.db.addPerson('Alex'));
    await dose(tester, app, me, 'lsd', DateTime(2026, 7, 1, 20), dose: 100, unit: 'µg');
    await dose(tester, app, me, 'mdma', DateTime(2026, 7, 2, 20), dose: 80, unit: 'mg');
    await dose(tester, app, me, 'mdma', DateTime(2026, 7, 2, 23), dose: 40, unit: 'mg');
    await dose(tester, app, me, 'lsd', DateTime(2026, 6, 10, 20), dose: 100, unit: 'µg');
    await dose(tester, app, alex, 'ketamine', DateTime(2026, 7, 1, 20), dose: 30, unit: 'mg'); // someone else's
    await startApp(tester, app);
    await openInsights(tester);

    expect(find.text('July 2026'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('stat-doses'))).data, '3');
    expect(find.textContaining('+2 vs last month'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('stat-days'))).data, '2 of 31');
    expect(find.byKey(const ValueKey('insights-mdma')), findsOneWidget);
    expect(find.textContaining('2 doses on 1 day'), findsOneWidget);
    expect(find.textContaining('120 mg in total'), findsOneWidget);
    expect(find.byKey(const ValueKey('insights-ketamine')), findsNothing); // Alex's use is not mine
    await disposeApp(tester, app);
  });

  testWidgets('month navigation, an empty month, and no future months', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await dose(tester, app, me, 'lsd', DateTime(2026, 6, 10, 20), dose: 100, unit: 'µg');
    await startApp(tester, app);
    await openInsights(tester);

    expect(find.byKey(const ValueKey('insights-empty')), findsOneWidget);
    expect(find.textContaining('1 the month before'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('insights-next'))).onPressed, isNull);

    await tapKey(tester, 'insights-prev');
    expect(find.text('June 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('insights-lsd')), findsOneWidget);
    await tapKey(tester, 'insights-next');
    expect(find.text('July 2026'), findsOneWidget);
    await disposeApp(tester, app);
  });
}
