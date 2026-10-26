import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  final byKey = {for (final s in parseSubstances(File('../../../data/substances.json').readAsStringSync())) s.key: s};
  final cannabis = byKey['cannabis']!;
  final smoked = cannabis.route('smoked')!;
  final oral = cannabis.route('oral')!;
  final sublingual = cannabis.route('sublingual')!;

  group('dose classification', () {
    test('uses [min, max) bands against the reference data', () {
      expect(classifyDose(smoked, 0.1), DoseClass.belowThreshold);
      expect(classifyDose(smoked, 0.4), DoseClass.light);
      expect(classifyDose(smoked, 1.9), DoseClass.light);
      expect(classifyDose(smoked, 2.0), DoseClass.common);
      expect(classifyDose(smoked, 4.0), DoseClass.strong);
      expect(classifyDose(smoked, 10.0), DoseClass.heavy);
      expect(classifyDose(oral, 0.5), DoseClass.belowThreshold);
      expect(classifyDose(oral, 1.0), DoseClass.threshold);
      expect(classifyDose(oral, 10.0), DoseClass.strong);
    });

    test('routes without published bands classify as null', () {
      expect(classifyDose(sublingual, 5), isNull);
    });
  });

  group('dose estimate', () {
    test('a whole 1 g joint at 20% is 200 mg in the flower but not 200 mg absorbed', () {
      final e = estimateCannabisDose(method: CannabisMethod.joint, grams: 1, thcPercent: 20);
      expect(e.productThcMg, closeTo(200, 1e-9));
      expect(e.absorbedCentralMg, closeTo(36, 1e-9));
      expect(e.absorbedLowMg, closeTo(16, 1e-9));
      expect(e.absorbedHighMg, closeTo(60, 1e-9));
      expect(e.classRange(smoked), (DoseClass.heavy, DoseClass.heavy));
    });

    test('a small bowl spans light to strong, because absorption is uncertain', () {
      final e = estimateCannabisDose(method: CannabisMethod.pipe, grams: 0.1, thcPercent: 15);
      expect(e.productThcMg, closeTo(15, 1e-9));
      expect(e.bandAmountLowMg, closeTo(1.2, 1e-9));
      expect(e.bandAmountCentralMg, closeTo(2.7, 1e-9));
      expect(e.bandAmountHighMg, closeTo(4.5, 1e-9));
      expect(e.classRange(smoked), (DoseClass.light, DoseClass.strong));
      expect(classifyDose(smoked, e.bandAmountCentralMg!), DoseClass.common);
    });

    test('share of the joint smoked scales the dose linearly', () {
      final whole = estimateCannabisDose(method: CannabisMethod.joint, grams: 1, thcPercent: 20);
      final quarter = estimateCannabisDose(method: CannabisMethod.joint, grams: 1, thcPercent: 20, fractionUsed: 0.25);
      expect(quarter.productThcMg, closeTo(whole.productThcMg / 4, 1e-9));
      expect(quarter.absorbedCentralMg, closeTo(whole.absorbedCentralMg / 4, 1e-9));
    });

    test('edible label mg is compared to the oral bands directly', () {
      final e = estimateCannabisDose(method: CannabisMethod.edible, labelThcMg: 10);
      expect(e.bandAmountCentralMg, 10);
      expect(e.absorbedCentralMg, closeTo(1.0, 1e-9)); // about 10% reaches the blood
      expect(e.classRange(oral), (DoseClass.strong, DoseClass.strong));
      final small = estimateCannabisDose(method: CannabisMethod.edible, labelThcMg: 2.5);
      expect(small.classRange(oral).$1, DoseClass.light);
    });

    test('tinctures have no band comparison', () {
      final e = estimateCannabisDose(method: CannabisMethod.tincture, labelThcMg: 10);
      expect(e.bandAmountCentralMg, isNull);
      expect(e.classRange(sublingual), (null, null));
      expect(e.absorbedCentralMg, closeTo(1.2, 1e-9));
    });

    test('a 10 mg-THC cigarette is light-to-common and a 25 mg one strong, like the Spindle 2018 arms', () {
      // 10 mg of THC in the product, 18% absorbed = 1.8 mg (light, reaching common at the
      // high estimate); 25 mg = 4.5 mg is "strong". Volunteers rated 10 mg as moderate.
      final ten = estimateCannabisDose(method: CannabisMethod.joint, labelThcMg: 10);
      final twentyFive = estimateCannabisDose(method: CannabisMethod.joint, labelThcMg: 25);
      expect(ten.absorbedCentralMg, closeTo(1.8, 1e-9));
      expect(classifyDose(smoked, ten.bandAmountCentralMg!), DoseClass.light);
      expect(ten.bandAmountHighMg! >= smoked.doseCommon!.min!, isTrue); // common is within reach at the high end
      expect(classifyDose(smoked, twentyFive.bandAmountCentralMg!), DoseClass.strong);
    });

    test('inhaled centre sits inside the published 8-24% systemic availability band', () {
      expect(inhaledBioavailability.central, inInclusiveRange(0.08, 0.24));
      expect(inhaledBioavailability.low, 0.08);
      expect(inhaledBioavailability.high, 0.30);
    });

    test('sublingual absorbs about as little as swallowing, not like smoking', () {
      expect(sublingualBioavailability.central, lessThan(inhaledBioavailability.central));
      expect(sublingualBioavailability.central, closeTo(oralBioavailability.central, 0.05));
    });

    test('vaping and dabbing absorb more than smoking, edibles less', () {
      double central(CannabisMethod m) => bioavailabilityFor(m).central;
      expect(central(CannabisMethod.vape), greaterThan(central(CannabisMethod.joint)));
      expect(central(CannabisMethod.dab), central(CannabisMethod.vape));
      expect(central(CannabisMethod.edible), lessThan(central(CannabisMethod.joint)));
      for (final m in CannabisMethod.values) {
        final b = bioavailabilityFor(m);
        expect(b.low, lessThan(b.central), reason: '$m');
        expect(b.central, lessThan(b.high), reason: '$m');
        expect(b.source, isNotEmpty);
      }
    });

    test('CBD and the THC:CBD ratio', () {
      final e = estimateCannabisDose(method: CannabisMethod.edible, labelThcMg: 10, labelCbdMg: 20);
      expect(e.productCbdMg, 20);
      expect(e.thcToCbdRatio, closeTo(0.5, 1e-9));
      expect(estimateCannabisDose(method: CannabisMethod.edible, labelThcMg: 10).thcToCbdRatio, isNull);
      final flower = estimateCannabisDose(method: CannabisMethod.bong, grams: 0.5, thcPercent: 10, cbdPercent: 5);
      expect(flower.productCbdMg, closeTo(25, 1e-9));
    });

    test('invalid input is rejected', () {
      expect(() => estimateCannabisDose(method: CannabisMethod.joint, grams: 1), throwsArgumentError);
      expect(() => estimateCannabisDose(method: CannabisMethod.joint), throwsArgumentError);
      expect(() => estimateCannabisDose(method: CannabisMethod.joint, grams: 1, thcPercent: 120), throwsArgumentError);
      expect(() => estimateCannabisDose(method: CannabisMethod.joint, grams: -1, thcPercent: 20), throwsArgumentError);
      expect(() => estimateCannabisDose(method: CannabisMethod.edible, labelThcMg: -5), throwsArgumentError);
      expect(() => estimateCannabisDose(method: CannabisMethod.joint, grams: 1, thcPercent: 20, fractionUsed: 1.5), throwsArgumentError);
    });

    test('maps each method to a reference route', () {
      expect(CannabisMethod.joint.route, 'smoked');
      expect(CannabisMethod.dab.route, 'smoked');
      expect(CannabisMethod.edible.route, 'oral');
      expect(CannabisMethod.tincture.route, 'sublingual');
      for (final m in CannabisMethod.values) {
        expect(cannabis.route(m.route), isNotNull, reason: '$m');
      }
    });
  });

  group('curves', () {
    final start = DateTime.utc(2026, 7, 3, 20);
    CannabisCurve curveFor(RouteOfAdministration roa, double amount) =>
        CannabisCurve(CurveIngestion(substanceKey: 'cannabis', roaId: roa.id, amount: amount, occurredAt: start), roa);

    /// Minute of the highest intensity, scanning one-minute steps for 24 hours.
    int peakMinute(CannabisCurve c) {
      var best = 0;
      var bestValue = -1.0;
      for (var m = 0; m <= 24 * 60; m++) {
        final v = c.intensity(start.add(Duration(minutes: m)));
        if (v > bestValue) {
          bestValue = v;
          best = m;
        }
      }
      return best;
    }

    test('inhaled peaks at 25-30 minutes and is mostly gone within 4 hours', () {
      final c = curveFor(smoked, 3);
      expect(peakMinute(c), inInclusiveRange(25, 30));
      final peak = c.intensity(start.add(Duration(minutes: peakMinute(c))));
      expect(c.intensity(start.add(const Duration(hours: 1))), closeTo(0.78 * peak, 0.02 * peak));
      expect(c.intensity(start.add(const Duration(hours: 2))), closeTo(0.39 * peak, 0.02 * peak));
      expect(c.intensity(start.add(const Duration(hours: 4))), lessThan(0.12 * peak));
    });

    test('sublingual peaks after about 75-95 minutes, between inhaled and oral', () {
      final sub = curveFor(sublingual, 3);
      expect(peakMinute(sub), inInclusiveRange(75, 95));
      expect(peakMinute(sub), greaterThan(peakMinute(curveFor(smoked, 3))));
      expect(peakMinute(sub), lessThan(peakMinute(curveFor(oral, 10))));
    });

    test('edibles peak at 2-3 hours and last far longer than smoking', () {
      final inhaled = curveFor(smoked, 3);
      final eaten = curveFor(oral, 10);
      expect(peakMinute(eaten), inInclusiveRange(100, 180));
      expect(peakMinute(eaten), greaterThan(peakMinute(inhaled) + 60));
      expect(eaten.endsAt.isAfter(inhaled.endsAt.add(const Duration(hours: 3))), isTrue);
      // Still clearly present 6 hours in, which matches the 4-10 hour total in the reference data.
      final peak = eaten.intensity(start.add(Duration(minutes: peakMinute(eaten))));
      expect(eaten.intensity(start.add(const Duration(hours: 6))), greaterThan(0.2 * peak));
    });

    test('nothing happens before the dose or before an edible kicks in', () {
      expect(curveFor(smoked, 3).intensity(start.subtract(const Duration(minutes: 5))), 0);
      expect(curveFor(oral, 10).intensity(start.add(const Duration(minutes: 10))), 0);
      expect(curveFor(oral, 10).intensity(start.add(const Duration(minutes: 40))), greaterThan(0));
    });

    test('height follows the dose factor and is capped like the generic curve', () {
      final common = curveFor(smoked, smoked.doseCommon!.min!);
      final double peakOfCommon = common.intensity(start.add(Duration(minutes: peakMinute(common))));
      expect(peakOfCommon, closeTo(1.0, 0.01));

      final double peakOfDouble = curveFor(smoked, 2 * smoked.doseCommon!.min!)
          .intensity(start.add(Duration(minutes: peakMinute(common))));
      expect(peakOfDouble, closeTo(2.0, 0.02));

      final huge = curveFor(smoked, 1000);
      expect(huge.intensity(start.add(Duration(minutes: peakMinute(huge)))), closeTo(maxDoseFactor, 0.03));
    });

    test('intensity is never negative and ends below 3% of the peak', () {
      for (final roa in [smoked, oral, sublingual]) {
        final c = curveFor(roa, 4);
        var peak = 0.0;
        for (var m = 0; m <= 24 * 60; m += 5) {
          final v = c.intensity(start.add(Duration(minutes: m)));
          expect(v, greaterThanOrEqualTo(0));
          if (v > peak) peak = v;
        }
        expect(c.intensity(c.endsAt.add(const Duration(minutes: 1))), lessThan(0.031 * peak), reason: roa.id);
      }
    });

    test('the session series uses the cannabis model by default', () {
      final dose = CurveIngestion(substanceKey: 'cannabis', roaId: 'cannabis:oral', amount: 10, occurredAt: start);
      final withModel = sessionEffectSeries([dose], byKey, now: start.add(const Duration(hours: 1)));
      final generic = sessionEffectSeries([dose], byKey, now: start.add(const Duration(hours: 1)), useRouteModels: false);
      expect(withModel.map((p) => p.$2).toList(), isNot(generic.map((p) => p.$2).toList()));
      expect(withModel.first.$2, 0.0);
      expect(withModel.any((p) => p.$2 > 0), isTrue);
    });
  });
}
