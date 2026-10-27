import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('the journal shows what is active now, with a hold-off note until it has fully arrived', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow);
      await app.db.addIngestion(
          experience: e, substanceKey: 'mdma', route: 'oral', time: testNow.subtract(const Duration(minutes: 10)), dose: 100, unit: 'mg');
      // Yesterday's dose is long over and must not show.
      final old = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(days: 1)));
      await app.db.addIngestion(
          experience: old, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(const Duration(days: 1)), dose: 100, unit: 'µg');
    });
    await startApp(tester, app);

    expect(find.text('Active now'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-mdma')), findsOneWidget);
    expect(find.byKey(const ValueKey('active-lsd')), findsNothing);
    expect(find.text('Kicking in'), findsOneWidget);
    expect(find.byKey(const ValueKey('wait-mdma')), findsOneWidget);
    expect(find.textContaining('Hold off on more until then'), findsOneWidget);
    expect(find.textContaining('Fully arrives by about'), findsOneWidget);
    final note = find.byKey(const ValueKey('driving-note'));
    expect(note, findsOneWidget);
    expect(find.descendant(of: note, matching: find.textContaining('never a clearance')), findsOneWidget);
    expect(find.descendant(of: note, matching: find.textContaining('Plan not to drive')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('with nothing active there is no card', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    expect(find.text('Active now'), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('recent drinking shows an estimated BAC and clear time, and counts toward the driving note', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      for (var i = 0; i < 3; i++) {
        await app.db.logDrink(personId: me.id, at: testNow.subtract(Duration(minutes: 40 - i)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      }
    });
    await startApp(tester, app);
    final row = find.byKey(const ValueKey('active-alcohol'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('% BAC')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('Estimated to clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('driving-note')), findsOneWidget);
    await disposeApp(tester, app);
  });
}
