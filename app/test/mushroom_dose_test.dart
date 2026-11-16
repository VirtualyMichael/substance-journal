import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/ui/add/mushroom_calculator.dart';

import 'helpers.dart';

void main() {
  Future<dynamic> logMushrooms(WidgetTester tester, {String? form, required String amount}) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-psilocybin_mushrooms');
    expect(find.byKey(const ValueKey('dose-field')), findsNothing); // no mg field: grams, dried or fresh
    if (form != null) {
      await tester.tap(find.text(form));
      await settle(tester);
    }
    await tester.enterText(find.byKey(ValueKey('mushroom-amount-${{'Fresh g': 'fresh', 'Pure mg': 'mg'}[form] ?? 'dried'}')), amount);
    await settle(tester, rounds: 2);
    return app;
  }

  Future<dynamic> savedRow(WidgetTester tester, dynamic app) async {
    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');
    final person = (await dbRun(tester, app.db.activePeople)).single;
    return (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
  }

  testWidgets('dried grams are kept as they are and classed against the gram bands', (tester) async {
    final app = await logMushrooms(tester, amount: '1.5');
    expect(find.textContaining('Common'), findsWidgets);
    final row = await savedRow(tester, app);
    expect((row.dose, row.unit), (1.5, 'g'));
    expect(row.detailsJson, contains('"form":"dried"'));
    await disposeApp(tester, app);
  });

  testWidgets('fresh weight counts as a tenth of its weight in dried', (tester) async {
    final app = await logMushrooms(tester, form: 'Fresh g', amount: '20');
    expect(find.text('= 2 g dried (about 20 mg psilocybin)'), findsOneWidget);
    final row = await savedRow(tester, app);
    expect((row.dose, row.unit), (2.0, 'g'));
    expect(row.detailsJson, contains('"form":"fresh"'));
    expect(row.detailsJson, contains('"entered":20.0'));
    await disposeApp(tester, app);
  });

  testWidgets('pure psilocybin mg converts at 10 mg per gram', (tester) async {
    final app = await logMushrooms(tester, form: 'Pure mg', amount: '25');
    final row = await savedRow(tester, app);
    expect(row.dose, closeTo(2.5, 1e-9));
    expect(row.unit, 'g');
    await disposeApp(tester, app);
  });

  Map<String, dynamic> details(dynamic row) => jsonDecode(row.detailsJson as String) as Map<String, dynamic>;

  testWidgets('the calculator shows an estimate with its range and stores it beside the dose', (tester) async {
    final app = await logMushrooms(tester, amount: '2');
    // Unknown potency: 10 mg/g expected, the published range around it.
    expect(tester.widget<Text>(find.byKey(const ValueKey('mushroom-estimate'))).data, startsWith('About 20 mg psilocybin equivalents (range'));
    expect(find.byKey(const ValueKey('mushroom-caveat')), findsOneWidget);
    expect(find.byKey(const ValueKey('mushroom-formula')), findsOneWidget);
    final row = await savedRow(tester, app);
    expect((row.dose, row.unit), (2.0, 'g')); // the dose stays grams of dried mushroom
    final d = details(row);
    expect(d['form'], 'dried');
    expect(d['psilocybinEqMg'], 20.0);
    expect(d['psilocybinEqMgLow'], lessThan(20));
    expect(d['psilocybinEqMgHigh'], greaterThan(20));
    expect((d['calc'] as Map)['dryness'], 'typical');
    await disposeApp(tester, app);
  });

  testWidgets('a typed potency, caps only and psilocin change the estimate, not the logged grams', (tester) async {
    final app = await logMushrooms(tester, amount: '1.5');
    await tapKey(tester, 'mushroom-details');
    await tester.enterText(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('mushroom-psilocybin-')), '1.2');
    await settle(tester, rounds: 2);
    await tester.enterText(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('mushroom-psilocin-')), '0.1');
    await settle(tester, rounds: 2);
    final expected = 1.5 * 1000 * (1.2 + 0.1 * psilocinToPsilocybin) / 100;
    expect(tester.widget<Text>(find.byKey(const ValueKey('mushroom-estimate'))).data, startsWith('About ${expected.toStringAsFixed(0)} mg'));
    await tester.ensureVisible(find.text('Caps'));
    await tester.tap(find.text('Caps'));
    await settle(tester, rounds: 2);
    final row = await savedRow(tester, app);
    expect(row.dose, 1.5);
    final d = details(row);
    expect(d['psilocybinEqMg'], closeTo(expected, 0.01));
    expect(d['psilocybinEqMgHigh'], greaterThan(d['psilocybinEqMg'] as num)); // caps can be stronger
    expect((d['calc'] as Map)['part'], 'caps');
    expect((d['calc'] as Map)['potencySource'], 'estimate');
    await disposeApp(tester, app);
  });

  testWidgets('capsules are counted, and zero or very large amounts are flagged', (tester) async {
    final app = await logMushrooms(tester, amount: '0');
    expect(find.byKey(const ValueKey('mushroom-error')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mushroom-amount-dried')), '30');
    await settle(tester, rounds: 2);
    expect(find.byKey(const ValueKey('mushroom-warning-0')), findsOneWidget);
    await tester.tap(find.text('Other'));
    await settle(tester, rounds: 2);
    await tester.enterText(find.byKey(const ValueKey('mushroom-count')), '4');
    await tester.enterText(find.byKey(const ValueKey('mushroom-per-unit')), '250');
    await settle(tester, rounds: 2);
    final row = await savedRow(tester, app);
    expect((row.dose, row.unit), (1.0, 'g'));
    final d = details(row);
    expect((d['form'], d['entered'], d['psilocybinEqMg']), ('capsule', 4.0, 10.0));
    await disposeApp(tester, app);
  });

  testWidgets('a batch saves as a preset with its potency and links back to itself', (tester) async {
    final app = await logMushrooms(tester, amount: '1');
    await tapKey(tester, 'mushroom-details');
    await tester.enterText(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('mushroom-psilocybin-')), '0.9');
    await settle(tester, rounds: 2);
    await tapKey(tester, 'mushroom-save-batch');
    await tester.enterText(find.byKey(const ValueKey('batch-name')), 'Spring grow');
    await tester.enterText(find.byKey(const ValueKey('batch-strain')), 'B+');
    await tapKey(tester, 'batch-save');
    await settle(tester);
    final presets = await dbRun(tester, () => app.db.watchDosePresets('psilocybin_mushrooms', 'oral').first);
    expect(presets.single.name, 'Spring grow');
    final saved = jsonDecode(presets.single.detailsJson) as Map<String, dynamic>;
    expect((saved['batch'] as Map)['strain'], 'B+');
    expect((saved['batch'] as Map)['psilocybinPct'], '0.9');
    final calc = ((saved['input'] as Map)['mushroomCalc'] as Map);
    expect(calc['batchId'], presets.single.id);
    // Let the 'Batch saved' message time out so it does not cover the save button.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    final row = await savedRow(tester, app);
    expect(details(row)['batchId'], presets.single.id);
    expect(details(row)['batchName'], 'Spring grow');
    await disposeApp(tester, app);
  });

  test('ratings on entries from a batch feed its calibration', () {
    Ingestion row(String id, String batch, String? feel) => Ingestion(
          id: id,
          hlc: '0',
          experienceId: 'e',
          personId: 'p',
          substanceKey: 'psilocybin_mushrooms',
          route: 'oral',
          time: testNow,
          dose: 1,
          unit: 'g',
          doseIsEstimate: false,
          notes: '',
          detailsJson: jsonEncode({'batchId': batch, 'batchFeel': ?feel}),
          deleted: false,
        );
    final rows = [row('a', 'b1', 'muchWeaker'), row('b', 'b1', 'weaker'), row('c', 'b2', 'stronger'), row('d', 'b1', null)];
    final ratings = batchRatings(rows, 'b1');
    expect(ratings, [BatchFeel.muchWeaker, BatchFeel.weaker]);
    final c = calibrate(1.0, ratings)!;
    expect(c.factor, lessThan(1));
    expect(c.factor, greaterThanOrEqualTo(1 / maxCalibrationFactor));
  });
}
