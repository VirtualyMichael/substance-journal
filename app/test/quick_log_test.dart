import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/add/dose_widgets.dart';
import 'package:substance_journal_app/app.dart';
import 'package:substance_journal_app/ui/quicklog/launch_route.dart';

import 'helpers.dart';

class FakeLaunch extends LaunchRoutes {
  FakeLaunch(this.route);
  final String? route;
  @override
  Future<String?> initial() async => route;
}

void main() {
  testWidgets('presets and recent doses are listed, and a tap plus a confirm logs the dose, with undo', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      await app.db.addDosePreset(
        substanceKey: 'lsd',
        route: 'sublingual',
        name: 'Usual tab',
        amount: 80,
        unit: 'µg',
        input: const DoseInput(text: '80').toPresetJson(),
      );
      // A preset that cannot be valid any more (no dose) is simply left out.
      await app.db.addDosePreset(substanceKey: 'lsd', route: 'sublingual', name: 'Broken', amount: 0, unit: 'µg', input: const DoseInput().toPresetJson());
      final old = testNow.subtract(const Duration(days: 3));
      final e = await app.db.addExperience(personId: me.id, sortDate: old);
      await app.db.addIngestion(experience: e, substanceKey: 'ketamine', route: 'insufflated', time: old, dose: 30, unit: 'mg');
    });
    await startApp(tester, app);

    await tapKey(tester, 'quick-log');
    expect(find.text('Usual tab'), findsOneWidget);
    expect(find.text('Broken'), findsNothing);
    expect(find.textContaining('Ketamine 30'), findsWidgets); // repeat a recent dose

    final tile = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('quick-preset-'));
    await tester.tap(tile);
    await settle(tester);
    expect(find.textContaining('Log Usual tab now?'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-active-warning')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-confirm')));
    await settle(tester, rounds: 6);

    final person = (await dbRun(tester, app.db.activePeople)).single;
    var rows = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    final lsd = rows.where((i) => i.substanceKey == 'lsd').single;
    expect((lsd.dose, lsd.unit, lsd.route), (80, 'µg', 'sublingual'));
    expect(lsd.time, testNow);

    // Logging it again straight away warns that the last dose has not fully arrived.
    await tester.tap(tile);
    await settle(tester);
    expect(find.byKey(const ValueKey('quick-active-warning')), findsOneWidget);
    expect(find.textContaining('has not fully arrived yet'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    await tester.tap(find.text('Undo'));
    await settle(tester, rounds: 6);
    rows = await dbRun(tester, () => app.db.ingestionsForPerson(person.id));
    expect(rows.where((i) => i.substanceKey == 'lsd'), isEmpty);
    await disposeApp(tester, app);
  });

  testWidgets('being opened with the quicklog route (shortcut, tile or widget) goes straight to the Quick log', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(app.db),
        referenceProvider.overrideWithValue(app.reference),
        interactionPairsProvider.overrideWithValue(app.reference.interactionPairs),
        clockProvider.overrideWithValue(() => testNow),
        launchRoutesProvider.overrideWithValue(FakeLaunch('quicklog')),
      ],
      child: const SubstanceJournalApp(),
    ));
    await settle(tester, rounds: 6);
    expect(find.text('Quick log'), findsWidgets);
    expect(find.textContaining('Tap one to log it for'), findsOneWidget);
    await disposeApp(tester, app);
  });
}
