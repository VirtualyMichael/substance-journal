import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  Color primaryOf(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;

  testWidgets('choosing an accent colour recolours the app and is remembered; rainbow replaces it', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    final before = primaryOf(tester);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    final swatch = find.byKey(const ValueKey('accent-ffd1495b'));
    await tester.scrollUntilVisible(swatch, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await settle(tester, rounds: 8);
    final red = primaryOf(tester);
    expect(red, isNot(before));
    expect(await dbRun(tester, () => app.db.getSetting('accentColor')), '${0xFFD1495B}');

    await tester.tap(find.byKey(const ValueKey('rainbow-accent')));
    await settle(tester, rounds: 8);
    expect(await dbRun(tester, () => app.db.getSetting('rainbowAccent')), 'true');
    await tester.pump(const Duration(seconds: 7)); // two rainbow steps
    await tester.pump(const Duration(seconds: 4));
    expect(primaryOf(tester), isNot(red));

    // Picking a fixed colour turns rainbow off again.
    await tester.tap(swatch);
    await settle(tester, rounds: 8);
    expect(await dbRun(tester, () => app.db.getSetting('rainbowAccent')), 'false');
    await disposeApp(tester, app);
  });
}
