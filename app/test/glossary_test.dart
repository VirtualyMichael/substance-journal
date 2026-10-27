import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/glossary.dart';
import 'package:substance_journal_app/ui/safety/glossary_page.dart';

void main() {
  test('every entry is in a known group, has a real definition, and no term is repeated', () {
    final terms = <String>{};
    for (final e in glossary) {
      expect(glossaryGroups, contains(e.group), reason: e.term);
      expect(e.definition.length, greaterThan(30), reason: e.term);
      expect(terms.add(e.term.toLowerCase()), isTrue, reason: 'duplicate ${e.term}');
    }
    for (final g in glossaryGroups) {
      expect(glossary.any((e) => e.group == g), isTrue, reason: 'empty group $g');
    }
  });

  test('the terms the compound pages use are all defined', () {
    final text = glossary.map((e) => '${e.term} ${e.also.join(' ')}').join(' ').toLowerCase();
    for (final word in ['onset', 'come-up', 'peak', 'come-down', 'afterglow', 'duration', 'tolerance', 'cross-tolerance', 'redosing', 'threshold', 'bioavailability', 'half-life']) {
      expect(text, contains(word), reason: word);
    }
  });

  test('search finds a term by its name, by another name for it, and inside a definition', () {
    expect(glossary.where((e) => e.matches('comeup')).map((e) => e.term), contains('Come-up'));
    expect(glossary.where((e) => e.matches('fentanyl strip')).map((e) => e.term), contains('Test strip'));
    expect(glossary.where((e) => e.matches('SNORTED')).map((e) => e.term), contains('Route of administration'));
    expect(glossary.where((e) => e.matches('  ')).length, glossary.length);
    expect(glossary.where((e) => e.matches('zzzz-no-such')), isEmpty);
  });

  test('nothing in the glossary tells anyone it is safe to drive or use something', () {
    final all = glossary.map((e) => e.definition.toLowerCase()).join(' ');
    expect(all, isNot(contains('safe to drive')));
    expect(all, isNot(contains('is safe')));
  });

  testWidgets('searching narrows the list, opens the answers, and says when nothing matches', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlossaryPage()));
    expect(find.text('Come-up'), findsOneWidget);
    expect(find.text('Timing'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('glossary-search')), 'afterglow');
    await tester.pumpAndSettle();
    expect(find.text('Afterglow'), findsOneWidget);
    expect(find.text('Come-up'), findsNothing);
    expect(find.textContaining('Milder effects that linger'), findsOneWidget); // few matches: already open

    await tester.enterText(find.byKey(const ValueKey('glossary-search')), 'qqqq');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('glossary-empty')), findsOneWidget);
  });

  testWidgets('tapping a term opens its definition', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlossaryPage()));
    await tester.tap(find.text('Onset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('before you first notice anything'), findsOneWidget);
  });
}
