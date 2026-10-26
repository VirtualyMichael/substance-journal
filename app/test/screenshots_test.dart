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

import 'package:substance_journal_app/data/database.dart';

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

  testWidgets('render custom units and editing', skip: skip != null, (tester) async {
    await _loadFonts();
    final key = GlobalKey();
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final unit = await dbRun(
      tester,
      () => app.db.addCustomUnit(
        substanceKey: 'mdma',
        route: 'oral',
        name: 'Blue Superman',
        unitSingular: 'pill',
        unitPlural: 'pills',
        doseOfOneUnit: 120,
        doseStdDev: 15,
        originalUnit: 'mg',
        isEstimate: true,
      ),
    );
    final exp = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: testNow, title: 'Festival'));
    final ing = await dbRun(
      tester,
      () => app.db.addIngestion(
        experience: exp,
        substanceKey: 'mdma',
        route: 'oral',
        time: testNow.subtract(const Duration(hours: 1)),
        dose: 240,
        unit: 'mg',
        doseIsEstimate: true,
        customUnitId: unit.id,
        details: {'unitCount': 2.0, 'unitSingular': 'pill', 'unitPlural': 'pills', 'dosePerUnit': 120.0, 'unitName': 'Blue Superman'},
      ),
    );
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: key, child: app.widget));
    await settle(tester, rounds: 6);

    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-mdma');
    await tapKey(tester, 'custom-unit-${unit.id}');
    await tester.enterText(find.byKey(const ValueKey('unit-count')), '2');
    await settle(tester, rounds: 3);
    await _capture(tester, key, '09_custom_unit_dose_phone');
    await tester.pageBack();
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Festival'));
    await settle(tester, rounds: 6);
    await tapKey(tester, 'ingestion-${ing.id}');
    await _capture(tester, key, '10_edit_ingestion_phone');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await tapKey(tester, 'add-custom-compound');
    await _capture(tester, key, '11_custom_compound_dialog_phone');

    await disposeApp(tester, app);
  });

  testWidgets('render calendar and Alcohol mode', skip: skip != null, (tester) async {
    await _loadFonts();
    final key = GlobalKey();
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final bob = await dbRun(tester, () => app.db.addPerson('Bob'));
    final sam = await dbRun(tester, () => app.db.addPerson('Sam'));
    await dbRun(tester, app.db.ensureDefaultDrinkPresets);

    // Calendar: three people on the same evening, plus some older days.
    Future<void> evening(Person p, String title, Duration ago, String substance, String route, double dose, String unit) async {
      final exp = await dbRun(tester, () => app.db.addExperience(personId: p.id, sortDate: testNow.subtract(ago), title: title));
      await dbRun(
        tester,
        () => app.db.addIngestion(experience: exp, substanceKey: substance, route: route, time: testNow.subtract(ago), dose: dose, unit: unit),
      );
    }

    await evening(me, 'Saturday night', const Duration(hours: 4), 'mdma', 'oral', 100, 'mg');
    await evening(bob, "Bob's evening", const Duration(hours: 2), 'ketamine', 'insufflated', 40, 'mg');
    await evening(sam, "Sam's night", const Duration(minutes: 40), 'lsd', 'sublingual', 100, 'µg');
    await evening(me, 'Quiet weekend', const Duration(days: 9), 'lsd', 'sublingual', 100, 'µg');
    await evening(me, 'Garden day', const Duration(days: 15), 'cannabis', 'smoked', 2.7, 'mg');
    await evening(bob, 'Friday', const Duration(days: 15), 'alcohol', 'oral', 25, 'g');

    // Alcohol: a few weeks of drinks for me.
    for (final (daysAgo, count) in [(0, 3), (1, 2), (3, 4), (5, 1), (8, 5), (9, 2), (12, 3), (15, 6), (20, 2), (24, 4)]) {
      for (var i = 0; i < count; i++) {
        final at = DateTime(testNow.year, testNow.month, testNow.day - daysAgo, 18).add(Duration(minutes: i * 35 + (daysAgo == 0 ? 0 : 60)));
        if (daysAgo == 0 && at.isAfter(testNow)) continue;
        await dbRun(
          tester,
          () => app.db.logDrink(personId: me.id, at: at, volume: i.isEven ? 12 : 5, volumeUnit: 'oz', abvPercent: i.isEven ? 5 : 12, name: i.isEven ? 'Beer - 12 oz 5%' : 'Wine - 5 oz 12%'),
        );
      }
    }

    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: key, child: app.widget));
      await settle(tester, rounds: 6);
    }

    await show(const Size(1280, 800));
    await tester.tap(find.text('Calendar'));
    await settle(tester, rounds: 5);
    await _capture(tester, key, '12_calendar_desktop');
    await tapKey(tester, 'day-2026-7-3');
    await _capture(tester, key, '13_calendar_day_sheet');
    await tester.tapAt(const Offset(40, 40)); // dismiss the sheet
    await settle(tester);

    await dbRun(tester, () => app.db.setSetting('alcoholMode', 'true'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, '14_alcohol_today_desktop');

    await show(const Size(412, 892));
    await tapKey(tester, 'mode-toggle'); // back to full, then on again to reset the tab
    await tapKey(tester, 'mode-toggle');
    await _capture(tester, key, '15_alcohol_today_phone');
    await tester.tap(find.text('Analytics'));
    await settle(tester, rounds: 6);
    await _capture(tester, key, '16_alcohol_analytics_phone');
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await settle(tester);
    await _capture(tester, key, '17_alcohol_analytics_phone_2');
    await tester.tap(find.text('History'));
    await settle(tester, rounds: 4);
    await _capture(tester, key, '18_alcohol_history_phone');

    await disposeApp(tester, app);
  });
}
