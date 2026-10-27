import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/custom_substances.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/ui/add/dose_widgets.dart';
import 'package:substance_journal_app/ui/timeline/timeline_data.dart';

import 'helpers.dart';

CustomUnitChoice pill({double dose = 120, double? std, bool estimate = false}) => CustomUnitChoice(
      id: 'u1',
      name: 'Blue Superman',
      singular: 'pill',
      plural: 'pills',
      dosePerUnit: dose,
      stdDevPerUnit: std,
      isEstimate: estimate,
    );

void main() {
  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('custom compounds: create, edit, soft delete, undo', () async {
      final a = await db.addCustomSubstance(name: 'Magnesium', units: 'mg', onsetMinutes: 45, durationHours: 6);
      expect(a.name, 'Magnesium');
      expect(a.onsetMinutes, 45);
      expect(a.durationHours, 6);

      await db.updateCustomSubstance(a.id, name: 'Magnesium glycinate', units: 'g');
      var rows = await db.watchCustomSubstances().first;
      expect(rows.single.name, 'Magnesium glycinate');
      expect(rows.single.units, 'g');
      expect(Hlc.parse(rows.single.hlc) > Hlc.parse(a.hlc), isTrue);

      await db.setCustomSubstanceDeleted(a.id, true);
      rows = await db.watchCustomSubstances().first;
      expect(rows.single.deleted, isTrue); // still listed, so old ingestions keep a name
      await db.setCustomSubstanceDeleted(a.id, false);
      expect((await db.watchCustomSubstances().first).single.deleted, isFalse);
    });

    test('custom units: create, edit, archive, delete', () async {
      final u = await db.addCustomUnit(
        substanceKey: 'mdma',
        route: 'oral',
        name: 'Blue Superman',
        unitSingular: 'pill',
        doseOfOneUnit: 120,
        originalUnit: 'mg',
        isEstimate: true,
        doseStdDev: 15,
      );
      expect(u.unitPlural, isNull);
      await db.updateCustomUnit(u.id, doseOfOneUnit: 130, unitPlural: const Value('pills'), isArchived: true);
      var rows = await db.watchCustomUnits().first;
      expect(rows.single.doseOfOneUnit, 130);
      expect(rows.single.unitPlural, 'pills');
      expect(rows.single.isArchived, isTrue);
      expect(rows.single.doseStdDev, 15); // untouched
      await db.setCustomUnitDeleted(u.id, true);
      expect(await db.watchCustomUnits().first, isEmpty);
      await db.setCustomUnitDeleted(u.id, false);
      expect(await db.watchCustomUnits().first, hasLength(1));
    });

    test('an ingestion can be moved to another compound and route', () async {
      final me = await db.ensureDefaultPerson();
      final exp = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1));
      final ing = await db.addIngestion(
        experience: exp,
        substanceKey: 'nicotine',
        route: 'buccal',
        time: DateTime(2026, 7, 1, 20),
        dose: 2,
        unit: 'mg',
        customUnitId: 'u1',
        details: {'unitCount': 1},
      );
      await db.updateIngestion(
        ing.id,
        substanceKey: 'ketamine',
        route: 'insufflated',
        unit: 'mg',
        dose: const Value(40.0),
        customUnitId: const Value(null),
        detailsJson: '{}',
      );
      final row = (await db.ingestionsForPerson(me.id)).single;
      expect(row.substanceKey, 'ketamine');
      expect(row.route, 'insufflated');
      expect(row.dose, 40);
      expect(row.customUnitId, isNull);
      expect(row.detailsJson, '{}');
      expect(row.time, DateTime(2026, 7, 1, 20)); // untouched
    });

    test('version 1 databases upgrade without losing custom compounds', () async {
      final legacy = AppDatabase(
        NativeDatabase.memory(setup: (raw) {
          raw.execute('''
            CREATE TABLE custom_substances (
              id TEXT NOT NULL PRIMARY KEY, hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
              name TEXT NOT NULL, units TEXT NOT NULL, description TEXT NOT NULL DEFAULT ''
            )''');
          // Version 1 already had the peers table (v3 adds a column to it).
          raw.execute('''
            CREATE TABLE peers (
              device_id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
              last_known_address TEXT, last_synced_hlc TEXT NOT NULL DEFAULT '', paired_at INTEGER NOT NULL
            )''');
          raw.execute("INSERT INTO custom_substances (id, hlc, name, units) VALUES ('old', '1-0-x', 'Old compound', 'mg')");
          raw.execute('PRAGMA user_version = 1');
        }),
        deviceId: 'legacy',
      );
      addTearDown(legacy.close);
      final rows = await legacy.watchCustomSubstances().first;
      expect(rows.single.name, 'Old compound');
      expect(rows.single.onsetMinutes, 30); // new columns get their defaults
      expect(rows.single.durationHours, 4.0);
      // The sync key column was added to peers too.
      final peers = await legacy.select(legacy.peers).get();
      expect(peers, isEmpty);
    });
  });

  group('custom compound as a substance', () {
    CustomSubstance row({int onset = 30, double hours = 4}) => CustomSubstance(
          id: 'abc',
          hlc: 'x',
          deleted: false,
          name: 'Magnesium',
          units: 'mg',
          description: '',
          onsetMinutes: onset,
          durationHours: hours,
        );

    test('has a key prefix, every route, the chosen unit and no dose bands', () {
      final s = substanceFromCustom(row());
      expect(s.key, 'custom:abc');
      expect(isCustomKey(s.key), isTrue);
      expect(isCustomKey('lsd'), isFalse);
      expect(s.roas.map((r) => r.route), customRoutes);
      expect(s.roas.every((r) => r.unit == 'mg'), isTrue);
      expect(s.roas.first.id, 'custom:abc:oral');
      expect(s.roas.first.doseCommon, isNull);
      expect(classifyDose(s.roas.first, 5), isNull);
      expect(s.hasTolerance, isFalse);
      expect(s.safetyNotes, isNotEmpty);
    });

    test('timing phases add up to the chosen duration', () {
      final phases = customDurationPhases(onsetMinutes: 30, durationHours: 4);
      double minutes(String p) => phases.firstWhere((d) => d.phase == p).maxMinutes!;
      expect(minutes('onset'), 30);
      expect(minutes('onset') + minutes('comeup') + minutes('peak') + minutes('offset'), closeTo(240, 1e-9));
      expect(minutes('total'), 240);
      // The onset is capped so it can never exceed the whole duration.
      expect(customDurationPhases(onsetMinutes: 999, durationHours: 1).firstWhere((d) => d.phase == 'onset').maxMinutes, 60);
    });

    test('a custom compound draws on the timeline for its whole duration', () {
      final reference = loadReference().withCustom(active: [substanceFromCustom(row(onset: 30, hours: 4))]);
      final start = DateTime(2026, 7, 3, 20);
      final ingestion = Ingestion(
        id: 'i',
        hlc: 'x',
        deleted: false,
        experienceId: 'e',
        personId: 'p',
        substanceKey: 'custom:abc',
        route: 'oral',
        time: start,
        endTime: null,
        dose: 200,
        unit: 'mg',
        doseIsEstimate: false,
        doseStdDev: null,
        stomachFullness: null,
        customUnitId: null,
        productId: null,
        absorbedMg: null,
        method: null,
        notes: '',
        detailsJson: '{}',
      );
      final series = buildTimelineSeries(ingestions: [ingestion], reference: reference, now: start);
      expect(series, hasLength(1));
      expect(series.single.label, 'Magnesium 200 mg');
      expect(series.single.end.difference(start), const Duration(hours: 4));
      expect(series.single.peak, 1.0); // no dose bands: the curve is drawn at a common-dose height
    });

    test('a deleted custom compound still resolves for old ingestions but is not offered', () {
      final deleted = substanceFromCustom(row());
      final reference = loadReference().withCustom(active: const [], archived: [deleted]);
      expect(reference.byKey['custom:abc']?.name, 'Magnesium');
      expect(reference.substances.any((s) => s.key == 'custom:abc'), isFalse);
    });
  });

  group('dose input with a custom unit', () {
    final reference = loadReference();
    final oral = reference.byKey['mdma']!.route('oral')!;

    test('the dose is the count times the unit dose, and the dose band follows it', () {
      final input = const DoseInput.empty().copyWith(unit: pill(), unitCountText: '2');
      expect(input.dose, 240);
      expect(input.validate(oral), isNull);
      expect(classifyDose(oral, input.dose!), DoseClass.heavy);
      expect(const DoseInput.empty().copyWith(unit: pill(), unitCountText: '0.5').dose, 60);
    });

    test('a missing or non-positive count is rejected with the unit name', () {
      final input = const DoseInput.empty().copyWith(unit: pill());
      expect(input.validate(oral), 'Enter how many pills.');
      expect(input.copyWith(unitCountText: '0').validate(oral), 'Enter how many pills.');
      expect(input.copyWith(unitCountText: 'abc').validate(oral), 'Enter how many pills.');
    });

    test('storage records the unit, the count and a combined uncertainty', () {
      final input = const DoseInput.empty().copyWith(unit: pill(std: 15, estimate: true), unitCountText: '2');
      final stored = input.toStorage(oral);
      expect(stored.dose, 240);
      expect(stored.unit, 'mg');
      expect(stored.isEstimate, isTrue);
      expect(stored.stdDev, 30); // two pills from one batch: uncertainties add
      expect(stored.customUnitId, 'u1');
      expect(stored.details['unitCount'], 2);
      expect(stored.details['unitPlural'], 'pills');
    });

    test('plain doses are unaffected and clearing the unit goes back to them', () {
      final plain = const DoseInput.empty().copyWith(text: '80');
      expect(plain.dose, 80);
      expect(plain.toStorage(oral).customUnitId, isNull);
      final withUnit = plain.copyWith(unit: pill(), unitCountText: '1');
      expect(withUnit.dose, 120);
      expect(withUnit.copyWith(clearUnit: true).dose, 80);
    });

    test('pluralising', () {
      expect(pluralize('pill'), 'pills');
      expect(pluralize('drops'), 'drops');
    });
  });

  group('screens', () {
    testWidgets('add a custom compound, then log it with a route and dose', (tester) async {
      final app = await buildTestApp(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Compounds'));
      await settle(tester);

      await tapKey(tester, 'add-custom-compound');
      await tester.enterText(find.byKey(const ValueKey('custom-name')), 'Magnesium');
      await tapKey(tester, 'custom-save');
      expect(find.text('Magnesium'), findsOneWidget);
      expect(find.text('Custom'), findsNWidgets(2)); // the list subtitle and the category filter chip

      await tester.tap(find.text('Magnesium'));
      await settle(tester);
      expect(find.byKey(const ValueKey('custom-timing')), findsOneWidget);
      await tapKey(tester, 'log-this');
      await tapKey(tester, 'route-oral');
      await tester.enterText(find.byKey(const ValueKey('dose-field')), '200');
      await settle(tester, rounds: 2);
      await tapKey(tester, 'primary-action');
      await tapKey(tester, 'primary-action');

      final person = (await dbRun(tester, app.db.activePeople)).single;
      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
      expect(row.substanceKey, startsWith('custom:'));
      expect(row.route, 'oral');
      expect(row.dose, 200);
      expect(row.unit, 'mg');
      expect(find.text('Magnesium'), findsWidgets); // on the experience page, with a timeline legend
      expect(find.textContaining('Magnesium 200 mg'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('the custom compound dialog validates its fields', (tester) async {
      final app = await buildTestApp(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Compounds'));
      await settle(tester);
      await tapKey(tester, 'add-custom-compound');
      await tapKey(tester, 'custom-save');
      expect(find.text('Give the compound a name.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('custom-name')), 'Test');
      await tester.enterText(find.byKey(const ValueKey('custom-hours')), '0.1');
      await tester.enterText(find.byKey(const ValueKey('custom-onset')), '30');
      await tapKey(tester, 'custom-save');
      expect(find.text('Onset must be shorter than the whole duration.'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('log 2 pills from a saved custom unit', (tester) async {
      final app = await buildTestApp(tester);
      final me = await dbRun(tester, app.db.ensureDefaultPerson);
      final unit = await dbRun(
        tester,
        () => app.db.addCustomUnit(
          substanceKey: 'mdma',
          route: 'oral',
          name: 'Blue Superman',
          unitSingular: 'pill',
          doseOfOneUnit: 120,
          originalUnit: 'mg',
        ),
      );
      await startApp(tester, app);

      await tapKey(tester, 'journal-add');
      await tapKey(tester, 'compound-mdma');
      expect(find.text('MDMA dose'), findsOneWidget); // MDMA has one route
      await tapKey(tester, 'custom-unit-${unit.id}');
      expect(find.byKey(const ValueKey('dose-field')), findsNothing); // the dose now comes from the unit
      await tester.enterText(find.byKey(const ValueKey('unit-count')), '2');
      await settle(tester, rounds: 2);
      expect(find.text('2 pills = 240 mg'), findsOneWidget);
      expect(find.text('About a heavy dose'), findsOneWidget);

      await tapKey(tester, 'primary-action');
      await tapKey(tester, 'primary-action');

      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(row.dose, 240);
      expect(row.customUnitId, unit.id);
      expect(row.detailsJson, contains('"unitCount":2'));
      expect(find.textContaining('2 pills (240 mg)'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('create a custom unit while logging, and it is selected for you', (tester) async {
      final app = await buildTestApp(tester);
      await startApp(tester, app);
      await tapKey(tester, 'journal-add');
      await tapKey(tester, 'compound-mdma');

      await tapKey(tester, 'new-custom-unit');
      await tapKey(tester, 'unit-save');
      expect(find.text('Give the unit a name.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('unit-name')), 'Pink Tesla');
      await tester.enterText(find.byKey(const ValueKey('unit-dose')), '150');
      await tapKey(tester, 'unit-estimate');
      await tester.enterText(find.byKey(const ValueKey('unit-std')), '20');
      await tapKey(tester, 'unit-save');

      expect(find.byKey(const ValueKey('unit-count')), findsOneWidget);
      expect(find.text('1 pill = 150 mg (estimate)'), findsOneWidget);
      final units = await dbRun(tester, () => app.db.watchCustomUnits().first);
      expect(units.single.name, 'Pink Tesla');
      expect(units.single.isEstimate, isTrue);
      expect(units.single.doseStdDev, 20);
      expect(units.single.route, 'oral');
      await disposeApp(tester, app);
    });

    testWidgets('custom units can be edited, archived and deleted from settings', (tester) async {
      final app = await buildTestApp(tester);
      await dbRun(tester, app.db.ensureDefaultPerson);
      final unit = await dbRun(
        tester,
        () => app.db.addCustomUnit(
          substanceKey: 'mdma',
          route: 'oral',
          name: 'Blue Superman',
          unitSingular: 'pill',
          doseOfOneUnit: 120,
          originalUnit: 'mg',
        ),
      );
      await startApp(tester, app);
      await tester.tap(find.text('Settings'));
      await settle(tester);
      await tapKey(tester, 'manage-units');
      expect(find.text('Blue Superman'), findsOneWidget);
      Finder inCard(String text) => find.descendant(of: find.byKey(ValueKey('unit-${unit.id}')), matching: find.textContaining(text));
      expect(inCard('1 pill = 120 mg'), findsOneWidget);

      await tapKey(tester, 'unit-menu-${unit.id}');
      await tester.tap(find.text('Edit'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('unit-dose')), '125');
      await tapKey(tester, 'unit-save');
      expect(inCard('1 pill = 125 mg'), findsOneWidget);

      await tapKey(tester, 'unit-menu-${unit.id}');
      await tester.tap(find.text('Archive'));
      await settle(tester);
      expect(inCard('archived'), findsOneWidget);

      await tapKey(tester, 'unit-menu-${unit.id}');
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Blue Superman'), findsNothing);
      await disposeApp(tester, app);
    });

    testWidgets('archived units are not offered in the dose step', (tester) async {
      final app = await buildTestApp(tester);
      await dbRun(tester, app.db.ensureDefaultPerson);
      final unit = await dbRun(
        tester,
        () => app.db.addCustomUnit(
          substanceKey: 'mdma',
          route: 'oral',
          name: 'Old pill',
          unitSingular: 'pill',
          doseOfOneUnit: 100,
          originalUnit: 'mg',
        ),
      );
      await dbRun(tester, () => app.db.updateCustomUnit(unit.id, isArchived: true));
      await startApp(tester, app);
      await tapKey(tester, 'journal-add');
      await tapKey(tester, 'compound-mdma');
      expect(find.byKey(ValueKey('custom-unit-${unit.id}')), findsNothing);
      expect(find.byKey(const ValueKey('new-custom-unit')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets("editing an ingestion's compound and route", (tester) async {
      final app = await buildTestApp(tester);
      final me = await dbRun(tester, app.db.ensureDefaultPerson);
      final exp = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: testNow, title: 'Edit me'));
      final nicotine = await dbRun(
        tester,
        () => app.db.addIngestion(
          experience: exp,
          substanceKey: 'nicotine',
          route: 'buccal',
          time: testNow.subtract(const Duration(hours: 1)),
          dose: 2,
          unit: 'mg',
        ),
      );
      await startApp(tester, app);
      await tester.tap(find.text('Edit me'));
      await settle(tester);

      await tapKey(tester, 'ingestion-${nicotine.id}'); // opens the edit dialog
      expect(find.text('Edit ingestion'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-compound')));
      await settle(tester);
      await tester.tap(find.text('Ketamine').last);
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('edit-dose')), '40');
      await tapKey(tester, 'edit-save');

      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(row.substanceKey, 'ketamine');
      expect(row.route, 'insufflated');
      expect(row.unit, 'mg');
      expect(row.dose, 40);
      expect(find.text('Ketamine'), findsWidgets);
      expect(find.text('Nicotine'), findsNothing);
      await disposeApp(tester, app);
    });

    testWidgets('cannabis keeps its compound and route when edited', (tester) async {
      final app = await buildTestApp(tester);
      final me = await dbRun(tester, app.db.ensureDefaultPerson);
      final exp = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: testNow, title: 'Green'));
      final joint = await dbRun(
        tester,
        () => app.db.addIngestion(
          experience: exp,
          substanceKey: 'cannabis',
          route: 'smoked',
          time: testNow.subtract(const Duration(hours: 1)),
          dose: 2.7,
          unit: 'mg',
          absorbedMg: 2.7,
          method: 'joint',
        ),
      );
      await startApp(tester, app);
      await tester.tap(find.text('Green'));
      await settle(tester);
      await tapKey(tester, 'ingestion-${joint.id}');
      expect(find.byKey(const ValueKey('cannabis-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-compound')), findsNothing);
      await disposeApp(tester, app);
    });

    testWidgets('editing a custom-unit ingestion changes the count; changing the compound detaches the unit', (tester) async {
      final app = await buildTestApp(tester);
      final me = await dbRun(tester, app.db.ensureDefaultPerson);
      final exp = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: testNow, title: 'Pills'));
      final unit = await dbRun(
        tester,
        () => app.db.addCustomUnit(
          substanceKey: 'mdma',
          route: 'oral',
          name: 'Blue Superman',
          unitSingular: 'pill',
          unitPlural: 'pills',
          doseOfOneUnit: 120,
          originalUnit: 'mg',
        ),
      );
      final ing = await dbRun(
        tester,
        () => app.db.addIngestion(
          experience: exp,
          substanceKey: 'mdma',
          route: 'oral',
          time: testNow.subtract(const Duration(hours: 1)),
          dose: 120,
          unit: 'mg',
          customUnitId: unit.id,
          details: {'unitCount': 1.0, 'unitSingular': 'pill', 'unitPlural': 'pills', 'dosePerUnit': 120.0, 'unitName': 'Blue Superman'},
        ),
      );
      await startApp(tester, app);
      await tester.tap(find.text('Pills'));
      await settle(tester);
      expect(find.textContaining('1 pill (120 mg)'), findsOneWidget);

      await tapKey(tester, 'ingestion-${ing.id}');
      await tester.enterText(find.byKey(const ValueKey('edit-unit-count')), '3');
      await tapKey(tester, 'edit-save');
      var row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(row.dose, 360);
      expect(row.customUnitId, unit.id);
      expect(find.textContaining('3 pills (360 mg)'), findsOneWidget);

      // Moving it to another compound makes it a plain dose again.
      await tapKey(tester, 'ingestion-${ing.id}');
      await tester.tap(find.byKey(const ValueKey('edit-compound')));
      await settle(tester);
      await tester.tap(find.text('LSD').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('edit-unit-count')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('edit-dose')), '100');
      await tapKey(tester, 'edit-save');
      row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(row.id, ing.id);
      expect(row.substanceKey, 'lsd');
      expect(row.unit, 'µg');
      expect(row.customUnitId, isNull);
      expect(row.detailsJson, '{}');
      await disposeApp(tester, app);
    });

    testWidgets('removing a custom compound keeps its past ingestions readable, and undo brings it back', (tester) async {
      final app = await buildTestApp(tester);
      final me = await dbRun(tester, app.db.ensureDefaultPerson);
      final custom = await dbRun(tester, () => app.db.addCustomSubstance(name: 'Magnesium', units: 'mg'));
      final key = '$customKeyPrefix${custom.id}';
      final exp = await dbRun(tester, () => app.db.addExperience(personId: me.id, sortDate: testNow, title: 'Supplements'));
      await dbRun(
        tester,
        () => app.db.addIngestion(
          experience: exp,
          substanceKey: key,
          route: 'oral',
          time: testNow.subtract(const Duration(hours: 1)),
          dose: 200,
          unit: 'mg',
        ),
      );
      await startApp(tester, app);

      await tester.tap(find.text('Compounds'));
      await settle(tester);
      await tester.tap(find.text('Magnesium'));
      await settle(tester);
      await tapKey(tester, 'custom-menu');
      await tester.tap(find.text('Remove'));
      await settle(tester, rounds: 6);
      expect(find.text('Magnesium'), findsNothing); // gone from the list

      await tester.tap(find.text('Journal'));
      await settle(tester);
      expect(find.widgetWithText(Chip, 'Magnesium'), findsOneWidget); // the old experience still names it

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Undo'));
      await settle(tester, rounds: 8);
      await tester.tap(find.text('Compounds'));
      await settle(tester);
      expect(find.text('Magnesium'), findsOneWidget);
      await disposeApp(tester, app);
    });
  });
}
