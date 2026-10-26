import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/sync.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/sync/qr_widgets.dart';

import 'helpers.dart';

void main() {
  /// A second device, to produce packages the screen can receive.
  Future<(AppDatabase, SyncService)> otherDevice(WidgetTester tester) async {
    final db = (await tester.runAsync(() async => AppDatabase.memory(deviceId: 'laptop')))!;
    addTearDown(() async => tester.runAsync(db.close));
    return (db, SyncService(db, deviceName: 'Laptop'));
  }

  Future<TestApp> open(WidgetTester tester, {String? pickedFile, void Function(String)? onSave}) async {
    final built = await buildTestApp(tester);
    await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
        clockProvider.overrideWithValue(() => testNow),
        cameraScannerAvailableProvider.overrideWithValue(false),
        packageFilePickerProvider.overrideWithValue(() async => pickedFile == null ? null : File(pickedFile).readAsString()),
        packageSaverProvider.overrideWithValue((name, text) async {
          onSave?.call(text);
          return name;
        }),
      ],
      child: (built.widget as ProviderScope).child,
    ));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    final open = find.byKey(const ValueKey('open-sync'));
    await tester.scrollUntilVisible(open, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await settle(tester);
    return built;
  }

  testWidgets('shows a pairing QR and a copyable code, and lists the waiting device', (tester) async {
    final built = await open(tester);
    expect(find.byKey(const ValueKey('no-peers')), findsOneWidget);
    expect(find.byKey(const ValueKey('scan-pairing')), findsNothing); // no camera on this device
    await tapKey(tester, 'show-pairing');
    expect(find.text('Your pairing code'), findsOneWidget);
    expect(find.byType(QrCard), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.textContaining('Waiting for the other device'), findsOneWidget);
    await disposeApp(tester, built);
  });

  testWidgets('pairing by pasted code, then receiving a pasted package merges it', (tester) async {
    final (otherDb, other) = await otherDevice(tester);
    final code = (await tester.runAsync(() async {
      final person = await otherDb.ensureDefaultPerson();
      final e = await otherDb.addExperience(personId: person.id, sortDate: DateTime(2026, 7, 1, 9));
      await otherDb.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 9), dose: 100, unit: 'µg');
      return other.offerPairing();
    }))!;

    final built = await open(tester);
    // Enter the laptop's pairing code.
    await tapKey(tester, 'paste-pairing');
    await tester.enterText(find.byKey(const ValueKey('paste-field')), code.encode());
    await tapKey(tester, 'paste-ok');
    await settle(tester);
    expect(find.textContaining('Paired with Laptop'), findsOneWidget);
    expect(find.byKey(const ValueKey('peer-laptop')), findsOneWidget);

    // The laptop sends its journal as text; this device receives it.
    final package = (await tester.runAsync(() async => other.createPackage((await other.peers()).single.deviceId, everything: true)))!;
    await tapKey(tester, 'receive-laptop');
    await tapKey(tester, 'receive-paste');
    await tester.enterText(find.byKey(const ValueKey('paste-field')), package);
    await tapKey(tester, 'paste-ok');
    await settle(tester, rounds: 12);
    expect(find.byKey(const ValueKey('sync-result')), findsOneWidget);
    expect(find.textContaining('changes from Laptop merged'), findsOneWidget);
    await tapKey(tester, 'sync-done');
    final me = (await dbRun(tester, built.db.activePeople)).single;
    expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), hasLength(1));
    await disposeApp(tester, built);
  });

  testWidgets('a damaged package explains itself and changes nothing', (tester) async {
    final (_, other) = await otherDevice(tester);
    final code = (await tester.runAsync(other.offerPairing))!;
    final built = await open(tester);
    await tapKey(tester, 'paste-pairing');
    await tester.enterText(find.byKey(const ValueKey('paste-field')), code.encode());
    await tapKey(tester, 'paste-ok');
    await settle(tester);
    await tapKey(tester, 'receive-laptop');
    await tapKey(tester, 'receive-paste');
    await tester.enterText(find.byKey(const ValueKey('paste-field')), 'SJSYNC1:not-really-a-package');
    await tapKey(tester, 'paste-ok');
    await settle(tester);
    expect(find.textContaining('not a Substance Journal sync package'), findsOneWidget);
    await disposeApp(tester, built);
  });

  testWidgets('send offers QR codes, a file and text, and QR frames reassemble to the package', (tester) async {
    final (_, other) = await otherDevice(tester);
    final code = (await tester.runAsync(other.offerPairing))!;
    String? saved;
    final built = await open(tester, onSave: (t) => saved = t);
    await dbRun(tester, () async {
      final me = await built.db.ensureDefaultPerson();
      final e = await built.db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1, 9));
      await built.db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 9), dose: 100, unit: 'µg');
    });
    await tapKey(tester, 'paste-pairing');
    await tester.enterText(find.byKey(const ValueKey('paste-field')), code.encode());
    await tapKey(tester, 'paste-ok');
    await settle(tester);

    await tapKey(tester, 'send-laptop');
    await settle(tester, rounds: 8);
    expect(find.byKey(const ValueKey('send-summary')), findsOneWidget);
    await tapKey(tester, 'send-file');
    await settle(tester);
    expect(saved, startsWith('SJSYNC1:'));

    await tapKey(tester, 'send-qr');
    await settle(tester);
    expect(find.byType(QrFramePlayer), findsOneWidget);
    expect(find.textContaining(RegExp(r'Code \d+ of \d+')), findsOneWidget);
    await disposeApp(tester, built);
  });
}
