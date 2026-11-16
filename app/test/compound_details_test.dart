import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/compound_details.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';

import 'helpers.dart';

final _detailsText = File('assets/data/compound_details.json').readAsStringSync();
final _effectsText = File('assets/data/effects.json').readAsStringSync();

void main() {
  test('the bundled details parse, belong to real compounds, cite sources and never call anything safe', () {
    final d = CompoundDetails.tryParse(_detailsText, effectsText: _effectsText);
    final keys = {
      ...parseSubstances(File('assets/data/substances.json').readAsStringSync()).map((s) => s.key),
      ...parseSubstances(File('assets/data/substances_extra.json').readAsStringSync()).map((s) => s.key),
    };
    expect(d.byKey.length, greaterThanOrEqualTo(20));
    for (final MapEntry(:key, :value) in d.byKey.entries) {
      expect(keys, contains(key));
      expect(value.sources, isNotEmpty, reason: key);
      expect(value.sources.every((s) => s.url.startsWith('https://')), isTrue, reason: key);
      final all = [value.whatItIs, value.howItWorks, value.timing, ...value.harmReduction].join(' ').toLowerCase();
      expect(all, isNot(matches(RegExp(r'\bsafe\b'))), reason: key);
      expect(all, isNot(contains('recommended dose')), reason: key);
    }
    for (final k in ['lsd', 'psilocybin_mushrooms', 'mdma', 'cannabis', 'alcohol', 'ketamine', 'cocaine', 'ghb', 'oxycodone', 'kratom']) {
      expect(d[k], isNotNull, reason: k);
    }
    // Effect names link to the PsychonautWiki effect index where they match it.
    expect(d.effect('color enhancement')?.url, startsWith('https://psychonautwiki.org/'));
  });

  test('missing or malformed details give nothing, and an unsourced entry is dropped', () {
    expect(CompoundDetails.tryParse(null).byKey, isEmpty);
    expect(CompoundDetails.tryParse('not json').byKey, isEmpty);
    expect(CompoundDetails.tryParse('{"compounds": []}').byKey, isEmpty);
    final d = CompoundDetails.tryParse('{"compounds": {"a": {"what_it_is": "x", "how_it_works": "y", "sources": []},'
        ' "b": {"what_it_is": "x", "how_it_works": "y", "sources": [{"name": "n", "url": "https://e.org"}]}}}');
    expect(d.byKey.keys, ['b']);
  });

  testWidgets('a compound page shows what it is, how it works, effects, timing, harm reduction and sources', (tester) async {
    final built = await buildTestApp(tester);
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    final reference = ReferenceRepository(
      built.reference.substances,
      interactionPairs: built.reference.interactionPairs,
      details: CompoundDetails.tryParse(_detailsText, effectsText: _effectsText),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(reference),
        interactionPairsProvider.overrideWithValue(reference.interactionPairs),
      ],
      child: MaterialApp(home: CompoundDetailPage(substanceKey: 'mdma', personId: me.id)),
    ));
    await settle(tester);
    for (final k in ['details-what', 'details-how', 'details-effects', 'details-timing', 'details-harm-0', 'details-sources']) {
      final f = find.byKey(ValueKey(k));
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      expect(f, findsOneWidget, reason: k);
    }
    expect(tester.widget<Text>(find.byKey(const ValueKey('details-how'))).data, contains('serotonin, dopamine and noradrenaline'));
    // An effect with a definition opens it.
    final chip = find.byKey(const ValueKey('effect-Teeth grinding'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeApp(tester, built);
  });

  testWidgets('a compound without details shows no detail sections', (tester) async {
    final built = await buildTestApp(tester);
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference), // no details loaded
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
      ],
      child: MaterialApp(home: CompoundDetailPage(substanceKey: 'lsd', personId: me.id)),
    ));
    await settle(tester);
    expect(find.byKey(const ValueKey('compound-details')), findsNothing);
    await disposeApp(tester, built);
  });
}
