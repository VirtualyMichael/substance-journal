import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  MushroomEstimate est(String form, String amount, [MushroomCalc c = const MushroomCalc()]) =>
      estimateMushroom(form, amount, c).estimate!;

  test('psilocin converts to psilocybin by molar mass (PubChem 284.25 / 204.27)', () {
    expect(psilocinToPsilocybin, closeTo(1.3916, 1e-4));
    final c = const MushroomCalc(psilocybinPct: '1.0', psilocinPct: '0.5', potencySource: 'labTest');
    final e = est('dried', '1', c);
    expect(e.potencyPct, closeTo(1.0 + 0.5 * 1.3916, 1e-4));
    expect(e.expectedMg, closeTo(1000 * (1.0 + 0.5 * 1.3916) / 100, 1e-3));
  });

  test('unknown potency: 10 mg/g expected, the published range around it', () {
    final e = est('dried', '2');
    expect(e.driedGrams, 2);
    expect(e.expectedMg, closeTo(20, 1e-9));
    // Low: 9.5% water allowed and the lowest published potency; high: the highest.
    expect(e.lowMg, closeTo(2 * (1 - 0.095) * 1000 * unknownCubensisLowPct / 100, 1e-9));
    expect(e.highMg, closeTo(2 * 1000 * unknownCubensisHighPct / 100, 1e-9));
    expect(e.toDetails()['psilocybinEqMg'], 20.0);
  });

  test('fresh mushrooms are about 90% water, within the USDA range', () {
    final e = est('fresh', '20');
    expect(e.driedGrams, closeTo(2, 1e-9));
    expect(e.expectedMg, closeTo(20, 1e-9));
    expect(e.lowMg, closeTo(20 * (1 - 0.9245) * 1000 * unknownCubensisLowPct / 100, 1e-9));
    expect(e.highMg, closeTo(20 * (1 - 0.883) * 1000 * unknownCubensisHighPct / 100, 1e-9));
  });

  test('capsules, edibles by mushroom grams or by psilocybin mg, and pure mg', () {
    expect(est('capsule', '', const MushroomCalc(count: '4', perUnit: '250')).driedGrams, closeTo(1, 1e-9));
    expect(est('edible', '', const MushroomCalc(count: '2', perUnit: '0.5', edibleUnit: 'g')).driedGrams, closeTo(1, 1e-9));
    final labelled = est('edible', '', const MushroomCalc(count: '2', perUnit: '5', edibleUnit: 'mg'));
    expect(labelled.expectedMg, 10);
    expect(labelled.driedGrams, closeTo(1, 1e-9));
    final pure = est('mg', '25');
    expect((pure.expectedMg, pure.lowMg, pure.highMg, pure.driedGrams), (25.0, 25.0, 25.0, 2.5));
  });

  test('a lab result gets the fruit-body spread; a published strain its own range', () {
    final lab = est('dried', '1', const MushroomCalc(psilocybinPct: '1', potencySource: 'labTest'));
    expect(lab.lowMg, closeTo(10 * (1 - fruitBodyCv) * (1 - 0.095), 1e-6));
    expect(lab.highMg, closeTo(10 * (1 + fruitBodyCv), 1e-6));
    final published = estimateMushroom('dried', '1', const MushroomCalc(psilocybinPct: '1', potencySource: 'published', dryness: 'dry'),
        publishedLow: 0.5, publishedHigh: 1.5).estimate!;
    expect(published.lowMg, closeTo(5, 1e-9));
    expect(published.highMg, closeTo(15, 1e-9));
  });

  test('caps can be stronger and stems weaker, as a range only', () {
    const dry = MushroomCalc(dryness: 'dry', psilocybinPct: '1', potencySource: 'labTest');
    final caps = est('dried', '1', dry.copyWith(part: 'caps'));
    final stems = est('dried', '1', dry.copyWith(part: 'stems'));
    final whole = est('dried', '1', dry);
    expect(caps.expectedMg, whole.expectedMg);
    expect(caps.highMg, closeTo(whole.highMg * 1.03 / 0.52, 1e-6));
    expect(stems.lowMg, closeTo(whole.lowMg * 0.52 / 1.03, 1e-6));
  });

  test('moisture and storage loss', () {
    final damp = est('dried', '1', const MushroomCalc(dryness: 'damp', water: '20'));
    expect(damp.expectedMg, closeTo(8, 1e-9));
    expect(damp.driedGrams, 1); // the dose stays as weighed, as the bands are
    final old = est('dried', '1', const MushroomCalc(dryness: 'dry', degradationPct: 20));
    expect(old.expectedMg, closeTo(8, 1e-9));
    expect(old.highMg, closeTo(28, 1e-9)); // the high end assumes no loss
    expect(estimateMushroom('dried', '1', const MushroomCalc(dryness: 'damp', water: '95')).error, isNotNull);
    expect(estimateMushroom('dried', '1', const MushroomCalc(dryness: 'damp')).error, isNotNull);
  });

  test('blank, zero, negative and very large input', () {
    expect(estimateMushroom('dried', '', const MushroomCalc()).estimate, isNull);
    expect(estimateMushroom('dried', '', const MushroomCalc()).error, isNull);
    expect(estimateMushroom('dried', 'abc', const MushroomCalc()).estimate, isNull);
    expect(estimateMushroom('dried', '0', const MushroomCalc()).error, isNotNull);
    expect(estimateMushroom('fresh', '-3', const MushroomCalc()).error, isNotNull);
    expect(estimateMushroom('capsule', '', const MushroomCalc(count: '0', perUnit: '250')).error, isNotNull);
    expect(estimateMushroom('dried', '1', const MushroomCalc(psilocybinPct: '-1')).error, isNotNull);
    expect(estimateMushroom('dried', '1', const MushroomCalc(psilocybinPct: '0', psilocinPct: '0')).error, isNotNull);
    expect(est('dried', '1,5').driedGrams, 1.5); // a decimal comma works
    expect(est('dried', '25').warnings, isNotEmpty);
    expect(est('dried', '2').warnings, isEmpty);
    expect(est('dried', '1', const MushroomCalc(psilocybinPct: '15')).warnings, isNotEmpty); // probably mg/g typed as %
    expect(est('mg', '500').warnings, isNotEmpty);
  });

  test('the calculator input survives a round trip, and odd JSON falls back to defaults', () {
    const c = MushroomCalc(count: '3', perUnit: '200', dryness: 'damp', water: '12', part: 'caps', psilocybinPct: '0.9', psilocinPct: '0.1',
        potencySource: 'labTest', potencyDetail: 'Lab X, 2026-05-01', strain: 'B+', degradationPct: 10, batchId: 'b1', batchName: 'Spring');
    expect(MushroomCalc.fromJson(c.toJson()).toJson(), c.toJson());
    expect(MushroomCalc.fromJson('nonsense').toJson(), const MushroomCalc().toJson());
    expect(MushroomCalc.fromJson({'degradationPct': 400}).degradationPct, 50);
  });

  group('personal calibration', () {
    test('no ratings, no suggestion; as expected changes nothing', () {
      expect(calibrate(1.0, const []), isNull);
      expect(calibrate(1.0, const [BatchFeel.asExpected, BatchFeel.asExpected])!.factor, 1.0);
    });

    test('damped: one rating moves only part way', () {
      final one = calibrate(1.0, const [BatchFeel.muchStronger])!;
      expect(one.factor, greaterThan(1));
      expect(one.factor, lessThan(batchFeelStep[BatchFeel.muchStronger]!));
      final many = calibrate(1.0, List.filled(10, BatchFeel.muchStronger))!;
      expect(many.factor, greaterThan(one.factor));
    });

    test('never more than the stated factor either way', () {
      for (final f in BatchFeel.values) {
        final c = calibrate(1.0, List.filled(50, f))!;
        expect(c.factor, inInclusiveRange(1 / maxCalibrationFactor, maxCalibrationFactor));
      }
    });
  });

  test('the bundled strain reference parses, and every number has a source', () {
    final ref = StrainReference.parse(File('../../assets/data/mushroom_strains.json').readAsStringSync());
    expect(ref.verified, isNotEmpty);
    expect(ref.strains, isNotEmpty);
    for (final s in ref.strains) {
      expect(s.analyses, isNotEmpty, reason: s.name);
      for (final a in s.analyses) {
        expect(a.source, isNotEmpty, reason: s.name);
        expect(a.equivalentPct, inInclusiveRange(0, unknownCubensisHighPct), reason: s.name);
      }
      expect(s.lowPct, lessThanOrEqualTo(s.equivalentPct));
      expect(s.highPct, greaterThanOrEqualTo(s.equivalentPct));
    }
    final creeper = ref.find('creeper')!;
    expect(creeper.equivalentPct, closeTo(1.3 + 0.024 * psilocinToPsilocybin, 1e-9));
    expect(ref.find('Golden Teacher')!.note, contains('published sample'));
    expect(ref.find('Nonexistent'), isNull);
  });
}
