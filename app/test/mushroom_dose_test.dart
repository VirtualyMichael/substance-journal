import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
