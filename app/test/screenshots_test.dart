// Renders the main screens to PNG files so the design can be reviewed without launching the app.
//
// Skipped unless SJ_SCREENSHOTS_DIR is set:
//   SJ_SCREENSHOTS_DIR=C:/temp/shots flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$_outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  final skip = _outDir == null ? 'set SJ_SCREENSHOTS_DIR to render screenshots' : null;

  testWidgets('render main screens', skip: skip != null, (tester) async {
    await _loadFonts();
    final key = GlobalKey();
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final bob = await dbRun(tester, () => app.db.addPerson('Bob'));

    // A busy evening for me: MDMA, then alcohol, then cannabis, plus a note and a rating.
    final night = await dbRun(
      tester,
      () => app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(hours: 4)), title: 'Saturday night'),
    );
    Future<void> add(String s, String route, double dose, String unit, Duration ago, {double? absorbed, String? method}) => dbRun(
          tester,
          () => app.db.addIngestion(
            experience: night,
            substanceKey: s,
            route: route,
            time: testNow.subtract(ago),
            dose: dose,
            unit: unit,
            absorbedMg: absorbed,
            method: method,
            details: absorbed == null ? null : {'productThcMg': 15.0},
          ),
        );
    await add('mdma', 'oral', 100, 'mg', const Duration(hours: 4));
    await add('alcohol', 'oral', 20, 'g', const Duration(hours: 2, minutes: 30));
    await add('cannabis', 'smoked', 2.7, 'mg', const Duration(hours: 1), absorbed: 2.7, method: 'joint');
    await dbRun(tester, () => app.db.addTimedNote(experienceId: night.id, time: testNow.subtract(const Duration(hours: 3)), note: 'Coming up nicely', colorValue: 0xFF3D9970));
    await dbRun(tester, () => app.db.addRating(experienceId: night.id, time: testNow.subtract(const Duration(hours: 2)), shulgin: 'plus3', scores: {'mood': 8}));
    final older = await dbRun(
      tester,
      () => app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(days: 9)), title: 'Quiet weekend'),
    );
    await dbRun(
      tester,
      () => app.db.addIngestion(experience: older, substanceKey: 'lsd', route: 'sublingual', time: testNow.subtract(const Duration(days: 9)), dose: 100, unit: 'µg'),
    );
    final bobNight = await dbRun(tester, () => app.db.addExperience(personId: bob.id, sortDate: testNow.subtract(const Duration(hours: 1)), title: "Bob's evening"));
    await dbRun(
      tester,
      () => app.db.addIngestion(experience: bobNight, substanceKey: 'ketamine', route: 'insufflated', time: testNow.subtract(const Duration(hours: 1)), dose: 40, unit: 'mg'),
    );

    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: key, child: app.widget));
      await settle(tester, rounds: 6);
    }

    // Wide desktop layout
    await show(const Size(1280, 800));
    await _capture(tester, key, '01_journal_desktop');
    await tester.tap(find.text('Saturday night'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, '02_experience_desktop');
    await tester.pageBack();
    await settle(tester);

    // Phone layout
    await show(const Size(412, 892));
    await _capture(tester, key, '03_journal_phone');
    await tester.tap(find.text('Saturday night'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, '04_experience_phone');
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await _capture(tester, key, '05_compounds_phone');
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await _capture(tester, key, '06_settings_phone');
    await tester.tap(find.text('Journal'));
    await settle(tester);

    // Add flow: interaction warning, then the cannabis dose editor.
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-ketamine');
    await tapKey(tester, 'route-insufflated');
    await _capture(tester, key, '07_warning_phone');
    await tester.pageBack();
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    await tapKey(tester, 'compound-cannabis');
    await tapKey(tester, 'route-smoked');
    await tapKey(tester, 'acknowledge'); // cannabis with alcohol is a caution
    await tapKey(tester, 'primary-action');
    await tester.enterText(find.byKey(const ValueKey('cannabis-grams')), '0.1');
    await tester.enterText(find.byKey(const ValueKey('cannabis-thc')), '15');
    await settle(tester, rounds: 3);
    await _capture(tester, key, '08_cannabis_dose_phone');

    await disposeApp(tester, app);
  });
}
