import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/app.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/providers.dart';

/// 2026-07-03 21:00, a Friday evening.
final DateTime testNow = DateTime(2026, 7, 3, 21, 0);

ReferenceRepository loadReference() => ReferenceRepository(
      parseSubstances(File('assets/data/substances.json').readAsStringSync()),
      interactionPairs: parseInteractions(File('assets/data/interactions.json').readAsStringSync()),
    );

class TestApp {
  TestApp(this.db, this.reference, this.widget);
  final AppDatabase db;
  final ReferenceRepository reference;
  final Widget widget;
}

/// Builds the app around an in-memory database.
///
/// The database is created in the real zone (not the test's fake-async zone), otherwise its
/// internal locks would wait on fake microtasks and direct queries from tests would hang.
Future<TestApp> buildTestApp(WidgetTester tester, {DateTime? now}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = (await tester.runAsync(
    () async => AppDatabase.memory(nowMillis: () => (now ?? testNow).millisecondsSinceEpoch),
  ))!;
  final reference = loadReference();
  final widget = ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      referenceProvider.overrideWithValue(reference),
      interactionPairsProvider.overrideWithValue(reference.interactionPairs),
      clockProvider.overrideWithValue(() => now ?? testNow),
    ],
    child: const SubstanceJournalApp(),
  );
  return TestApp(db, reference, widget);
}

/// Lets Drift's real asynchronous work finish, then rebuilds the widget tree.
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs database work in real time (Drift is not driven by the test's fake clock).
Future<T> dbRun<T>(WidgetTester tester, Future<T> Function() work) async {
  final result = await tester.runAsync(() => work().timeout(const Duration(seconds: 10)));
  return result as T;
}

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> startApp(WidgetTester tester, TestApp app) async {
  usePhoneScreen(tester);
  await dbRun(tester, app.db.ensureDefaultPerson);
  await tester.pumpWidget(app.widget);
  await settle(tester);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: 'widget with key $key');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> disposeApp(WidgetTester tester, TestApp app) async {
  await tester.pumpWidget(const SizedBox());
  // Drift schedules stream clean-up on timers in the test's fake clock; let them fire first.
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await app.db.close().timeout(const Duration(seconds: 3), onTimeout: () {});
  });
}
