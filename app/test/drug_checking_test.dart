import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/testing/testing_page.dart';

import 'helpers.dart';

void main() {
  Future<TestApp> logPage(WidgetTester tester, {String? compound, Future<void> Function(TestApp)? seed}) async {
    final built = await buildTestApp(tester);
    if (seed != null) await dbRun(tester, () => seed(built));
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
        clockProvider.overrideWithValue(() => testNow),
      ],
      child: MaterialApp(home: TestingPage(substanceKey: compound)),
    ));
    await settle(tester);
    return built;
  }

  testWidgets('logging a reagent test that did not match flags the sample, and removing it clears the flag', (tester) async {
    final app = await logPage(tester, compound: 'mdma');
    expect(find.textContaining('No samples yet'), findsOneWidget);
    expect(find.textContaining('never proof of safety'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-https://dancesafe.org/testing-kit-instructions/')), findsOneWidget);

    await tapKey(tester, 'add-test');
    await tapKey(tester, 'test-save');
    expect(find.textContaining('Give the sample a name'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sample-name')), 'Pink pill');
    await tapKey(tester, 'test-save');
    expect(find.text('Choose how it compared with the chart.'), findsOneWidget);
    expect(find.byKey(const ValueKey('suggested-tests')), findsOneWidget);

    await tapKey(tester, 'initial-Yellow');
    await tapKey(tester, 'final-Purple');
    await tapKey(tester, 'outcome-unmatched');
    await tapKey(tester, 'test-save');
    await settle(tester, rounds: 8);

    expect(find.text('Pink pill'), findsOneWidget);
    expect(find.text('A test did not match or was positive'), findsOneWidget);
    expect(find.text('Marquis: yellow, then purple (did not match)'), findsOneWidget);
    expect(find.textContaining('Do not take it unless you know why'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester);
    expect(find.text('Not tested'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('A test did not match or was positive'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('a strip has its own outcomes, no colours, and a negative still says it proves nothing', (tester) async {
    late final String sampleId;
    final app = await logPage(tester, compound: 'mdma', seed: (a) async => sampleId = (await a.db.addProduct(substanceKey: 'mdma', name: 'Powder')).id);
    await tapKey(tester, 'add-test-$sampleId');
    await tester.tap(find.byKey(const ValueKey('test-reagent')));
    await settle(tester);
    await tester.tap(find.text('Fentanyl strip').last);
    await settle(tester);
    expect(find.byKey(const ValueKey('initial-Yellow')), findsNothing);
    expect(find.byKey(const ValueKey('outcome-matched')), findsNothing);
    await tapKey(tester, 'outcome-negative');
    await tapKey(tester, 'test-save');
    await settle(tester, rounds: 8);

    expect(find.text('Tested, nothing unexpected seen'), findsOneWidget);
    expect(find.text('Fentanyl strip: negative'), findsOneWidget);
    expect(find.textContaining('presumptive only'), findsOneWidget);
    expect(find.textContaining('safe'), findsWidgets); // only in the "never proof of safety" wording
    expect(find.text('Tested, safe'), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('choosing a flagged sample in the dose step warns, and the dose remembers the sample', (tester) async {
    final app = await buildTestApp(tester);
    final sample = await dbRun(tester, () => app.db.addProduct(substanceKey: 'mdma', name: 'Pink pill'));
    await dbRun(tester, () => app.db.addReagentTest(
          productId: sample.id,
          substanceKey: 'mdma',
          testedAt: testNow,
          kind: 'strip',
          reagent: 'Fentanyl strip',
          outcome: 'positive',
        ));
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-mdma');
    expect(find.byKey(const ValueKey('dose-sample-status')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dose-sample-pick')));
    await settle(tester);
    await tester.tap(find.text('Pink pill  (flagged)').last);
    await settle(tester);
    expect(find.textContaining('Do not take it unless you know why'), findsOneWidget);
    expect(find.text('Fentanyl strip: positive'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('dose-field')), '100');
    await settle(tester, rounds: 2);
    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');
    final person = (await dbRun(tester, app.db.activePeople)).single;
    final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
    expect(row.productId, sample.id);
    expect(row.detailsJson, contains('"sample":"Pink pill"'));
    await disposeApp(tester, app);
  });

  testWidgets('everyday products get no testing prompt, but other compounds offer to test', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-nicotine');
    expect(find.byKey(const ValueKey('dose-test-sample')), findsNothing);
    await tester.pageBack();
    await settle(tester);
    await disposeApp(tester, app);
  });
}
