import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/research_links.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';
import 'package:substance_journal_app/ui/safety/research_page.dart';

import 'helpers.dart';

void main() {
  test('each compound gets its own profile, an Erowid search, a TripSit factsheet and the combination chart', () {
    final ref = loadReference();
    final lsd = researchLinksFor(ref.byKey['lsd']!);
    expect(lsd.map((l) => l.url), containsAll(['https://tripsit.me/factsheets/lsd', 'https://tripsit.me/combo', 'https://www.erowid.org/search.php?q=LSD']));
    expect(lsd.first.url, startsWith('https://psychonautwiki.org/wiki/'));
    final shrooms = researchLinksFor(ref.byKey['psilocybin_mushrooms']!);
    expect(shrooms.map((l) => l.url), contains('https://tripsit.me/factsheets/mushrooms')); // TripSit's own name for them
    // A catalog compound with no mapped factsheet points to the list instead of a guessed page.
    const extra = Substance(key: 'some_other', name: 'Some Other', category: '', summary: '', hasTolerance: false, audited: false);
    final links = researchLinksFor(extra).map((l) => l.url);
    expect(links, contains('https://tripsit.me/factsheets'));
    expect(links.every((u) => Uri.parse(u).scheme == 'https'), isTrue);
    // Names with spaces and symbols are safely encoded.
    expect(researchLinksFor(ref.byKey['psilocybin_mushrooms']!).any((l) => l.url.contains('Psilocybin+mushrooms')), isTrue);
  });

  test('every link in the reading list is a secure web address', () {
    for (final (_, links) in researchHub) {
      for (final l in links) {
        expect(Uri.parse(l.url).scheme, 'https', reason: l.title);
        expect(l.description, isNotEmpty);
      }
    }
    expect(researchHub.expand((g) => g.$2).map((l) => l.url), contains('https://psychonautwiki.org/wiki/Psychoactive_substance_index'));
  });

  testWidgets('the compound page and the research page show links that open in the browser', (tester) async {
    final built = await buildTestApp(tester);
    final opened = <Uri>[];
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    Future<void> show(Widget page) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(built.db),
          referenceProvider.overrideWithValue(built.reference),
          interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(home: page),
      ));
      await settle(tester);
    }

    await show(CompoundDetailPage(substanceKey: 'mdma', personId: me.id));
    final tripsit = find.byKey(const ValueKey('link-https://tripsit.me/factsheets/mdma'));
    await tester.scrollUntilVisible(tripsit, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(tripsit);
    await tester.pumpAndSettle();
    expect(find.text('Research before you take it'), findsOneWidget);
    await tester.tap(tripsit);
    await settle(tester);
    expect(opened.single.toString(), 'https://tripsit.me/factsheets/mdma');

    await show(const ResearchPage());
    expect(find.text('Check before you mix'), findsOneWidget);
    final index = find.byKey(const ValueKey('link-https://psychonautwiki.org/wiki/Psychoactive_substance_index'));
    await tester.ensureVisible(index);
    await tester.tap(index);
    await settle(tester);
    expect(opened.last.toString(), 'https://psychonautwiki.org/wiki/Psychoactive_substance_index');
    await disposeApp(tester, built);
  });
}
