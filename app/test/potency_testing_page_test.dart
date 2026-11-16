import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/mushroom_reference.dart';
import 'package:substance_journal_app/ui/safety/potency_testing_page.dart';

void main() {
  final info = PotencyTestingInfo.parse(File('assets/data/potency_testing.json').readAsStringSync());

  test('every listed service names what it tests, who can use it and when it was checked', () {
    expect(info.verified, isNotEmpty);
    expect(info.legal, contains('not legal advice'));
    expect(info.legal, contains('not an endorsement'));
    expect(info.services, isNotEmpty);
    for (final s in info.services) {
      expect(Uri.parse(s.url).scheme, 'https', reason: s.name);
      expect(s.tests, isNotEmpty, reason: s.name);
      expect(s.eligibility, isNotEmpty, reason: s.name);
      expect(s.verified, isNotEmpty, reason: s.name);
    }
    // Reagent kits are said not to tell potency.
    expect(info.whatATestTells.any((t) => t.contains('cannot tell potency')), isTrue);
  });

  testWidgets('the page shows the legal note, the guidance and the services', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [potencyTestingProvider.overrideWith((ref) => info)],
      child: const MaterialApp(home: PotencyTestingPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('potency-testing-legal')), findsOneWidget);
    expect(find.text('Reading a lab certificate'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(ValueKey('testing-service-${info.services.first.name}')), 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('potency-testing-list')), matching: find.byType(Scrollable)));
    expect(find.text(info.services.first.name), findsOneWidget);
  });
}
