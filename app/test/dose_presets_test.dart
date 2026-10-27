import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/ui/add/dose_presets.dart';

import 'helpers.dart';

void main() {
  test('low, medium and high are the middle of the light, common and strong ranges; cannabis has none', () {
    final ref = loadReference();
    final lsd = ref.byKey['lsd']!.roas.first;
    final presets = builtInPresets(lsd);
    expect(presets.map((p) => p.label), ['Low', 'Medium', 'High']);
    double mid(double? a, double? b) => roundDose((a! + b!) / 2);
    expect(presets[0].amount, mid(lsd.doseLight!.min, lsd.doseLight!.max));
    expect(presets[1].amount, mid(lsd.doseCommon!.min, lsd.doseCommon!.max));
    expect(presets[2].amount, mid(lsd.doseStrong!.min, lsd.doseStrong!.max));
    expect(presets[0].amount, lessThan(presets[1].amount));
    expect(presets[1].amount, lessThan(presets[2].amount));
    expect(builtInPresets(ref.byKey['cannabis']!.roas.first), isEmpty);
    final mushrooms = builtInPresets(ref.byKey['psilocybin_mushrooms']!.roas.first);
    expect(mushrooms.map((p) => p.amount), [0.63, 1.8, 3.8]); // grams of dried mushrooms
  });

  testWidgets('tapping Medium fills the dose, and the entry saves that dose', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    final lsd = app.reference.byKey['lsd']!.roas.first;
    final medium = builtInPresets(lsd)[1].amount;
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-lsd');
    await tapKey(tester, 'preset-medium');
    expect(find.text(medium.toString().replaceFirst(RegExp(r'\.0$'), '')), findsWidgets);

    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');
    final person = (await dbRun(tester, app.db.activePeople)).single;
    final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
    expect(row.dose, medium);
    await disposeApp(tester, app);
  });

  testWidgets('a custom preset is saved from the dose step, offered next time, and can be removed with undo', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-lsd');
    expect(find.byKey(const ValueKey('save-preset')), findsNothing); // nothing to save yet

    await tester.enterText(find.byKey(const ValueKey('dose-field')), '80');
    await settle(tester, rounds: 2);
    await tapKey(tester, 'save-preset');
    await tester.enterText(find.byKey(const ValueKey('preset-name')), 'Usual tab');
    await tapKey(tester, 'preset-save');
    expect(find.text('Usual tab'), findsOneWidget);

    // Change the dose, then use the preset to put it back.
    await tester.enterText(find.byKey(const ValueKey('dose-field')), '20');
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Usual tab'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '80'), findsOneWidget);

    // Remove it, then bring it back.
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(find.text('Usual tab'), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Usual tab'), findsOneWidget);

    final rows = await dbRun(tester, () => app.db.watchDosePresets('lsd', 'sublingual').first);
    expect(rows.map((p) => p.name), ['Usual tab']);
    await disposeApp(tester, app);
  });

  testWidgets('a cannabis preset remembers the whole calculator', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-cannabis');
    await tapKey(tester, 'route-smoked');
    expect(find.byKey(const ValueKey('preset-low')), findsNothing); // no ready-made bands for cannabis

    await tester.enterText(find.byKey(const ValueKey('cannabis-grams')), '0.2');
    await tester.enterText(find.byKey(const ValueKey('cannabis-thc')), '18');
    await settle(tester, rounds: 2);
    await tapKey(tester, 'save-preset');
    await tester.enterText(find.byKey(const ValueKey('preset-name')), 'Evening joint');
    await tapKey(tester, 'preset-save');

    await tester.enterText(find.byKey(const ValueKey('cannabis-grams')), '1');
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Evening joint'));
    await settle(tester);
    expect(find.widgetWithText(TextFormField, '0.2'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '18'), findsOneWidget);
    await disposeApp(tester, app);
  });
}
