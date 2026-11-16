import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/dose_audit.dart';
import 'package:substance_journal_app/data/glossary.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';
import 'package:substance_journal_app/ui/compounds/dose_ladder.dart';

import 'helpers.dart';

final _auditText = File('assets/data/dose_audit.json').readAsStringSync();

List<Substance> _catalog({bool extras = false}) {
  final audited = parseSubstances(File('assets/data/substances.json').readAsStringSync());
  if (!extras) return audited;
  final taken = {for (final s in audited) s.key};
  return [
    ...audited,
    ...parseSubstances(File('assets/data/substances_extra.json').readAsStringSync()).where((s) => !taken.contains(s.key)),
  ];
}

ReferenceRepository _withAudit({bool extras = false}) {
  final substances = _catalog(extras: extras);
  final audit = DoseAudit.tryParse(_auditText)..applyTo(substances);
  return ReferenceRepository(
    substances,
    interactionPairs: parseInteractions(File('assets/data/interactions.json').readAsStringSync()),
    doseAudit: audit,
  );
}

Map<String, dynamic> _entry({Object? threshold = 10, Object? lowMin = 20, Object? heavy = 300}) => {
      'unit': 'µg',
      'threshold': threshold,
      'low': {'min': lowMin, 'max': 75},
      'common': {'min': 75, 'max': 150},
      'high': {'min': 150, 'max': 300},
      'heavy': heavy,
      'sources': [
        {'name': 'PsychonautWiki', 'url': 'https://psychonautwiki.org/wiki/LSD', 'bands_as_published': 'common 75 - 150 µg', 'retrieved': '2026-11-15'},
        {'name': 'Erowid', 'url': 'https://erowid.org/chemicals/lsd/lsd_dose.shtml', 'bands_as_published': 'common 50 - 150 ug', 'retrieved': '2026-11-15'},
      ],
      'agreement': 'minor differences',
      'confidence': 'medium',
      'note': 'test',
    };

String _doc(Map<String, Map<String, dynamic>> routesByKey) => jsonEncode({'version': 1, 'substances': routesByKey});

