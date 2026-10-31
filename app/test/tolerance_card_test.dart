import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/ui/journal/tolerance_card.dart';

import 'helpers.dart';

void main() {
  testWidgets('the experience shows tolerance, its trend, and how recently the compound was used', (tester) async {
    final app = await buildTestApp(tester);
    final id = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final past = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(days: 5)));
      await app.db.addIngestion(experience: past, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(const Duration(days: 5)), dose: 100, unit: 'µg');
      final now = await app.db.addExperience(personId: me.id, sortDate: testNow);
      await app.db.addIngestion(experience: now, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(const Duration(minutes: 30)), dose: 100, unit: 'µg');
      return now.id;
    });
    await startApp(tester, app);
    await tapKey(tester, 'experience-$id');
    expect(find.byKey(const ValueKey('tolerance-card')), findsOneWidget);
    Finder keyed(String prefix) => find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith(prefix));
    expect(keyed('tolerance-trend-'), findsOneWidget);
    final context = tester.widget<Text>(keyed('tolerance-context-')).data!;
    expect(context, contains('Before this: 5 days earlier'));
    expect(context, contains('in the last 7 days'));
    await disposeApp(tester, app);
  });

  test('rising when more was taken lately than a week ago, falling when it is fading', () {
    ToleranceTrack track(double now, double weekAgo) => ToleranceTrack(
          key: 'x',
          label: 'X',
          level: now,
          lastUse: DateTime(2026, 7, 1),
          baselineAt: null,
          projection: [(DateTime(2026, 6, 26), weekAgo), (DateTime(2026, 7, 3), now)],
          substances: const ['X'],
        );
    final at = DateTime(2026, 7, 3);
    expect(toleranceTrend(track(2.0, 0.5), at), ToleranceTrend.rising);
    expect(toleranceTrend(track(0.5, 2.0), at), ToleranceTrend.falling);
    expect(toleranceTrend(track(1.0, 1.0), at), ToleranceTrend.steady);
  });
}
