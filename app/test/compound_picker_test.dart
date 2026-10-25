import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/main.dart';

void main() {
  late ReferenceRepository reference;

  setUpAll(() {
    reference = ReferenceRepository(parseSubstances(File('assets/data/substances.json').readAsStringSync()));
  });

  testWidgets('lists every bundled compound and filters by search', (tester) async {
    // A tall surface so the lazy list builds all rows.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CompoundPickerPage(reference: reference)));
    expect(find.byType(ListTile), findsNWidgets(9));

    await tester.enterText(find.byType(TextField), 'weed');
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Cannabis'), findsOneWidget);
  });

  testWidgets('orders by history: the most used compound is listed first', (tester) async {
    final usage = {'ketamine': UsageStat(count: 5, lastUsed: DateTime(2026, 10, 1))};
    await tester.pumpWidget(MaterialApp(home: CompoundPickerPage(reference: reference, usage: usage)));
    final first = tester.widget<ListTile>(find.byType(ListTile).first);
    expect((first.title as Text).data, 'Ketamine');
  });

  test('bundled asset copy matches the source data file', () {
    expect(File('assets/data/substances.json').readAsStringSync(), File('../data/substances.json').readAsStringSync());
  });
}
