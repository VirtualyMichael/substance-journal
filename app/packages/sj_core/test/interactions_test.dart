import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final byKey = {for (final s in parseSubstances(File('../../../data/substances.json').readAsStringSync())) s.key: s};
  final pairs = parseInteractions(File('../../../data/interactions.json').readAsStringSync());

  List<InteractionWarning> check(String incoming, List<String> active) =>
      checkInteractions(incoming: byKey[incoming]!, active: [for (final k in active) byKey[k]!], pairs: pairs);

  test('parses all 28 TripSit pairs', () {
    expect(pairs, hasLength(28));
  });

  test('alcohol with ketamine is dangerous, whichever is logged first', () {
    for (final (incoming, active) in [('ketamine', 'alcohol'), ('alcohol', 'ketamine')]) {
      final w = check(incoming, [active]);
      expect(w, hasLength(1), reason: '$incoming after $active');
      expect(w.single.severity, InteractionSeverity.dangerous);
      expect(w.single.reasons.any((r) => r.startsWith('TripSit')), isTrue);
    }
  });

  test('alcohol with MDMA is a caution; cannabis with LSD is a caution', () {
    expect(check('mdma', ['alcohol']).single.severity, InteractionSeverity.caution);
    expect(check('lsd', ['cannabis']).single.severity, InteractionSeverity.caution);
  });

  test('low-risk synergy pairs produce no warning', () {
    expect(check('lsd', ['psilocybin_mushrooms']), isEmpty);
    expect(check('cannabis', ['ketamine']).where((w) => w.severity != InteractionSeverity.lowRisk), isEmpty);
  });

  test('PsychonautWiki lists add warnings TripSit lacks, including class names', () {
    // Lithium-style: DMT lists MAOIs as unsafe, but we have no MAOI substance; class aliases matter instead.
    // Ketamine lists Alcohol as dangerous; alcohol lists Depressants/Dissociatives as dangerous.
    final w = check('alcohol', ['ketamine']).single;
    expect(w.reasons.any((r) => r.contains('PsychonautWiki')), isTrue);
    // MDMA's unsafe list contains "Serotonin releasers": MDMA is itself one, so nothing else matches here.
    expect(interactionNames(byKey['mdma']!), containsAll(['mdma', 'stimulants', 'serotonin releasers']));
    // Nicotine counts as a stimulant for lists that name the class.
    expect(interactionNames(byKey['nicotine']!), contains('stimulants'));
    final lsdWithNicotine = check('lsd', ['nicotine']);
    expect(lsdWithNicotine.single.severity, InteractionSeverity.caution); // LSD lists Stimulants as uncertain
  });

  test('the same substance never warns against itself and duplicates collapse', () {
    expect(check('cannabis', ['cannabis']), isEmpty);
    expect(check('alcohol', ['ketamine', 'ketamine']), hasLength(1));
  });

  test('warnings are ordered worst first and carry both substances', () {
    final w = check('alcohol', ['mdma', 'ketamine', 'lsd']);
    expect(w.first.severity, InteractionSeverity.dangerous);
    expect(w.first.other.key, 'ketamine');
    expect(w.map((x) => x.severity.index).toList(), [...w.map((x) => x.severity.index)]..sort((a, b) => b.compareTo(a)));
    expect(w.every((x) => x.incoming.key == 'alcohol'), isTrue);
  });

  test('no active substances means no warnings, and other people are simply not passed in', () {
    expect(check('mdma', []), isEmpty);
  });
}
