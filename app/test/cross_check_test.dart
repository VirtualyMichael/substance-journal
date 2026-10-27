import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';

void main() {
  final extras = parseSubstances(File('assets/data/substances_extra.json').readAsStringSync());

  test('compounds whose doses agree with TripSit are marked cross-checked, and only those', () {
    final checked = extras.where((s) => s.crossChecked).toList();
    expect(checked.length, greaterThan(50));
    for (final s in checked) {
      expect(s.audited, isFalse, reason: '${s.name}: cross-checked is not the same as audited by hand');
      expect(s.sources.any((u) => u.startsWith('https://tripsit.me/factsheets/')), isTrue, reason: s.name);
      expect(s.safetyNotes.any((n) => n.startsWith('Cross-check: ')), isTrue, reason: s.name);
      expect(s.safetyNotes.any((n) => n.startsWith('Copied from PsychonautWiki and not independently checked')), isFalse, reason: s.name);
    }
  });

  test('where the sources disagree the compound stays unchecked, keeps its copied-only warning, and says what differs', () {
    final conflicted = extras.where((s) => !s.crossChecked && s.safetyNotes.any((n) => n.startsWith('Cross-check: '))).toList();
    expect(conflicted.length, greaterThan(50));
    for (final s in conflicted) {
      expect(s.safetyNotes.any((n) => n.startsWith('Copied from PsychonautWiki')), isTrue, reason: s.name);
      expect(s.sources.any((u) => u.contains('tripsit.me/factsheets/')), isTrue, reason: s.name);
    }
    final butanediol = extras.firstWhere((s) => s.name == '1,4-Butanediol');
    expect(butanediol.safetyNotes.join(' '), contains('Start with the lower figure'));
  });

  test('nothing in the catalog is both hand-audited and cross-checked, and numbers are untouched', () {
    expect(extras.where((s) => s.audited && s.crossChecked), isEmpty);
    expect(extras.every((s) => !s.audited), isTrue); // the extras were never promoted to audited
  });
}
