import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/custom_substances.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/pw_journal_import.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/providers.dart';

import 'helpers.dart';

final _t0 = DateTime(2026, 6, 6, 20, 0);
int ms(DateTime t) => t.millisecondsSinceEpoch;

/// A small synthetic export in the shape PsychonautWiki Journal writes.
String exportJson() => jsonEncode({
      'experiences': [
        {
          'title': 'Festival night',
          'text': 'Went well',
          'creationDate': ms(_t0),
          'sortDate': ms(_t0),
          'isFavorite': true,
          'location': {'name': 'The field', 'latitude': 51.5, 'longitude': -0.12},
          'ingestions': [
            {
              'substanceName': 'LSD',
              'time': ms(_t0),
              'administrationRoute': 'ORAL',
              'dose': 100.0,
              'isDoseAnEstimate': false,
              'units': 'µg',
              'notes': 'blotter',
              'stomachFullness': 'QUARTERFULL',
            },
            {
              'substanceName': 'Diazepam',
              'time': ms(_t0.add(const Duration(hours: 5))),
              'administrationRoute': 'ORAL',
              'dose': 10.0,
              'isDoseAnEstimate': true,
              'estimatedDoseStandardDeviation': 1.0,
              'units': 'mg',
              'customUnitId': 7,
            },
            {
              'substanceName': 'Mystery powder',
              'time': ms(_t0.add(const Duration(hours: 1))),
              'administrationRoute': 'INSUFFLATED',
              'dose': 20.0,
              'units': 'mg',
            },
            {
              'substanceName': 'Ketamine',
              'time': ms(_t0.add(const Duration(hours: 2))),
              'administrationRoute': 'INSUFFLATED',
              'dose': 30.0,
              'units': 'mg',
              'consumerName': 'Alex',
            },
          ],
          'timedNotes': [
            {'time': ms(_t0.add(const Duration(hours: 3))), 'note': 'Peaking', 'color': 'PINK', 'isPartOfTimeline': true},
          ],
          'ratings': [
            {'time': ms(_t0.add(const Duration(hours: 4))), 'option': 'THREEPLUS'},
            {'time': ms(_t0.add(const Duration(hours: 6))), 'option': 'PLUSMINUS'},
          ],
        },
        {
          'title': 'Quiet one',
          'creationDate': ms(_t0.add(const Duration(days: 3))),
          'ingestions': [
            {'substanceName': 'Cannabis', 'time': ms(_t0.add(const Duration(days: 3))), 'administrationRoute': 'SMOKED', 'dose': 5.0, 'units': 'mg'},
            {'substanceName': 'Broken', 'administrationRoute': 'ORAL'},
          ],
        },
      ],
      'customSubstances': [
        {'id': 1, 'name': 'Mystery powder', 'units': 'mg', 'description': 'Unlabelled'},
      ],
      'customUnits': [
        {
          'id': 7,
          'substanceName': 'Diazepam',
          'name': 'Blue pill',
          'administrationRoute': 'ORAL',
          'dose': 5.0,
          'estimatedDoseStandardDeviation': 0.5,
          'isEstimate': true,
          'isArchived': false,
          'unit': 'pill',
          'unitPlural': 'pills',
          'originalUnit': 'mg',
          'note': '',
        },
      ],
    });

