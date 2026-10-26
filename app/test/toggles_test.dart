import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/ui/timeline/timeline_chart.dart';

import 'helpers.dart';

void main() {
  testWidgets('each substance on a day can be switched off and on to see the others alone or all together', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final exp = await dbRun(tester, () async {
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(hours: 3)));
      await app.db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(const Duration(hours: 3)), dose: 100, unit: 'µg');
      await app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: testNow.subtract(const Duration(hours: 2)), dose: 5, unit: 'mg');
      await app.db.addIngestion(experience: e, substanceKey: 'alcohol', route: 'oral', time: testNow.subtract(const Duration(hours: 1)), dose: 14, unit: 'g');
      return e;
    });
    await startApp(tester, app);
    await tester.tap(find.text(exp.title.isEmpty ? 'Journal' : exp.title).first);
    await settle(tester);
    // open the experience from the journal list
    await tester.tap(find.byType(Card).first);
    await settle(tester);

    int shown() => tester.widget<TimelineChart>(find.byType(TimelineChart)).series.length;
    expect(shown(), 3);
    expect(find.byKey(const ValueKey('toggle-lsd')), findsOneWidget);

    await tapKey(tester, 'toggle-lsd');
    await tapKey(tester, 'toggle-cannabis');
    expect(shown(), 1); // only alcohol left
    expect(tester.widget<TimelineChart>(find.byType(TimelineChart)).series.single.substanceKey, 'alcohol');

    await tapKey(tester, 'toggle-all'); // "Show all"
    expect(shown(), 3);
    await tapKey(tester, 'toggle-all'); // "Hide all"
    expect(shown(), 0);
    await disposeApp(tester, app);
  });
}
