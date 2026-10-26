import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/safety/safer_use_page.dart';

import 'helpers.dart';

void main() {
  Future<TestApp> page(WidgetTester tester, {String? a, String? b}) async {
    final built = await buildTestApp(tester);
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
      ],
      child: MaterialApp(home: SaferUsePage(initialA: a, initialB: b)),
    ));
    await settle(tester);
    return built;
  }

  testWidgets('shows the basics and emergency steps, and no result until two compounds are chosen', (tester) async {
    final app = await page(tester);
    expect(find.text('If something goes wrong'), findsOneWidget);
    expect(find.text('Start low, go slow'), findsOneWidget);
    expect(find.byKey(const ValueKey('combo-result')), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('a dangerous pair is flagged, and a pair with no entry still says that is not proof of safety', (tester) async {
    var app = await page(tester, a: 'alcohol', b: 'ketamine');
    final result = find.byKey(const ValueKey('combo-result'));
    expect(find.descendant(of: result, matching: find.textContaining('Alcohol + Ketamine')), findsOneWidget);
    expect(find.descendant(of: result, matching: find.textContaining('Alcohol + Ketamine: Dangerous')), findsOneWidget);
    await disposeApp(tester, app);

    app = await page(tester, a: 'nicotine', b: 'cannabis');
    expect(find.descendant(of: result, matching: find.textContaining('does not mean it is safe')), findsOneWidget);
    await disposeApp(tester, app);
  });
}
