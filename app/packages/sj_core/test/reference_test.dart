import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

// Tests run with the package root as the working directory.
final _dataFile = File('../../../data/substances.json');

void main() {
  late List<Substance> substances;
  late Map<String, Substance> byKey;

  setUpAll(() {
    substances = parseSubstances(_dataFile.readAsStringSync());
    byKey = {for (final s in substances) s.key: s};
  });

  test('parses all nine substances with routes', () {
    expect(byKey.keys.toSet(), {
      'alcohol', 'nicotine', 'cannabis', 'psilocybin_mushrooms', 'lsd', 'dmt', 'mdma', '2c-b', 'ketamine',
    });
    for (final s in substances) {
      expect(s.roas, isNotEmpty, reason: s.key);
      expect(s.summary.length, greaterThan(60), reason: s.key);
      expect(s.sources, isNotEmpty, reason: s.key);
    }
  });

  test('audited values survive the round trip into Dart', () {
    final ketamine = byKey['ketamine']!;
    expect(ketamine.toleranceHalfDays, 14.0);
    expect(ketamine.toleranceZeroDays, 28.0);

    final oral = byKey['cannabis']!.route('oral')!;
    expect(oral.duration('onset')!.minMinutes, 20.0);
    expect(oral.duration('onset')!.maxMinutes, 120.0);
    expect(oral.duration('peak')!.maxMinutes, 180.0);
    expect(byKey['cannabis']!.route('sublingual'), isNotNull);
    expect(byKey['cannabis']!.route('sublingual')!.doseCommon, isNull);
  });

  test('durations are converted to minutes', () {
    final dmt = byKey['dmt']!.route('smoked')!;
    expect(dmt.duration('onset')!.minMinutes, closeTo(0.25, 1e-9));
    expect(dmt.duration('onset')!.maxMinutes, closeTo(1.0, 1e-9));
    expect(dmt.duration('total')!.maxMinutes, 20.0);
  });

  test('route ids use the stable substance:route key', () {
    expect(byKey['cannabis']!.route('smoked')!.id, 'cannabis:smoked');
    expect(byKey['alcohol']!.route('oral')!.unit, 'g');
    final common = byKey['alcohol']!.route('oral')!.doseCommon!;
    expect([common.min, common.max], [20.0, 30.0]);
  });

  test('interaction tiers are loaded', () {
    expect(byKey['dmt']!.unsafe, contains('MAOIs'));
    expect(byKey['psilocybin_mushrooms']!.dangerous, contains('Lithium'));
    expect(byKey['mdma']!.unsafe, containsAll(['Protease Inhibitors', 'GHB', 'GBL']));
  });
}
