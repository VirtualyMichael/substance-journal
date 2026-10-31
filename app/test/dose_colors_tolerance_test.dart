import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/ui/design.dart';
import 'package:substance_journal_app/ui/journal/tolerance_card.dart';
import 'package:substance_journal_app/ui/timeline/timeline_data.dart';

import 'helpers.dart';

void main() {
  testWidgets('each dose of a compound gets its own curve and colour, and a chosen colour wins', (tester) async {
    final app = await buildTestApp(tester);
    final rows = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow);
      final a = await app.db.addIngestion(experience: e, substanceKey: 'mdma', route: 'oral', time: testNow.subtract(const Duration(hours: 3)), dose: 80, unit: 'mg');
      final b = await app.db.addIngestion(
        experience: e,
        substanceKey: 'mdma',
        route: 'oral',
        time: testNow.subtract(const Duration(hours: 1)),
        dose: 40,
        unit: 'mg',
        details: {'color': 0xFFE53935},
      );
      return [a, b];
    });
    final series = buildTimelineSeries(ingestions: rows, reference: app.reference, now: testNow);
    expect(series, hasLength(1)); // still one combined curve per compound
    expect(series.single.parts, hasLength(2));
    expect(series.single.parts.first.color, substanceColor('mdma'));
    expect(series.single.parts.last.color, const Color(0xFFE53935));

    final colors = doseColors(rows);
    expect(colors[rows.first.id], substanceColor('mdma'));
    expect(colors[rows.last.id], const Color(0xFFE53935));

    // One dose has no separate parts, but a colour chosen for it recolours its curve.
    final single = buildTimelineSeries(
      ingestions: [rows.last],
      reference: app.reference,
      now: testNow,
    );
    expect(single.single.parts, isEmpty);
    expect(single.single.color, const Color(0xFFE53935));
    expect(jsonDecode(rows.last.detailsJson)['color'], 0xFFE53935);

    // Without a choice, doses of one compound still differ.
    final plain = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow);
      return [
        for (var n = 0; n < 3; n++)
          await app.db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(Duration(hours: n)), dose: 50, unit: 'µg'),
      ];
    });
    expect({for (final c in doseColors(plain).values) c.toARGB32()}, hasLength(3));
    await disposeApp(tester, app);
  });

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
