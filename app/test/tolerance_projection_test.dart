import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/tolerance_projection.dart';
import 'package:substance_journal_app/providers.dart';
import 'package:substance_journal_app/ui/compounds/compounds_page.dart';

import 'helpers.dart';

void main() {
  final all = [
    ...parseSubstances(File('assets/data/substances.json').readAsStringSync()),
  ];
  final taken = {for (final s in all) s.key};
  all.addAll(parseSubstances(File('assets/data/substances_extra.json').readAsStringSync()).where((s) => !taken.contains(s.key)));
  final byKey = {for (final s in all) s.key: s};

  group('the compound-page projection uses the shared tolerance model', () {
    test('LSD follows its published profile: largest about a day after, gone in about five days', () {
      final p = ToleranceProjection.of(byKey['lsd']!, byKey)!;
      expect(p.profiled, isTrue);
      final (peakAt, _) = p.peak;
      expect(peakAt.difference(toleranceOrigin).inHours, inInclusiveRange(20, 28));
      expect(p.peakLoss.percent, 52); // Isbell 1956 via the profile (docs/data-audit/lsd-tolerance-mushroom-potency.md)
      final gone = p.baselineAt()!.difference(toleranceOrigin).inHours / 24;
      expect(gone, inInclusiveRange(4.0, 5.5));
      final repeat = {for (final o in p.schedules()) o.everyDays: o};
      expect((repeat[3]!.beforeDose * 100).round(), 26); // matches the audit's "repeat 3 days later" row
      expect((repeat[7]!.beforeDose * 100).round(), 0);
      expect((repeat[14]!.beforeDose * 100).round(), 0);
      expect(repeat[1]!.beforeDose, greaterThan(repeat[3]!.beforeDose));
      expect(repeat[1]!.beforeDose, lessThanOrEqualTo(byKey['lsd']!.toleranceProfile!.maxLoss.high + 1e-9));
    });

    test('the projection matches what the tolerance card computes for the same doses', () {
      final events = [UseEvent('lsd', toleranceOrigin), UseEvent('lsd', toleranceOrigin.add(const Duration(days: 3)))];
      final at = toleranceOrigin.add(const Duration(days: 6));
      final card = effectLossAt(events, byKey, 'psychedelics', at, upTo: at.subtract(const Duration(microseconds: 1)));
      final p = ToleranceProjection.of(byKey['lsd']!, byKey)!;
      final mine = p.schedules(settleDays: 6).firstWhere((o) => o.everyDays == 3);
      expect(mine.beforeDose, closeTo(card.expected, 1e-9));
    });

    test('a compound without a profile gets the generic half-life shape', () {
      final mdma = byKey['mdma']!;
      final p = ToleranceProjection.of(mdma, byKey)!;
      expect(p.profiled, isFalse);
      final (_, peak) = p.peak;
      expect(peak, closeTo(1.0, 1e-9)); // one common dose on no prior tolerance
      final half = p.halfAt!.difference(toleranceOrigin).inMinutes / 1440;
      expect(half, closeTo(halfLifeDays(mdma), 1 / 24 + 1e-9));
      final baseline = p.baselineAt()!;
      expect(genericToleranceLevel([UseEvent('mdma', toleranceOrigin)], byKey, toleranceTrackKey(mdma), baseline), lessThan(baselineLevel));
      final daily = p.schedules().firstWhere((o) => o.everyDays == 1);
      final fortnightly = p.schedules().firstWhere((o) => o.everyDays == 14);
      expect(daily.beforeDose, greaterThan(fortnightly.beforeDose));
      expect(daily.afterDose!, lessThanOrEqualTo(toleranceCeiling));
    });

    test('compounds without tolerance get no graph', () {
      final none = all.firstWhere((s) => !s.hasTolerance);
      expect(ToleranceProjection.of(none, byKey), isNull);
    });
  });

  testWidgets('the compound page draws the tolerance graph with schedule lines, on a phone', (tester) async {
    final built = await buildTestApp(tester);
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
      ],
      child: MaterialApp(home: CompoundDetailPage(substanceKey: 'lsd', personId: me.id)),
    ));
    await settle(tester);
    final graph = find.byKey(const ValueKey('tolerance-graph-lsd'));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('tolerance-repeat-14')), 300, scrollable: find.byType(Scrollable).first);
    expect(graph, findsOneWidget);
    expect(find.byKey(const ValueKey('tolerance-graph-chart-lsd')), findsOneWidget);
    expect(find.byKey(const ValueKey('tolerance-graph-kind-lsd')), findsOneWidget);
    for (final n in toleranceRepeatDays) {
      expect(find.byKey(ValueKey('tolerance-repeat-$n')), findsOneWidget);
    }
    expect(find.textContaining('Cross-tolerance group: Psychedelics'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('tolerance-schedule-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tolerance-schedule-3')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tolerance-schedule-3'))).selected, isTrue);
    expect(tester.takeException(), isNull);
    await disposeApp(tester, built);
  });

  testWidgets('a generic compound says its curve is a rough shape with the source', (tester) async {
    final built = await buildTestApp(tester);
    final me = await dbRun(tester, built.db.ensureDefaultPerson);
    usePhoneScreen(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(built.db),
        referenceProvider.overrideWithValue(built.reference),
        interactionPairsProvider.overrideWithValue(built.reference.interactionPairs),
      ],
      child: MaterialApp(home: CompoundDetailPage(substanceKey: 'mdma', personId: me.id)),
    ));
    await settle(tester);
    final source = find.byKey(const ValueKey('tolerance-graph-source-mdma'));
    await tester.scrollUntilVisible(source, 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('A rough shape from a published half-life'), findsOneWidget);
    expect(tester.widget<Text>(source).data, contains('PsychonautWiki'));
    await disposeApp(tester, built);
  });
}
