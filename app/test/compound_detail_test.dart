import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';
import 'package:substance_journal_app/ui/compounds/route_timeline_chart.dart';

import 'helpers.dart';

void main() {
  Future<(TestApp, List<Uri>)> detail(WidgetTester tester, String key) async {
    final built = await buildTestApp(tester);
    final opened = <Uri>[];
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
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
      child: MaterialApp(home: CompoundDetailPage(substanceKey: key, personId: me.id)),
    ));
    await settle(tester);
    return (built, opened);
  }

  testWidgets('a compound page draws a timeline per route, with dependence and tolerance wording', (tester) async {
    final (app, _) = await detail(tester, 'lsd');
    final chart = find.byType(RouteTimelineChart);
    await tester.scrollUntilVisible(chart, 300, scrollable: find.byType(Scrollable).first);
    expect(chart, findsOneWidget);
    expect(find.text('How it typically unfolds'), findsWidgets);
    expect(find.textContaining('not a measurement'), findsWidgets);
    expect(find.byKey(const ValueKey('audit-note')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('source links are tappable and open the address; non-links stay plain text', (tester) async {
    final (app, opened) = await detail(tester, 'alcohol');
    final link = find.byKey(const ValueKey('link-https://pubmed.ncbi.nlm.nih.gov/17064864/'));
    await tester.scrollUntilVisible(link, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(find.descendant(of: link, matching: find.text('pubmed.ncbi.nlm.nih.gov/17064864')), findsOneWidget);
    await tester.tap(link);
    await settle(tester);
    expect(opened.single.toString(), 'https://pubmed.ncbi.nlm.nih.gov/17064864/');
    await disposeApp(tester, app);
  });

  testWidgets('psilocybin mushrooms are weighed in grams, dried or fresh', (tester) async {
    final (app, _) = await detail(tester, 'psilocybin_mushrooms');
    expect(find.textContaining('Dried'), findsWidgets);
    expect(find.textContaining('mg of pure psilocybin'), findsNothing);
    await disposeApp(tester, app);
  });
}
