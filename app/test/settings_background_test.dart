import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/background_config.dart';
import 'package:substance_journal_app/ui/design.dart';
import 'package:substance_journal_app/ui/settings/settings_page.dart';

import 'helpers.dart';

void main() {
  test('the background setting survives being saved and read, and bad data falls back', () {
    const c = BackgroundConfig(mode: BackgroundMode.still, palette: 'gold', dim: 0.5, imagePath: '/x/y.gif');
    final back = BackgroundConfig.decode(c.encode());
    expect(back.mode, BackgroundMode.still);
    expect(back.palette, 'gold');
    expect(back.dim, 0.5);
    expect(back.imagePath, '/x/y.gif');
    expect(BackgroundConfig.decode('nonsense').mode, BackgroundMode.flow);
    expect(BackgroundConfig.decode(null, defaultMode: BackgroundMode.off).active, isFalse);
    expect(BackgroundConfig.decode('{"dim": 9}').dim, 0.8); // clamped
    expect(paletteById('missing').id, 'amethyst');
  });

  test('with a background the screens and cards let it show through', () {
    final solid = buildTheme(Brightness.dark);
    final glass = buildTheme(Brightness.dark, translucent: true);
    expect(solid.scaffoldBackgroundColor.a, 1.0);
    expect(glass.scaffoldBackgroundColor, Colors.transparent);
    expect(glass.cardTheme.color!.a, lessThan(1.0));
  });

  testWidgets('Settings is a short list of groups; each opens on its own and the background can be switched', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    await tester.tap(find.text('Settings'));
    await settle(tester);

    for (final c in SettingsCategory.values) {
      expect(find.byKey(ValueKey('settings-${c.name}')), findsOneWidget, reason: c.name);
    }
    expect(find.byKey(const ValueKey('add-person')), findsNothing); // nothing is buried in one long page

    await tapKey(tester, 'settings-appearance');
    await settle(tester);
    expect(find.byKey(const ValueKey('background-mode')), findsOneWidget);
    await tester.tap(find.text('Still'));
    await settle(tester);
    final saved = BackgroundConfig.decode(await dbRun(tester, () => app.db.getSetting('background')));
    expect(saved.mode, BackgroundMode.still);
    expect(find.byKey(const ValueKey('palette-gold')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('palette-gold')));
    await settle(tester);
    expect(BackgroundConfig.decode(await dbRun(tester, () => app.db.getSetting('background'))).palette, 'gold');
    await disposeApp(tester, app);
  });

  testWidgets('on a wide screen the groups sit beside what they contain', (tester) async {
    final app = await buildTestApp(tester);
    await dbRun(tester, app.db.ensureDefaultPerson);
    await startApp(tester, app);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.byKey(const ValueKey('add-person')), findsOneWidget); // People is showing already
    expect(find.byKey(const ValueKey('settings-appearance')), findsOneWidget);
    await tapKey(tester, 'settings-appearance');
    await settle(tester);
    expect(find.byKey(const ValueKey('background-mode')), findsOneWidget); // no new screen, just the right-hand side
    expect(find.byKey(const ValueKey('add-person')), findsNothing);
    await disposeApp(tester, app);
  });
}
