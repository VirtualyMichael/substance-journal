import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

void main() {
  Future<Person> seedLsd(WidgetTester tester, TestApp app, Duration ago) async {
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await dbRun(tester, () async {
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(ago));
      await app.db.addIngestion(
        experience: e,
        substanceKey: 'lsd',
        route: 'sublingual',
        time: testNow.subtract(ago),
        dose: 100,
        unit: 'µg',
      );
    });
    return me;
  }

  Future<void> openLsdDose(WidgetTester tester) async {
    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('compound-lsd')));
    await settle(tester);
    await tapKey(tester, 'log-this');
  }

  testWidgets('the dose step warns about a heavy dose as you type, and never blocks saving', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    await openLsdDose(tester);

    await tester.enterText(find.byKey(const ValueKey('dose-field')), '100');
    await settle(tester, rounds: 2);
    expect(find.byKey(const ValueKey('advisories')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('dose-field')), '600');
    await settle(tester, rounds: 2);
    expect(find.text('Heavy dose'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('primary-action'))).onPressed, isNotNull);
    await disposeApp(tester, app);
  });

  testWidgets('a repeat dose shortly after the last one is flagged, with tolerance noted', (tester) async {
    final app = await buildTestApp(tester);
    await seedLsd(tester, app, const Duration(minutes: 30));
    await startApp(tester, app);
    await openLsdDose(tester);
    await tester.enterText(find.byKey(const ValueKey('dose-field')), '100');
    await settle(tester, rounds: 2);
    expect(find.textContaining('Still active from 30 min ago'), findsOneWidget);
    expect(find.text('Tolerance is up'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('tolerance page shows the pooled track with a return-to-baseline date', (tester) async {
    final app = await buildTestApp(tester);
    await seedLsd(tester, app, const Duration(days: 1));
    await startApp(tester, app);
    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await tapKey(tester, 'open-tolerance');
    expect(find.text('Psychedelics'), findsWidgets);
    expect(find.textContaining('Back to baseline around'), findsOneWidget);
    expect(find.byKey(const ValueKey('no-tolerance')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('tolerance page is empty when nothing recent builds tolerance', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await tapKey(tester, 'open-tolerance');
    expect(find.byKey(const ValueKey('no-tolerance')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('audited compounds carry a badge and an audited-only filter', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    await tester.tap(find.text('Compounds'));
    await settle(tester);
    expect(find.byIcon(Icons.verified_outlined), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('audited-only')));
    await settle(tester);
    expect(find.byKey(const ValueKey('compound-lsd')), findsOneWidget); // the test data is all audited
    await disposeApp(tester, app);
  });
}
