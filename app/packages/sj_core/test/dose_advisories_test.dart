import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final all = parseSubstances(File('../../assets/data/substances.json').readAsStringSync());
  final byKey = {for (final s in all) s.key: s};
  final at = DateTime(2026, 7, 1, 20);

  List<DoseAdvisory> run(String key, String route, double? dose, {List<PastDose> past = const []}) {
    final s = byKey[key]!;
    return doseAdvisories(substance: s, roa: s.route(route)!, dose: dose, at: at, past: past, byKey: byKey);
  }

  List<String> titles(List<DoseAdvisory> a) => [for (final x in a) x.title];

  test('a common dose gets no advisories', () {
    expect(run('lsd', 'sublingual', 100), isEmpty);
  });

  test('strong is a note, heavy a caution, with the published number', () {
    final lsd = byKey['lsd']!.route('sublingual')!;
    final strong = run('lsd', 'sublingual', lsd.doseStrong!.min!);
    expect(titles(strong), ['Strong dose']);
    expect(strong.single.level, AdvisoryLevel.note);
    final heavy = run('lsd', 'sublingual', lsd.doseHeavy!);
    expect(titles(heavy), ['Heavy dose']);
    expect(heavy.single.level, AdvisoryLevel.caution);
    expect(heavy.single.detail, contains('${lsd.doseHeavy!.round()} '));
  });

  test('a repeat dose while the first is active is flagged, and says when onset is not over', () {
    final soon = run('mdma', 'oral', 75, past: [PastDose(substanceKey: 'mdma', route: 'oral', time: at.subtract(const Duration(minutes: 20)), dose: 75, unit: 'mg')]);
    expect(titles(soon), contains('Still active from 20 min ago'));
    expect(soon.firstWhere((a) => a.title.startsWith('Still')).detail, contains('may not have started working yet'));
    expect(soon.firstWhere((a) => a.title.startsWith('Still')).level, AdvisoryLevel.caution);

    final later = run('mdma', 'oral', 75, past: [PastDose(substanceKey: 'mdma', route: 'oral', time: at.subtract(const Duration(minutes: 100)), dose: 75, unit: 'mg')]);
    final stillActive = later.firstWhere((a) => a.title.startsWith('Still'));
    expect(stillActive.detail, isNot(contains('may not have started')));

    final gone = run('mdma', 'oral', 75, past: [PastDose(substanceKey: 'mdma', route: 'oral', time: at.subtract(const Duration(hours: 20)), dose: 75, unit: 'mg')]);
    expect(titles(gone).where((t) => t.startsWith('Still')), isEmpty);
  });

  test('another substance, or a dose in the future, does not count as a repeat', () {
    final other = run('mdma', 'oral', 75, past: [PastDose(substanceKey: 'lsd', route: 'sublingual', time: at.subtract(const Duration(minutes: 20)))]);
    expect(titles(other).where((t) => t.startsWith('Still')), isEmpty);
    final future = run('mdma', 'oral', 75, past: [PastDose(substanceKey: 'mdma', route: 'oral', time: at.add(const Duration(minutes: 20)), dose: 75, unit: 'mg')]);
    expect(titles(future).where((t) => t.startsWith('Still')), isEmpty);
  });

  test('a 24-hour total at the heavy dose is flagged even when each dose is lower', () {
    final heavy = byKey['mdma']!.route('oral')!.doseHeavy!;
    final each = heavy * 0.6;
    final result = run('mdma', 'oral', each, past: [PastDose(substanceKey: 'mdma', route: 'oral', time: at.subtract(const Duration(hours: 10)), dose: each, unit: 'mg')]);
    expect(titles(result), contains('High total today'));
  });

  test('recent use of a tolerance-forming substance adds a tolerance note, old use does not', () {
    final recent = run('lsd', 'sublingual', 100, past: [PastDose(substanceKey: 'lsd', route: 'sublingual', time: at.subtract(const Duration(days: 1)), dose: 100, unit: 'µg')]);
    expect(titles(recent), contains('Tolerance is up'));
    final old = run('lsd', 'sublingual', 100, past: [PastDose(substanceKey: 'lsd', route: 'sublingual', time: at.subtract(const Duration(days: 40)), dose: 100, unit: 'µg')]);
    expect(titles(old), isEmpty);
  });

  test('alcohol and unknown doses are skipped or quiet', () {
    expect(run('alcohol', 'oral', 500), isEmpty);
    expect(run('lsd', 'sublingual', null), isEmpty);
  });
}
