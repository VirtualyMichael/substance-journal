import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('Same as last time repeats the latest dose after a confirm, and Log now saves from the dose step', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final old = testNow.subtract(const Duration(days: 2));
      final e = await app.db.addExperience(personId: me.id, sortDate: old);
      await app.db.addIngestion(experience: e, substanceKey: 'ketamine', route: 'insufflated', time: old, dose: 30, unit: 'mg');
    });
    await startApp(tester, app);

    expect(find.textContaining('Same as last time: Ketamine'), findsOneWidget);
    await tapKey(tester, 'same-as-last');
    await tapKey(tester, 'quick-confirm');
    final person = (await dbRun(tester, app.db.activePeople)).single;
    var rows = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    expect(rows, hasLength(2));
    expect(rows.where((r) => r.dose == 30), hasLength(2));

    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).clearSnackBars(); // it would cover the buttons
    await tester.pumpAndSettle();
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-lsd');
    await tester.enterText(find.byKey(const ValueKey('dose-field')), '90');
    await tester.pumpAndSettle();
    await tapKey(tester, 'log-now');
    await settle(tester, rounds: 12);
    rows = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    expect(rows, hasLength(3));
    final lsd = rows.firstWhere((r) => r.substanceKey == 'lsd');
    expect(lsd.dose, 90);
    await disposeApp(tester, app);
  });
}
