import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/app.dart';
import 'package:substance_journal_app/data/app_lock.dart';
import 'package:substance_journal_app/data/assistant_link.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/lock/lock_gate.dart';
import 'package:substance_journal_app/ui/voice_assistant.dart';

import 'helpers.dart';

class FakeLink implements AssistantLinkHandle {
  int starts = 0;
  int stops = 0;
  final undone = <LinkAddition>[];
  final _events = StreamController<LinkAddition>.broadcast();

  void add(LinkAddition a) => _events.add(a);

  @override
  Stream<LinkAddition> get additions => _events.stream;

  @override
  Future<int> start() async {
    starts++;
    return 5555;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<bool> undoFromApp(LinkAddition a) async {
    undone.add(a);
    return true;
  }
}

class NoDeviceAuth implements DeviceAuth {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

Future<FakeLink> start(WidgetTester tester, TestApp app) async {
  final link = FakeLink();
  usePhoneScreen(tester);
  await dbRun(tester, app.db.ensureDefaultPerson);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(app.db),
      referenceProvider.overrideWithValue(app.reference),
      interactionPairsProvider.overrideWithValue(app.reference.interactionPairs),
      clockProvider.overrideWithValue(() => testNow),
      deviceAuthProvider.overrideWithValue(NoDeviceAuth()),
      assistantLinkSupportedProvider.overrideWithValue(true),
      assistantLinkFactoryProvider.overrideWithValue(() async => link),
    ],
    child: const SubstanceJournalApp(),
  ));
  await settle(tester, rounds: 6);
  return link;
}

Future<void> openSection(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await settle(tester);
  await tapKey(tester, 'settings-ai');
  await settle(tester);
  await tester.scrollUntilVisible(find.byKey(const ValueKey('assistant-link')), 300, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

Future<void> unlockWith(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const ValueKey('lock-pin')), pin);
  await tapKey(tester, 'lock-unlock');
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  await settle(tester);
}

void main() {
  setUpAll(() => pinIterations = 1000);

  testWidgets('off by default; the switch says what it can and cannot do; on shows the strip and every entry with Undo', (tester) async {
    final app = await buildTestApp(tester);
    final link = await start(tester, app);
    expect(link.starts, 0);
    expect(find.byKey(const ValueKey('assistant-linked')), findsNothing);

    await openSection(tester);
    expect(find.text(VoiceAssistantSection.switchLabel), findsOneWidget);
    expect(find.text(VoiceAssistantSection.explanation), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('assistant-link'))).value, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('assistant-autostart'))).value, isFalse);

    await tapKey(tester, 'assistant-link'); // no app lock set: on at once
    expect(link.starts, 1);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('assistant-link'))).value, isTrue);

    await tester.pageBack();
    await settle(tester);
    expect(find.byKey(const ValueKey('assistant-linked')), findsOneWidget);
    expect(find.text('Voice assistant linked'), findsOneWidget);

    final a = LinkAddition(summary: 'Beer - 12 oz 5% for Me', id: 'x1', table: 'ingestions', at: testNow);
    link.add(a);
    await settle(tester);
    expect(find.text('Added by your voice assistant: Beer - 12 oz 5% for Me'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(link.undone, [a]);

    await tapKey(tester, 'assistant-banner-off');
    expect(link.stops, 1);
    expect(find.byKey(const ValueKey('assistant-linked')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('with an app lock, turning it on needs the PIN', (tester) async {
    final app = await buildTestApp(tester);
    final config = await tester.runAsync(() => lockWithPin('4321'));
    await dbRun(tester, () => app.db.saveLockConfig(config!));
    final link = await start(tester, app);
    await unlockWith(tester, '4321');
    await openSection(tester);

    await tapKey(tester, 'assistant-link');
    expect(find.byKey(const ValueKey('pin-new')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pin-new')), '1111');
    await tapKey(tester, 'pin-ok');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    expect(link.starts, 0);
    expect(find.text('That is not your PIN.'), findsOneWidget);

    await tapKey(tester, 'assistant-link');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(link.starts, 0);

    await tapKey(tester, 'assistant-link');
    await tester.enterText(find.byKey(const ValueKey('pin-new')), '4321');
    await tapKey(tester, 'pin-ok');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    expect(link.starts, 1);
    await disposeApp(tester, app);
  });

  testWidgets('"Turn on again when the app starts" starts it only after the app lock is passed', (tester) async {
    final app = await buildTestApp(tester);
    final config = await tester.runAsync(() => lockWithPin('4321'));
    await dbRun(tester, () => app.db.saveLockConfig(config!));
    await dbRun(tester, () => app.db.setSetting(assistantAutoStartKey, 'true'));
    final link = await start(tester, app);
    expect(link.starts, 0); // still locked
    await unlockWith(tester, '4321');
    await settle(tester);
    expect(link.starts, 1);
    expect(find.byKey(const ValueKey('assistant-linked')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('hidden where the link is not offered (phones)', (tester) async {
    final app = await buildTestApp(tester);
    usePhoneScreen(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(app.db),
        referenceProvider.overrideWithValue(app.reference),
        interactionPairsProvider.overrideWithValue(app.reference.interactionPairs),
        clockProvider.overrideWithValue(() => testNow),
        assistantLinkSupportedProvider.overrideWithValue(false),
      ],
      child: const SubstanceJournalApp(),
    ));
    await settle(tester, rounds: 6);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapKey(tester, 'settings-ai');
    await settle(tester);
    expect(find.byKey(const ValueKey('assistant-link')), findsNothing);
    expect(find.text('Voice assistant'), findsNothing);
    await disposeApp(tester, app);
  });
}
