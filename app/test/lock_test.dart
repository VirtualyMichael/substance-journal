import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/app.dart';
import 'package:substance_journal_app/data/app_lock.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/lock/lock_gate.dart';

import 'helpers.dart';

class FakeAuth implements DeviceAuth {
  FakeAuth({this.accepts = true});
  final bool accepts;
  int prompts = 0;

  @override
  Future<bool> available() async => true;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accepts;
  }
}

Future<void> startLocked(WidgetTester tester, TestApp app, DeviceAuth auth) async {
  usePhoneScreen(tester);
  await dbRun(tester, app.db.ensureDefaultPerson);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(app.db),
      referenceProvider.overrideWithValue(app.reference),
      interactionPairsProvider.overrideWithValue(app.reference.interactionPairs),
      clockProvider.overrideWithValue(() => testNow),
      deviceAuthProvider.overrideWithValue(auth),
    ],
    child: const SubstanceJournalApp(),
  ));
  await settle(tester, rounds: 6);
}

void main() {
  test('a PIN is four to eight digits, stored only as a salted hash, and checked against it', () async {
    expect(isValidPin('1234'), isTrue);
    expect(isValidPin('12345678'), isTrue);
    expect(isValidPin('123'), isFalse);
    expect(isValidPin('123456789'), isFalse);
    expect(isValidPin('12a4'), isFalse);

    final a = await lockWithPin('4321');
    final b = await lockWithPin('4321');
    expect(a.enabled, isTrue);
    expect(a.encode(), isNot(contains('4321')));
    expect(a.hash, isNot(b.hash)); // a new salt every time
    expect(await pinMatches(a, '4321'), isTrue);
    expect(await pinMatches(a, '4322'), isFalse);
    expect(await pinMatches(const LockConfig(), '4321'), isFalse);
    expect(LockConfig.decode(a.encode()).hash, a.hash);
    expect(LockConfig.decode('not json').enabled, isFalse);
  });

  testWidgets('with a PIN set the journal stays hidden until the PIN is right, and a wrong one says so', (tester) async {
    final app = await buildTestApp(tester);
    final config = await tester.runAsync(() => lockWithPin('4321'));
    await dbRun(tester, () => app.db.saveLockConfig(config!));
    await startLocked(tester, app, FakeAuth());

    expect(find.byKey(const ValueKey('lock-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-add')), findsNothing);
    expect(find.byKey(const ValueKey('lock-device')), findsNothing); // device unlock is off

    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '1111');
    await tapKey(tester, 'lock-unlock');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    expect(find.text('Wrong PIN.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '4321');
    await tapKey(tester, 'lock-unlock');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    expect(find.byKey(const ValueKey('lock-pin')), findsNothing);
    expect(find.byKey(const ValueKey('journal-add')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('device unlock opens the app without the PIN when it is turned on', (tester) async {
    final app = await buildTestApp(tester);
    final config = await tester.runAsync(() => lockWithPin('4321'));
    await dbRun(tester, () => app.db.saveLockConfig(config!.copyWith(useDevice: true)));
    final auth = FakeAuth();
    await startLocked(tester, app, auth);
    await settle(tester, rounds: 4);
    expect(auth.prompts, 1);
    expect(find.byKey(const ValueKey('lock-pin')), findsNothing);
    expect(find.byKey(const ValueKey('journal-add')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('a refused device unlock leaves the PIN screen, with a button to try again', (tester) async {
    final app = await buildTestApp(tester);
    final config = await tester.runAsync(() => lockWithPin('4321'));
    await dbRun(tester, () => app.db.saveLockConfig(config!.copyWith(useDevice: true)));
    final auth = FakeAuth(accepts: false);
    await startLocked(tester, app, auth);
    expect(find.byKey(const ValueKey('lock-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-device')), findsOneWidget);
    await tapKey(tester, 'lock-device');
    expect(auth.prompts, 2);
    expect(find.byKey(const ValueKey('journal-add')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('Settings sets a PIN (checking the two match) and turns the lock off with the PIN', (tester) async {
    final app = await buildTestApp(tester);
    await startLocked(tester, app, FakeAuth());
    await tester.tap(find.text('Settings'));
    await settle(tester);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('lock-enable')), 300, scrollable: find.byType(Scrollable).first);
    await tapKey(tester, 'lock-enable');
    await tester.enterText(find.byKey(const ValueKey('pin-new')), '2468');
    await tester.enterText(find.byKey(const ValueKey('pin-confirm')), '2469');
    await tapKey(tester, 'pin-ok');
    expect(find.text('The two PINs do not match.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pin-confirm')), '2468');
    await tapKey(tester, 'pin-ok');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    var saved = await dbRun(tester, () => app.db.watchLockConfig().first);
    expect(saved.enabled, isTrue);
    expect(await tester.runAsync(() => pinMatches(saved, '2468')), isTrue);
    expect(find.byKey(const ValueKey('lock-disable')), findsOneWidget); // still on the Settings page, not locked out

    await tapKey(tester, 'lock-disable');
    await tester.enterText(find.byKey(const ValueKey('pin-new')), '0000');
    await tapKey(tester, 'pin-ok');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    saved = await dbRun(tester, () => app.db.watchLockConfig().first);
    expect(saved.enabled, isTrue); // the wrong PIN did not turn it off

    await tapKey(tester, 'lock-disable');
    await tester.enterText(find.byKey(const ValueKey('pin-new')), '2468');
    await tapKey(tester, 'pin-ok');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester);
    saved = await dbRun(tester, () => app.db.watchLockConfig().first);
    expect(saved.enabled, isFalse);
    await disposeApp(tester, app);
  });
}