void main() {
  group('parsing the dose audit overlay', () {
    test('the bundled file parses, every entry matches a catalog route and its ladder rises', () {
      final audit = DoseAudit.tryParse(_auditText);
      expect(audit.isEmpty, isFalse);
      final byKey = {for (final s in _catalog(extras: true)) s.key: s};
      var routes = 0;
      for (final MapEntry(key: key, value: byRoute) in audit.routes.entries) {
        expect(byKey, contains(key), reason: key);
        for (final MapEntry(key: route, value: a) in byRoute.entries) {
          routes++;
          final roa = byKey[key]!.route(route);
          expect(roa, isNotNull, reason: '$key:$route');
          expect(audit.behind(roa!), same(a), reason: '$key:$route unit ${a.unit} vs ${roa.unit}');
          expect(a.sources, isNotEmpty, reason: '$key:$route');
          expect(a.sources.every((s) => s.url.startsWith('https://')), isTrue, reason: '$key:$route');
          final edges = [a.threshold, a.low?.min, a.common?.min, a.high?.min, a.heavy].whereType<double>().toList();
          for (var i = 1; i < edges.length; i++) {
            expect(edges[i], greaterThanOrEqualTo(edges[i - 1]), reason: '$key:$route');
          }
        }
      }
      expect(routes, greaterThan(50));
    });

    test('LSD sublingual has all five bands, cross-checked against PsychonautWiki, Erowid, TripSit and Holze 2021', () {
      final lsd = DoseAudit.tryParse(_auditText).route('lsd', 'sublingual')!;
      expect([lsd.threshold, lsd.low?.min, lsd.low?.max, lsd.common?.min, lsd.common?.max, lsd.high?.min, lsd.high?.max, lsd.heavy],
          [10, 20, 75, 75, 150, 150, 300, 300]);
      final names = lsd.sources.map((s) => s.name).join(' | ');
      for (final n in ['PsychonautWiki', 'Erowid', 'TripSit', 'Holze']) {
        expect(names, contains(n));
      }
      expect(lsd.sources.every((s) => s.bandsAsPublished.isNotEmpty && s.retrieved == '2026-11-15'), isTrue);
    });

    test('a missing, empty or malformed file gives an empty audit and changes nothing', () {
      for (final text in [null, '', '   ', 'not json', '[1, 2]', '{"substances": 3}', '{"version": 1}']) {
        final audit = DoseAudit.tryParse(text);
        expect(audit.isEmpty, isTrue, reason: '$text');
        final substances = _catalog();
        final before = substances.firstWhere((s) => s.key == 'lsd').route('sublingual')!;
        expect(audit.applyTo(substances), 0);
        expect(identical(substances.firstWhere((s) => s.key == 'lsd').route('sublingual'), before), isTrue);
      }
    });

    test('a bad entry is skipped on its own and the good ones are kept', () {
      final audit = DoseAudit.tryParse(_doc({
        'lsd': {'sublingual': _entry()},
        'mdma': {'oral': {..._entry(), 'unit': 'mg', 'threshold': 'lots'}}, // wrong type
        'dmt': {'smoked': {..._entry(), 'unit': 'mg', 'heavy': 5}}, // the ladder falls
        'ketamine': {'oral': {..._entry(), 'unit': 'mg', 'sources': []}}, // nothing to check against
        '2c-b': {'oral': 'nonsense'},
      }));
      expect(audit.routes.keys, ['lsd']);
    });

    test('applying the overlay swaps the bands but keeps the timing, and skips a different unit', () {
      final substances = _catalog();
      final lsdBefore = substances.firstWhere((s) => s.key == 'lsd').route('sublingual')!;
      final audit = DoseAudit.tryParse(_doc({
        'lsd': {'sublingual': _entry(threshold: 12)},
        'mdma': {'oral': {..._entry(), 'unit': 'g'}}, // MDMA is in mg: not applied
      }));
      expect(audit.applyTo(substances), 1);
      final lsd = substances.firstWhere((s) => s.key == 'lsd').route('sublingual')!;
      expect(lsd.doseThreshold, 12);
      expect(lsd.doseLight!.min, 20);
      expect(lsd.doseStrong!.max, 300);
      expect(lsd.durations, same(lsdBefore.durations));
      expect(lsd.id, lsdBefore.id);
      final mdma = substances.firstWhere((s) => s.key == 'mdma').route('oral')!;
      expect(audit.behind(mdma), isNull);
      expect(classifyDose(lsd, 15), DoseClass.threshold);
    });
  });

  test('the glossary uses the new band names and still finds the old ones', () {
    final terms = glossary.map((e) => e.term).toList();
    expect(terms, contains('Low, common, high, heavy'));
    expect(terms, isNot(contains('Light, common, strong, heavy')));
    for (final query in ['strong dose', 'light dose', 'high dose', 'dose ladder']) {
      expect(glossary.where((e) => e.matches(query)).map((e) => e.term), contains('Low, common, high, heavy'), reason: query);
    }
  });

  test('ladder helpers: ranges, plain equivalents and wording never call a dose safe', () {
    final lsd = _withAudit().byKey['lsd']!.route('sublingual')!;
    final steps = doseSteps(lsd);
    expect(steps.map((s) => s.cls), [DoseClass.threshold, DoseClass.light, DoseClass.common, DoseClass.strong, DoseClass.heavy]);
    expect(steps.map(doseStepRange), ['10-20', '20-75', '75-150', '150-300', '300+']);
    expect(plainEquivalent(1500, 'mg'), '1.5 g');
    expect(plainEquivalent(0.25, 'g'), '250 mg');
    expect(plainEquivalent(1500, 'µg'), '1.5 mg');
    expect(plainEquivalent(100, 'µg'), isNull);
    for (final c in DoseClass.values) {
      expect(doseStepMeaning(c).toLowerCase(), isNot(contains('safe')));
      expect(doseStepMeaning(c).toLowerCase(), isNot(contains('recommend')));
    }
  });

  group('the dose ladder on a compound page', () {
    Future<TestApp> show(WidgetTester tester, ReferenceRepository reference, String key) async {
      final built = await buildTestApp(tester);
      final me = await dbRun(tester, built.db.ensureDefaultPerson);
      usePhoneScreen(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(built.db),
          referenceProvider.overrideWithValue(reference),
          interactionPairsProvider.overrideWithValue(reference.interactionPairs),
        ],
        child: MaterialApp(home: CompoundDetailPage(substanceKey: key, personId: me.id)),
      ));
      await settle(tester);
      return built;
    }

    testWidgets('LSD sublingual shows five labelled steps in order, the unit, and the sources line', (tester) async {
      final app = await show(tester, _withAudit(), 'lsd');
      final ladder = find.byKey(const ValueKey('dose-ladder-sublingual'));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dose-sources-sublingual')), 200, scrollable: find.byType(Scrollable).first);
      expect(ladder, findsOneWidget);
      expect(find.textContaining('Doses in µg (micrograms'), findsOneWidget);

      final names = ['threshold', 'light', 'common', 'strong', 'heavy'];
      final labels = ['Threshold', 'Low', 'Common', 'High', 'Heavy'];
      final bars = [for (final n in names) find.byKey(ValueKey('ladder-bar-sublingual-$n'))];
      final steps = [for (final n in names) find.byKey(ValueKey('ladder-step-sublingual-$n'))];
      for (var i = 0; i < names.length; i++) {
        expect(bars[i], findsOneWidget);
        expect(find.descendant(of: bars[i], matching: find.text(labels[i])), findsOneWidget);
        expect(steps[i], findsOneWidget);
        if (i > 0) {
          expect(tester.getTopLeft(bars[i]).dx, greaterThan(tester.getTopLeft(bars[i - 1]).dx), reason: 'bar order');
          expect(tester.getTopLeft(steps[i]).dy, greaterThan(tester.getTopLeft(steps[i - 1]).dy), reason: 'list order');
        }
      }
      expect(find.descendant(of: bars[2], matching: find.text('75-150')), findsOneWidget);
      expect(find.descendant(of: bars[4], matching: find.text('300+')), findsOneWidget);
      // The bar fits a phone: every step sits inside the ladder's width.
      final ladderBox = tester.getRect(ladder);
      expect(tester.getRect(bars.last).right, lessThanOrEqualTo(ladderBox.right + 0.5));

      final sources = tester.widget<Text>(find.byKey(const ValueKey('dose-sources-sublingual'))).data!;
      expect(sources, startsWith('Checked against '));
      for (final n in ['PsychonautWiki', 'Erowid', 'TripSit', 'Holze et al. 2021']) {
        expect(sources, contains(n));
      }
      expect(find.byKey(const ValueKey('dose-spread-sublingual')), findsOneWidget); // they disagree, so the spread shows
      expect(find.textContaining('(PsychonautWiki)'), findsWidgets);
      await disposeApp(tester, app);
    });

    testWidgets('the ladder fits a narrow phone screen without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final reference = _withAudit();
      for (final key in ['lsd', 'mdma', 'ketamine', 'alcohol']) {
        final s = reference.byKey[key]!;
        for (final roa in s.roas) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DoseLadder(roa: roa, substance: s, audit: reference.doseAudit.behind(roa)),
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: '$key ${roa.route}');
        }
      }
    });

    testWidgets('a compound nobody has cross-checked says so', (tester) async {
      final reference = _withAudit(extras: true);
      final unchecked = reference.substances.firstWhere((s) =>
          !s.audited && !s.crossChecked && reference.doseAudit.routes[s.key] == null && s.roas.any((r) => r.doseCommon?.min != null));
      final app = await show(tester, reference, unchecked.key);
      final line = find.text('One source (PsychonautWiki) — not yet cross-checked');
      await tester.scrollUntilVisible(line.first, 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('One source (PsychonautWiki) — not yet cross-checked'), findsWidgets);
      await disposeApp(tester, app);
    });
  });
}
