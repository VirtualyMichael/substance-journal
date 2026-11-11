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
    // How much this session added, and when it halves from its end.
    final gain = tester.widget<Text>(keyed('tolerance-gain-')).data!;
    expect(gain, startsWith('This session: '));
    expect(gain, contains('→'));
    expect(gain, contains('%'));
    expect(tester.widget<Text>(keyed('tolerance-halving-')).data!, contains('half by'));
    expect(keyed('tolerance-chart-'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('a live drinking session shows the Alcohol Tracker tiles; a past one shows session values', (tester) async {
    final app = await buildTestApp(tester);
    final ids = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      Future<String> session(DateTime at, int drinks) async {
        final e = await app.db.addExperience(personId: me.id, sortDate: at);
        for (var n = 0; n < drinks; n++) {
          await app.db.addIngestion(
            experience: e,
            substanceKey: 'alcohol',
            route: 'oral',
            time: at.add(Duration(minutes: 20 * n)),
            dose: 14,
            unit: 'g',
            details: {'drink': 'Beer', 'volume': 12.0, 'volumeUnit': 'oz', 'abv': 5.0},
          );
        }
        return e.id;
      }

      final past = await session(testNow.subtract(const Duration(days: 3)), 4);
      final live = await session(testNow.subtract(const Duration(minutes: 70)), 3);
      return (past: past, live: live);
    });
    await startApp(tester, app);

    await tapKey(tester, 'experience-${ids.live}');
    for (final tile in ['std', 'active', 'bac', 'peak', 'clear', 'tolerance']) {
      expect(find.byKey(ValueKey('alcohol-tile-$tile')), findsOneWidget, reason: tile);
    }
    expect(find.text('3.00'), findsOneWidget); // standard drinks
    expect(find.text('tolerance now'), findsOneWidget);
    expect(find.textContaining('min absorption'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tapKey(tester, 'experience-${ids.past}');
    expect(find.byKey(const ValueKey('alcohol-tile-active')), findsNothing);
    expect(find.byKey(const ValueKey('alcohol-tile-bac')), findsNothing);
    expect(find.text('4.00'), findsOneWidget);
    expect(find.text('tolerance before → after'), findsOneWidget);
    expect(find.text('reached near zero'), findsOneWidget);
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