ReferenceRepository fullReference() => ReferenceRepository(
      [
        ...parseSubstances(File('assets/data/substances.json').readAsStringSync()),
        ...parseSubstances(File('assets/data/substances_extra.json').readAsStringSync()),
      ],
      interactionPairs: const [],
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  group('parsing', () {
    test('reads experiences, ingestions, notes, ratings, custom units and reports bad rows', () {
      final export = parsePwJournalJson(exportJson());
      expect(export.experiences, hasLength(2));
      expect(export.ingestionCount, 5); // the row with no time is dropped
      expect(export.problems, hasLength(1));
      expect(export.problems.single, contains('ingestion 2'));
      expect(export.noteCount, 1);
      expect(export.ratingCount, 2);
      expect(export.consumers, {'Alex'});
      expect(export.customSubstances.single.name, 'Mystery powder');
      expect(export.customUnits.single.dose, 5.0);

      final first = export.experiences.first;
      expect(first.isFavorite, isTrue);
      expect(first.locationName, 'The field');
      expect(first.latitude, 51.5);
      expect(first.ingestions.first.route, 'oral');
      expect(first.ingestions.first.stomach, 'quarter');
      expect(first.ratings.map((r) => r.shulgin), ['plus3', 'plusMinus']);
      expect(first.notes.single.colorName, 'PINK');
    });

    test('rejects files that are not exports', () {
      expect(() => parsePwJournalJson('nope'), throwsA(isA<PwImportException>()));
      expect(() => parsePwJournalJson('{"hello": 1}'), throwsA(isA<PwImportException>()));
      expect(() => parsePwJournalJson('[]'), throwsA(isA<PwImportException>()));
    });

    test('names are matched to the catalog, with custom compounds for the rest', () {
      final reference = fullReference();
      expect(catalogKeyFor('LSD', reference), 'lsd');
      expect(catalogKeyFor('Psilocybin mushrooms', reference), 'psilocybin_mushrooms');
      expect(catalogKeyFor('Diazepam', reference), 'diazepam');
      expect(catalogKeyFor('valium', reference), 'diazepam'); // a common name
      expect(catalogKeyFor('Mystery powder', reference), isNull);
    });
  });

  group('importing', () {
    test('everything lands under the right person, with units and notes', () async {
      final me = await db.ensureDefaultPerson();
      final result = await importPwJournal(db, parsePwJournalJson(exportJson()), fullReference());

      expect(result.experiencesImported, 2);
      expect(result.ingestions, 5);
      expect(result.notes, 1);
      expect(result.ratings, 2);
      expect(result.peopleCreated, ['Alex']);
      expect(result.customCompoundsCreated, ['Mystery powder']);
      expect(result.customUnitsCreated, 1);

      final mine = await db.ingestionsForPerson(me.id);
      expect(mine.map((i) => i.substanceKey), containsAll(['lsd', 'diazepam', 'cannabis']));
      expect(mine.where((i) => isCustomKey(i.substanceKey)), hasLength(1));
      final lsd = mine.firstWhere((i) => i.substanceKey == 'lsd');
      expect(lsd.dose, 100);
      expect(lsd.unit, 'µg');
      expect(lsd.stomachFullness, 'quarter');
      expect(lsd.notes, 'blotter');

      final alex = (await db.activePeople()).firstWhere((p) => p.name == 'Alex');
      final theirs = await db.ingestionsForPerson(alex.id);
      expect(theirs.single.substanceKey, 'ketamine');
      expect(theirs.single.route, 'insufflated');

      // The custom unit is linked, not left pointing at the old numeric id.
      final unit = (await db.watchCustomUnits().first).single;
      expect(unit.name, 'Blue pill');
      expect(unit.doseOfOneUnit, 5.0);
      final diazepam = mine.firstWhere((i) => i.substanceKey == 'diazepam');
      expect(diazepam.customUnitId, unit.id);
      expect(diazepam.doseIsEstimate, isTrue);

      final experiences = await db.watchExperiences(me.id).first;
      final festival = experiences.firstWhere((e) => e.title == 'Festival night');
      expect(festival.isFavorite, isTrue);
      expect(festival.locationName, 'The field');
      expect(festival.notes, 'Went well');
      final notes = await db.watchTimedNotes(festival.id).first;
      expect(notes.single.note, 'Peaking');
      expect(notes.single.colorValue, noteColorFor('PINK'));
      expect((await db.watchRatings(festival.id).first).map((r) => r.shulgin), ['plus3', 'plusMinus']);
      // Alex's doses are in their own experience, never mixed into mine.
      expect((await db.watchExperiences(alex.id).first).single.title, 'Festival night');
    });

    test('importing the same file twice adds nothing', () async {
      final me = await db.ensureDefaultPerson();
      final export = parsePwJournalJson(exportJson());
      final reference = fullReference();
      await importPwJournal(db, export, reference);
      final again = await importPwJournal(db, export, reference);

      expect(again.experiencesImported, 0);
      expect(again.experiencesSkipped, 2);
      expect(again.ingestions, 0);
      expect(again.customUnitsCreated, 0);
      expect(again.customCompoundsCreated, isEmpty);
      expect(await db.ingestionsForPerson(me.id), hasLength(4));
      expect(await db.watchExperiences(me.id).first, hasLength(2));
    });

    test('importing again never overwrites, resurrects or duplicates what you changed', () async {
      final me = await db.ensureDefaultPerson();
      final export = parsePwJournalJson(exportJson());
      final reference = fullReference();
      await importPwJournal(db, export, reference);
      final rows = await db.ingestionsForPerson(me.id);
      final lsd = rows.firstWhere((r) => r.substanceKey == 'lsd');
      final cannabis = rows.firstWhere((r) => r.substanceKey == 'cannabis');
      await db.updateIngestion(lsd.id, time: lsd.time.add(const Duration(hours: 1)), notes: 'edited', dose: const Value(75.0));
      await db.setIngestionDeleted(cannabis.id, true);

      final again = await importPwJournal(db, export, reference);
      expect(again.ingestions, 0);
      final after = await db.ingestionsForPerson(me.id);
      expect(after.where((r) => r.substanceKey == 'cannabis'), isEmpty);
      final edited = after.where((r) => r.substanceKey == 'lsd').single;
      expect(edited.notes, 'edited');
      expect(edited.dose, 75.0);
    });

    test('a failure part-way changes nothing', () async {
      final me = await db.ensureDefaultPerson();
      final export = PwExport(experiences: [
        PwExperience(
          title: 'x',
          text: '',
          sortDate: _t0,
          ingestions: [PwIngestion(substanceName: 'LSD', route: 'oral', time: _t0, dose: 100, unit: 'µg')],
          ratings: const [PwRating(time: null, shulgin: 'plus1')],
        ),
      ]);
      // A reference with no people set up fails inside the transaction only if people are missing;
      // here we simulate by deleting the default person's row first.
      await (db.delete(db.people)).go();
      await expectLater(importPwJournal(db, export, fullReference()), throwsA(isA<StateError>()));
      expect(await db.ingestionsForPerson(me.id), isEmpty);
    });
  });

  group('other export layouts and choices', () {
    String layoutJson() => jsonEncode({
          'experiences': [
            {
              'title': 'Morning',
              'sortDate': ms(_t0),
              'ingestions': [
                {'ingestion': {'substanceName': 'LSD', 'time': ms(_t0), 'administrationRoute': 'ORAL', 'dose': 50.0, 'units': 'µg'}},
              ],
            },
            {
              'title': 'Afternoon',
              'sortDate': ms(_t0.add(const Duration(hours: 4))),
              'ingestions': [
                {'customSubstanceId': 1, 'time': ms(_t0.add(const Duration(hours: 4))), 'administrationRoute': 'SMOKED', 'dose': 1.0, 'units': 'mg'},
                {'dose': 1.0, 'time': ms(_t0), 'someOtherField': true},
              ],
            },
          ],
          'customSubstances': [
            {'id': 1, 'name': 'Home blend', 'units': 'mg'},
          ],
        });

    test('wrapped doses and custom-substance ids are read; unreadable ones name their fields, not values', () {
      final export = parsePwJournalJson(layoutJson());
      expect(export.ingestionCount, 2);
      expect(export.experiences.last.ingestions.single.substanceName, 'Home blend');
      expect(export.problems.single, contains('no substance name'));
      expect(export.problems.single, contains('someOtherField'));
      expect(export.ingestionKeys, contains('customSubstanceId'));
    });

    test('doses close together become one experience, and can be kept apart', () async {
      final me = await db.ensureDefaultPerson();
      final export = parsePwJournalJson(layoutJson());
      final reference = fullReference();
      final plan = PwImportPlan(export, reference); // combine is on by default
      final result = await importPwJournal(db, export, reference, plan: plan);
      expect(result.experiencesImported, 2);
      expect(result.experiencesCreated, 1);
      final experiences = await db.watchExperiences(me.id).first;
      expect(experiences, hasLength(1));
      expect(await db.watchIngestionsForExperience(experiences.single.id).first, hasLength(2));

      final apart = AppDatabase.memory();
      addTearDown(apart.close);
      await apart.ensureDefaultPerson();
      final plan2 = PwImportPlan(export, reference)..combine = false;
      final result2 = await importPwJournal(apart, export, reference, plan: plan2);
      expect(result2.experiencesCreated, 2);
    });

    test('choices: skip experiences, remap a compound, change a route for one dose', () async {
      final me = await db.ensureDefaultPerson();
      final export = parsePwJournalJson(exportJson());
      final reference = fullReference();
      final plan = PwImportPlan(export, reference)
        ..selected.remove(1) // leave out "Quiet one"
        ..compoundByName['mystery powder'] = const PwCompound.reference('ketamine')
        ..routeByGroup[PwImportPlan.groupKey('LSD', 'oral')] = 'sublingual';
      final dose = export.experiences.first.ingestions.firstWhere((i) => i.substanceName == 'Diazepam');
      plan.overrides[dose.id] = const PwOverride(route: 'rectal');
      final result = await importPwJournal(db, export, reference, plan: plan);

      expect(result.experiencesImported, 1);
      expect(result.customCompoundsCreated, isEmpty);
      final mine = await db.ingestionsForPerson(me.id);
      expect(mine.any((i) => i.substanceKey == 'cannabis'), isFalse);
      expect(mine.firstWhere((i) => i.substanceKey == 'lsd').route, 'sublingual');
      expect(mine.firstWhere((i) => i.substanceKey == 'diazepam').route, 'rectal');
      expect(mine.where((i) => i.substanceKey == 'ketamine' && i.dose == 20), hasLength(1)); // the remapped powder
    });

    test('choices are saved and reloaded for the next import', () {
      final export = parsePwJournalJson(exportJson());
      final reference = fullReference();
      final plan = PwImportPlan(export, reference)
        ..compoundByName['mystery powder'] = const PwCompound.reference('ketamine')
        ..routeByGroup['lsd|oral'] = 'sublingual';
      final next = PwImportPlan(export, reference, saved: jsonDecode(jsonEncode(plan.toSaved())) as Map<String, dynamic>);
      expect(next.compoundByName['mystery powder'], const PwCompound.reference('ketamine'));
      expect(next.routeByGroup['lsd|oral'], 'sublingual');
    });

    test('a route the reference lacks borrows the nearest one', () {
      final dmt = fullReference().byKey['dmt']!; // only "smoked" is published
      expect(dmt.nearestRoute('insufflated')?.route, 'smoked');
      expect(dmt.nearestRoute('vaporized')?.route, 'smoked');
      final lsd = fullReference().byKey['lsd']!; // only "sublingual"
      expect(lsd.nearestRoute('oral')?.route, 'sublingual');
    });
  });

  group('screen', () {
    testWidgets('choosing a file shows a summary and imports it on confirmation', (tester) async {
      final dir = Directory.systemTemp.createTempSync('pw_export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/journal.json')..writeAsStringSync(exportJson());

      final built = await buildTestApp(tester);
      final me = await dbRun(tester, built.db.ensureDefaultPerson);
      usePhoneScreen(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(built.db),
          referenceProvider.overrideWithValue(fullReference()),
          interactionPairsProvider.overrideWithValue(const []),
          clockProvider.overrideWithValue(() => testNow),
          pwFilePickerProvider.overrideWithValue(() async => file.path),
        ],
        child: (built.widget as ProviderScope).child,
      ));
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);

      final button = find.byKey(const ValueKey('import-pw-file'));
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
      await settle(tester);
      expect(find.textContaining('2 experiences (5 ingestions, 1 timed notes, 2 ratings)'), findsOneWidget);
      expect(find.textContaining('People: Alex'), findsOneWidget);
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), isEmpty);

      await tapKey(tester, 'import-confirm');
      await settle(tester, rounds: 12);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.textContaining('2 experiences imported'), findsOneWidget);
      await tapKey(tester, 'import-done');
      expect(await dbRun(tester, () => built.db.ingestionsForPerson(me.id)), hasLength(4));
      await disposeApp(tester, built);
    });
  });
}
