import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/watch_bridge.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2026, 7, 3, 21);

  test('the watch settings survive being saved and read, and start switched off', () {
    expect(WatchPrefs.decode(null).enabled, isFalse);
    expect(WatchPrefs.decode(null).allowLog, isFalse);
    final back = WatchPrefs.decode(const WatchPrefs(enabled: true, allowLog: true).encode());
    expect(back.enabled, isTrue);
    expect(back.allowLog, isTrue);
    expect(WatchPrefs.decode('garbage').enabled, isFalse);
  });

  testWidgets('the snapshot carries the curve, recent doses and the Same-as-last label', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final e = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: now.subtract(const Duration(minutes: 30))));
    await dbRun(tester, () => app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: now.subtract(const Duration(minutes: 30)), dose: 2.7, unit: 'mg'));
    final rows = await dbRun(tester, () => app.db.ingestionsForPerson(me.id));

    Map<String, Object?> snap(WatchPrefs prefs) => buildWatchSnapshot(
          ingestions: rows,
          reference: app.reference,
          alcoholSettings: const EstimateSettings(),
          now: now,
          prefs: prefs,
        );

    final off = snap(const WatchPrefs(enabled: true));
    expect(off['curve'], isNotNull); // something is active
    expect((off['recent'] as List), hasLength(1));
    expect((off['recent'] as List).first['name'], 'Cannabis');
    expect(off['same'], contains('Cannabis'));
    expect(off['canLog'], isFalse); // the person has not allowed logging

    expect(snap(const WatchPrefs(enabled: true, allowLog: true))['canLog'], isTrue);
    await disposeApp(tester, app);
  });

  testWidgets('the watch logs the last dose again only when allowed, and says what it logged', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final e = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: now.subtract(const Duration(hours: 5))));
    await dbRun(tester, () => app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: now.subtract(const Duration(hours: 5)), dose: 2.7, unit: 'mg'));

    Future<WatchLogResult> press() => dbRun(tester, () => logSameForWatch(db: app.db, reference: app.reference, personId: me.id, now: now));
    Future<int> count() async => (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).where((i) => !i.deleted).length;

    final refused = await press();
    expect(refused.ok, isFalse);
    expect(await count(), 1); // nothing was logged

    await dbRun(tester, () => app.db.saveWatchPrefs(const WatchPrefs(enabled: true, allowLog: true)));
    final done = await press();
    expect(done.ok, isTrue);
    expect(done.message, contains('Cannabis'));
    expect(await count(), 2);
    await disposeApp(tester, app);
  });

  testWidgets('Settings has a Watch section with the two switches', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapKey(tester, 'settings-reminders');
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('watch-enabled')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('watch-allow-log')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('watch-enabled')));
    await settle(tester);
    expect((await dbRun(tester, () => app.db.getWatchPrefs())).enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('watch-allow-log')));
    await settle(tester);
    expect((await dbRun(tester, () => app.db.getWatchPrefs())).allowLog, isTrue);
    await tester.tap(find.byKey(const ValueKey('watch-enabled'))); // off again also turns logging off
    await settle(tester);
    final back = await dbRun(tester, () => app.db.getWatchPrefs());
    expect(back.enabled, isFalse);
    expect(back.allowLog, isFalse);
    await disposeApp(tester, app);
  });
}
