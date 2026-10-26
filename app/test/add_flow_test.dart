import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('a new journal is empty and offers to add the first ingestion', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    expect(find.text("Me's journal is empty"), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-add')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('logging LSD end to end: search, dose, save, then the experience opens', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);

    await tapKey(tester, 'journal-add');
    expect(find.text('Choose a compound'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'acid'); // an alias for LSD
    await settle(tester, rounds: 2);
    expect(find.byKey(const ValueKey('compound-lsd')), findsOneWidget);
    expect(find.byKey(const ValueKey('compound-mdma')), findsNothing);
    await tapKey(tester, 'compound-lsd'); // LSD has one route, so the route step is skipped

    expect(find.text('LSD dose'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('dose-field')), '100');
    await settle(tester, rounds: 2);
    expect(find.text('About a common dose'), findsOneWidget);

    await tapKey(tester, 'primary-action'); // Next
    expect(find.text('When'), findsOneWidget);
    await tapKey(tester, 'primary-action'); // Save

    // The new experience is open and shows the ingestion.
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.textContaining('100 µg'), findsWidgets);
    expect(find.text('Common'), findsOneWidget);

    final person = (await dbRun(tester, app.db.activePeople)).single;
    final rows = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    expect(rows, hasLength(1));
    expect(rows.single.substanceKey, 'lsd');
    expect(rows.single.dose, 100);
    expect(rows.single.time, testNow);
    await disposeApp(tester, app);
  });

  testWidgets('the dose step rejects an empty dose but accepts "unknown"', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-lsd');

    await tapKey(tester, 'primary-action');
    expect(find.byKey(const ValueKey('error')), findsOneWidget);
    expect(find.text('When'), findsNothing);

    await tapKey(tester, 'unknown-dose');
    await tapKey(tester, 'primary-action');
    expect(find.text('When'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('cannabis shows an absorbed-dose estimate as a range and stores it', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-cannabis');
    await tapKey(tester, 'route-smoked');

    await tester.enterText(find.byKey(const ValueKey('cannabis-grams')), '0.1');
    await tester.enterText(find.byKey(const ValueKey('cannabis-thc')), '15');
    await settle(tester, rounds: 2);
    expect(find.text('THC consumed: 15.0 mg'), findsOneWidget);
    expect(find.textContaining('Estimated absorbed: 1.2 to 4.5 mg'), findsOneWidget);
    expect(find.text('Between a light and a strong dose'), findsOneWidget);

    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');

    final person = (await dbRun(tester, app.db.activePeople)).single;
    final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
    expect(row.substanceKey, 'cannabis');
    expect(row.route, 'smoked');
    expect(row.method, 'joint');
    expect(row.absorbedMg, closeTo(2.7, 1e-9));
    expect(row.dose, closeTo(2.7, 1e-9));
    expect(row.detailsJson, contains('"productThcMg":15.0'));
    await disposeApp(tester, app);
  });

  testWidgets('cannabis edibles use the label mg directly', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-cannabis');
    await tapKey(tester, 'route-oral');
    expect(find.byKey(const ValueKey('cannabis-label-mg')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('cannabis-label-mg')), '10');
    await settle(tester, rounds: 2);
    expect(find.text('About a strong dose'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('alcohol drink calculator turns volume and ABV into grams of ethanol', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-alcohol');

    await tester.enterText(find.byKey(const ValueKey('drink-volume')), '12');
    await tester.enterText(find.byKey(const ValueKey('drink-abv')), '5');
    await settle(tester, rounds: 2);
    // 12 oz = 354.9 ml; x 5% x 0.789 = 14.0 g, one US standard drink.
    expect(find.textContaining('14.0 g ethanol'), findsOneWidget);
    await tapKey(tester, 'use-grams');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('dose-field'))).controller!.text, '14.0');
    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');

    final person = (await dbRun(tester, app.db.activePeople)).single;
    final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
    expect(row.unit, 'g');
    expect(row.dose, closeTo(14.0, 0.1));
    await disposeApp(tester, app);
  });

  testWidgets('interaction warning blocks Next until acknowledged', (tester) async {
    final app = await buildTestApp(tester);
    // Seed before the app starts: direct queries made while its streams are mid-flight can wait on the fake clock.
    final person = await dbRun(tester, app.db.ensureDefaultPerson);
    final exp = await dbRun(tester, () => app.db.addExperience(personId: person.id, sortDate: testNow));
    await dbRun(
      tester,
      () => app.db.addIngestion(
        experience: exp,
        substanceKey: 'alcohol',
        route: 'oral',
        time: testNow.subtract(const Duration(hours: 1)),
        dose: 20,
        unit: 'g',
      ),
    );
    await startApp(tester, app);

    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-ketamine');
    await tapKey(tester, 'route-insufflated');

    expect(find.text('Combinations'), findsOneWidget);
    expect(find.textContaining('Dangerous: Ketamine + Alcohol'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('primary-action'))).onPressed, isNull);

    await tapKey(tester, 'acknowledge');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('primary-action'))).onPressed, isNotNull);
    await tapKey(tester, 'primary-action');
    expect(find.text('Ketamine dose'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets("another person's alcohol never triggers a warning for me", (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final bob = await dbRun(tester, () => app.db.addPerson('Bob'));
    final bobExp = await dbRun(tester, () => app.db.addExperience(personId: bob.id, sortDate: testNow));
    await dbRun(
      tester,
      () => app.db.addIngestion(
        experience: bobExp,
        substanceKey: 'alcohol',
        route: 'oral',
        time: testNow.subtract(const Duration(hours: 1)),
        dose: 20,
        unit: 'g',
      ),
    );
    await startApp(tester, app);
    expect(me.id, isNot(bob.id));
    expect(find.text("Me's journal is empty"), findsOneWidget); // Bob's drink is not in my journal

    // I am "Me": ketamine goes straight to the dose step, with no combination warning.
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-ketamine');
    await tapKey(tester, 'route-insufflated');
    expect(find.text('Combinations'), findsNothing);
    expect(find.text('Ketamine dose'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('a new ingestion joins a recent experience by default and can be sent to a new one', (tester) async {
    final app = await buildTestApp(tester);
    final person = await dbRun(tester, app.db.ensureDefaultPerson);
    final exp = await dbRun(tester, () => app.db.addExperience(personId: person.id, sortDate: testNow));
    await dbRun(
      tester,
      () => app.db.addIngestion(
        experience: exp,
        substanceKey: 'mdma',
        route: 'oral',
        time: testNow.subtract(const Duration(hours: 2)),
        dose: 100,
        unit: 'mg',
      ),
    );
    await startApp(tester, app);

    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-nicotine');
    await tapKey(tester, 'route-buccal');
    await tester.enterText(find.byKey(const ValueKey('dose-field')), '2');
    await settle(tester, rounds: 2);
    await tapKey(tester, 'primary-action');
    await settle(tester);
    await tapKey(tester, 'primary-action'); // save into the suggested (recent) experience

    final all = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    expect(all, hasLength(2));
    expect(all.map((i) => i.experienceId).toSet(), {exp.id});
    await disposeApp(tester, app);
  });
}
