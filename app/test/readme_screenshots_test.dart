// Renders the screenshots used in the README from made-up demo data (never anyone's real journal).
//
// Skipped unless SJ_SCREENSHOTS_DIR is set:
//   SJ_SCREENSHOTS_DIR=../docs/screenshots flutter test test/readme_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/ui/add/dose_widgets.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';
import 'package:substance_journal_app/ui/safety/safer_use_page.dart';

import 'helpers.dart';

final String? _outDir = Platform.environment['SJ_SCREENSHOTS_DIR'];
const _fontDir = 'C:/dev/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<ByteData> bytes(String name) async => ByteData.view(File('$_fontDir/$name').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-medium.ttf'))
    ..addFont(bytes('roboto-bold.ttf'))
    ..addFont(bytes('roboto-italic.ttf'));
  final icons = FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'));
  await roboto.load();
  await icons.load();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  // No keyboard focus ring in the picture: drop focus and pretend input is touch.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  FocusManager.instance.rootScope.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$_outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  final skip = _outDir == null ? 'set SJ_SCREENSHOTS_DIR to render the README screenshots' : null;

  testWidgets('README screenshots', skip: skip != null, (tester) async {
    await _loadFonts();
    debugDisableShadows = false; // flutter_test draws shadows as solid black unless told otherwise
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch; // no keyboard focus rings in the pictures
    final key = GlobalKey();
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);

    await dbRun(tester, app.db.ensureDefaultDrinkPresets);
    DateTime ago(Duration d) => testNow.subtract(d);
    // Tonight: a dose still coming up, so the "Active now" card has something to say.
    final tonight = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: ago(const Duration(minutes: 40)), title: 'Friday night in'));
    await dbRun(tester, () => app.db.addIngestion(experience: tonight, substanceKey: 'mdma', route: 'oral', time: ago(const Duration(minutes: 40)), dose: 90, unit: 'mg'));
    for (var i = 0; i < 3; i++) {
      await dbRun(tester, () => app.db.logDrink(personId: me.id, at: ago(Duration(minutes: 150 - 25 * i)), volume: 12, volumeUnit: 'oz', abvPercent: 5, name: 'Beer'));
    }
    await dbRun(tester, () => app.db.setLimits(me.id, const DrinkLimits(daily: 4, weekly: 14)));

    // Earlier sessions so the journal, insights and tolerance have history.
    final festival = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: ago(const Duration(days: 5, hours: 3)), title: 'Festival day two'));
    await dbRun(tester, () => app.db.addIngestion(experience: festival, substanceKey: 'lsd', route: 'sublingual', time: ago(const Duration(days: 5, hours: 3)), dose: 100, unit: 'µg'));
    await dbRun(tester, () => app.db.addIngestion(experience: festival, substanceKey: 'cannabis', route: 'smoked', time: ago(const Duration(days: 5, hours: 1)), dose: 2.7, unit: 'mg', absorbedMg: 2.7, method: 'joint', details: {'productThcMg': 15.0}));
    await dbRun(tester, () => app.db.addTimedNote(experienceId: festival.id, time: ago(const Duration(days: 5, hours: 1, minutes: 30)), note: 'Visuals picking up', colorValue: 0xFF3D9970));
    await dbRun(tester, () => app.db.addRating(experienceId: festival.id, time: ago(const Duration(days: 5)), shulgin: 'plus2', scores: {'mood': 8, 'anxiety': 2}));
    final quiet = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: ago(const Duration(days: 12)), title: 'Quiet weekend'));
    await dbRun(tester, () => app.db.addIngestion(experience: quiet, substanceKey: 'psilocybin_mushrooms', route: 'oral', time: ago(const Duration(days: 12)), dose: 1.5, unit: 'g'));
    await dbRun(tester, () => app.db.addRating(experienceId: quiet.id, time: ago(const Duration(days: 12)), shulgin: 'plus3', scores: {'mood': 9}));
    for (final d in [3, 9, 16, 21]) {
      await dbRun(tester, () => app.db.logDrink(personId: me.id, at: ago(Duration(days: d, hours: -1)), volume: 5, volumeUnit: 'oz', abvPercent: 12, name: 'Wine'));
    }

    // A recipe-style preset and a tested sample, for Quick log and the drug checking log.
    await dbRun(tester, () => app.db.addDosePreset(substanceKey: 'lsd', route: 'sublingual', name: 'Usual tab', amount: 100, unit: 'µg', input: const DoseInput(text: '100').toPresetJson()));
    final sample = await dbRun(tester, () => app.db.addProduct(substanceKey: 'mdma', name: 'Pink pill'));
    await dbRun(tester, () => app.db.addReagentTest(productId: sample.id, substanceKey: 'mdma', testedAt: ago(const Duration(hours: 5)), kind: 'reagent', reagent: 'Marquis', initialColor: 'Purple', finalColor: 'Black', outcome: 'matched'));
    await dbRun(tester, () => app.db.addReagentTest(productId: sample.id, substanceKey: 'mdma', testedAt: ago(const Duration(hours: 5)), kind: 'strip', reagent: 'Fentanyl strip', outcome: 'negative'));
    final powder = await dbRun(tester, () => app.db.addProduct(substanceKey: 'ketamine', name: 'Saturday powder'));
    await dbRun(tester, () => app.db.addReagentTest(productId: powder.id, substanceKey: 'ketamine', testedAt: ago(const Duration(days: 2)), kind: 'reagent', reagent: 'Morris', initialColor: 'Yellow', outcome: 'unmatched'));

    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: key, child: app.widget));
      await settle(tester, rounds: 6);
    }

    // ---- phone ----
    await show(const Size(412, 892));
    await _capture(tester, key, 'journal');

    await tester.tap(find.text('Friday night in'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, 'experience');
    await tester.pageBack();
    await settle(tester);

    await tapKey(tester, 'quick-log');
    await _capture(tester, key, 'quick-log');
    await tester.pageBack();
    await settle(tester);

    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompoundDetailPage(substanceKey: 'lsd', personId: me.id)));
    await settle(tester, rounds: 6);
    await tester.scrollUntilVisible(find.text('How it typically unfolds'), 200, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 40));
    await settle(tester);
    await _capture(tester, key, 'compound');
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Insights'));
    await settle(tester, rounds: 6);
    await tester.tap(find.byIcon(Icons.chevron_left)); // last month has the most going on
    await settle(tester, rounds: 6);
    await _capture(tester, key, 'insights');

    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('open-testing')), 300, scrollable: find.byType(Scrollable).first);
    await tapKey(tester, 'open-testing');
    await _capture(tester, key, 'drug-checking');
    await tester.pageBack();
    await settle(tester);
    final settingsContext = tester.element(find.byType(Scaffold).first);
    Navigator.of(settingsContext).push(MaterialPageRoute(builder: (_) => const SaferUsePage(initialA: 'alcohol', initialB: 'ketamine')));
    await settle(tester, rounds: 6);
    await _capture(tester, key, 'safer-use');
    await tester.pageBack();
    await settle(tester);

    // ---- alcohol mode ----
    await settle(tester, rounds: 3);
    await dbRun(tester, () => app.db.setSetting('alcoholMode', 'true'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, 'alcohol');

    // ---- desktop ----
    await dbRun(tester, () => app.db.setSetting('alcoholMode', 'false'));
    await show(const Size(1280, 800));
    await _capture(tester, key, 'desktop');
    debugDisableShadows = true; // back to the test default, or the framework flags the run

    await disposeApp(tester, app);
  });
}
