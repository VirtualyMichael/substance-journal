import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';

void main() {
  final audited = parseSubstances(File('assets/data/substances.json').readAsStringSync());
  final extra = parseSubstances(File('assets/data/substances_extra.json').readAsStringSync());

  test('the PsychonautWiki catalog is large, unique and marked as not audited', () {
    expect(extra.length, greaterThan(200));
    expect(audited.every((s) => s.audited), isTrue);
    expect(extra.every((s) => !s.audited && s.license != null), isTrue);
    final keys = [...audited, ...extra].map((s) => s.key);
    expect(keys.toSet().length, keys.length);
  });

  test('every catalog route has sane bands and durations', () {
    for (final s in extra) {
      expect(s.roas, isNotEmpty, reason: s.key);
      for (final r in s.roas) {
        for (final band in [r.doseLight, r.doseCommon, r.doseStrong]) {
          if (band?.min != null && band?.max != null) {
            expect(band!.min! <= band.max!, isTrue, reason: '${s.key} ${r.route}');
          }
        }
        for (final d in r.durations) {
          if (d.minMinutes != null && d.maxMinutes != null) {
            expect(d.minMinutes! <= d.maxMinutes!, isTrue, reason: '${s.key} ${r.route} ${d.phase}');
          }
        }
      }
    }
  });

  test('catalog substances answer to their class names in interaction lists', () {
    final diazepam = extra.firstWhere((s) => s.key == 'diazepam');
    final names = interactionNames(diazepam);
    expect(names, containsAll(['diazepam', 'benzodiazepines', 'benzodiazepine']));
  });

  test('the category filter narrows the list', () {
    final all = [...audited, ...extra];
    final categories = compoundCategories(all);
    expect(categories, isNotEmpty);
    final filtered = orderCompounds(all: all, category: categories.first);
    expect(filtered, isNotEmpty);
    expect(filtered.length, lessThan(all.length));
    expect(filtered.every((s) => substanceCategories(s).contains(categories.first)), isTrue);
  });
}
