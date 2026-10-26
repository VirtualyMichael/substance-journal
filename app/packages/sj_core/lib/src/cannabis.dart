// Cannabis dosing and effect curves.
//
// Why this exists: PsychonautWiki's cannabis bands are mg of THC reaching you, while a
// joint's label says how much THC is in the flower (1 g at 20% = 200 mg). Treating the
// flower amount as the dose made every joint look enormous. Here the product amount is
// converted to an estimated effective dose per method, with low/central/high estimates
// because absorption varies several-fold (docs/data-audit/cannabis.md).
//
// Units of the reference bands used for classification:
//   smoked / vaporised / dabbed: mg of THC absorbed (the estimate computed here)
//   oral (edibles):              mg of THC swallowed (the label dose, which is how edibles
//                                are sold and how the bands were gathered)
//   sublingual:                  no published bands
import 'dart:math';

import 'effect_curve.dart';
import 'reference.dart';

enum CannabisMethod { joint, blunt, pipe, bong, vape, dab, edible, tincture }

extension CannabisMethodInfo on CannabisMethod {
  /// The reference-data route this method uses.
  String get route => switch (this) {
        CannabisMethod.edible => 'oral',
        CannabisMethod.tincture => 'sublingual',
        _ => 'smoked',
      };

  bool get isInhaled => route == 'smoked';
}

/// Fraction of the THC in the product that reaches the bloodstream.
class Bioavailability {
  const Bioavailability(this.low, this.central, this.high, {required this.confidence, required this.source});
  final double low;
  final double central;
  final double high;

  /// `moderate` where several sources agree, `low` where one weak source or an extrapolation.
  final String confidence;
  final String source;
}

const Bioavailability inhaledBioavailability = Bioavailability(
  0.08,
  0.18,
  0.30,
  confidence: 'moderate',
  source: 'Huestis 2007 (systemic availability ca. 8-24%, reported 2-56%), McGilveray 2005 (about 30%)',
);

const Bioavailability vaporisedBioavailability = Bioavailability(
  0.10,
  0.22,
  0.40,
  confidence: 'low',
  source: 'Spindle 2018 / Newmeyer 2016: blood THC similar to smoking, somewhat higher later; no firm percentage',
);

const Bioavailability oralBioavailability = Bioavailability(
  0.04,
  0.10,
  0.20,
  confidence: 'moderate',
  source: 'McGilveray 2005 (4-12%), pharmacist and review ranges (6-20%)',
);

const Bioavailability sublingualBioavailability = Bioavailability(
  0.05,
  0.12,
  0.25,
  confidence: 'low',
  source: 'Inferred from Karschner 2011 (oromucosal spray gave about the same exposure as swallowed THC); tinctures vary',
);

Bioavailability bioavailabilityFor(CannabisMethod method) => switch (method) {
      CannabisMethod.vape || CannabisMethod.dab => vaporisedBioavailability,
      CannabisMethod.edible => oralBioavailability,
      CannabisMethod.tincture => sublingualBioavailability,
      _ => inhaledBioavailability,
    };

/// An estimate of what one cannabis dose delivers.
class CannabisDoseEstimate {
  const CannabisDoseEstimate({
    required this.method,
    required this.productThcMg,
    required this.absorbedLowMg,
    required this.absorbedCentralMg,
    required this.absorbedHighMg,
    required this.productCbdMg,
    required this.bandAmountLowMg,
    required this.bandAmountCentralMg,
    required this.bandAmountHighMg,
    required this.bioavailability,
  });

  final CannabisMethod method;

  /// THC in the portion actually consumed, before absorption.
  final double productThcMg;
  final double absorbedLowMg;
  final double absorbedCentralMg;
  final double absorbedHighMg;
  final double productCbdMg;

  /// The number to compare with PsychonautWiki's bands (see the unit notes at the top of this
  /// file). Null for methods without published bands.
  final double? bandAmountLowMg;
  final double? bandAmountCentralMg;
  final double? bandAmountHighMg;
  final Bioavailability bioavailability;

  /// THC:CBD ratio of what was consumed (CBD = 1). Null when there is no CBD.
  double? get thcToCbdRatio => productCbdMg > 0 ? productThcMg / productCbdMg : null;

  /// Dose class at the low and high estimates. For inhaled methods these usually differ,
  /// which is the honest answer: "light to strong".
  (DoseClass?, DoseClass?) classRange(RouteOfAdministration roa) {
    if (bandAmountLowMg == null || bandAmountHighMg == null) return (null, null);
    return (classifyDose(roa, bandAmountLowMg!), classifyDose(roa, bandAmountHighMg!));
  }
}

/// Estimates the dose from a product amount.
///
/// Give either [grams] with [thcPercent] (flower, concentrate), or [labelThcMg] (an edible or
/// tincture's printed dose). [fractionUsed] is the share of the product you consumed, 0 to 1:
/// a joint passed around or left unfinished is not 100%. [cbdPercent] / [labelCbdMg] work the
/// same way for CBD.
CannabisDoseEstimate estimateCannabisDose({
  required CannabisMethod method,
  double? grams,
  double? thcPercent,
  double? labelThcMg,
  double? cbdPercent,
  double? labelCbdMg,
  double fractionUsed = 1.0,
}) {
  if (fractionUsed < 0 || fractionUsed > 1) {
    throw ArgumentError.value(fractionUsed, 'fractionUsed', 'must be between 0 and 1');
  }
  double mgFrom(double? percent, double? label, String what) {
    if (label != null) {
      if (label < 0) throw ArgumentError.value(label, what, 'must not be negative');
      return label;
    }
    if (percent == null || grams == null) return 0.0;
    if (grams < 0 || percent < 0 || percent > 100) {
      throw ArgumentError('$what: grams must be >= 0 and percent between 0 and 100');
    }
    return grams * (percent / 100.0) * 1000.0;
  }

  if (labelThcMg == null && (grams == null || thcPercent == null)) {
    throw ArgumentError('Give labelThcMg, or both grams and thcPercent');
  }

  final productThc = mgFrom(thcPercent, labelThcMg, 'THC') * fractionUsed;
  final productCbd = mgFrom(cbdPercent, labelCbdMg, 'CBD') * fractionUsed;
  final bio = bioavailabilityFor(method);

  final double? bandLow;
  final double? bandCentral;
  final double? bandHigh;
  if (method == CannabisMethod.tincture) {
    bandLow = bandCentral = bandHigh = null;
  } else if (method == CannabisMethod.edible) {
    // Oral bands are label (swallowed) mg, so there is no absorption range to apply.
    bandLow = bandCentral = bandHigh = productThc;
  } else {
    bandLow = productThc * bio.low;
    bandCentral = productThc * bio.central;
    bandHigh = productThc * bio.high;
  }

  return CannabisDoseEstimate(
    method: method,
    productThcMg: productThc,
    absorbedLowMg: productThc * bio.low,
    absorbedCentralMg: productThc * bio.central,
    absorbedHighMg: productThc * bio.high,
    productCbdMg: productCbd,
    bandAmountLowMg: bandLow,
    bandAmountCentralMg: bandCentral,
    bandAmountHighMg: bandHigh,
    bioavailability: bio,
  );
}

// ---------------------------------------------------------------------------
// Effect curves
// ---------------------------------------------------------------------------

/// Parameters of a one-compartment curve with first-order absorption (Bateman function):
///   C(t) = ka / (ka - ke) * (exp(-ke t) - exp(-ka t))   for t after [lagMinutes]
/// normalised so its peak is 1. Values are chosen so the peak time and duration agree with
/// the reference data and Grotenhermen's review (inhaled peak 15-30 min, oral peak 2-3 h).
class CannabisCurveShape {
  const CannabisCurveShape({required this.lagMinutes, required this.absorptionHalfLifeMinutes, required this.effectHalfLifeMinutes});
  final double lagMinutes;
  final double absorptionHalfLifeMinutes;
  final double effectHalfLifeMinutes;

  double get ka => ln2 / absorptionHalfLifeMinutes;
  double get ke => ln2 / effectHalfLifeMinutes;

  /// Minutes after the lag at which the curve peaks.
  double get peakAfterLagMinutes => log(ka / ke) / (ka - ke);

  double _raw(double minutes) {
    final tau = minutes - lagMinutes;
    if (tau <= 0) return 0.0;
    return ka / (ka - ke) * (exp(-ke * tau) - exp(-ka * tau));
  }

  double get _peakRaw => _raw(lagMinutes + peakAfterLagMinutes);

  /// 0 to 1, relative to the peak.
  double normalized(double minutesSinceDose) => _raw(minutesSinceDose) / _peakRaw;

  /// Minutes since the dose at which the curve has fallen below [fraction] of its peak.
  double endMinutes({double fraction = 0.03}) {
    var t = lagMinutes + peakAfterLagMinutes;
    while (normalized(t) >= fraction && t < 48 * 60) {
      t += 1;
    }
    return t;
  }
}

const CannabisCurveShape inhaledShape = CannabisCurveShape(
  lagMinutes: 0,
  absorptionHalfLifeMinutes: 8,
  effectHalfLifeMinutes: 60,
);

const CannabisCurveShape oralShape = CannabisCurveShape(
  lagMinutes: 20,
  absorptionHalfLifeMinutes: 45,
  effectHalfLifeMinutes: 120,
);

const CannabisCurveShape sublingualShape = CannabisCurveShape(
  lagMinutes: 5,
  absorptionHalfLifeMinutes: 30,
  effectHalfLifeMinutes: 120,
);

CannabisCurveShape cannabisShapeForRoute(String route) => switch (route) {
      'oral' => oralShape,
      'sublingual' => sublingualShape,
      _ => inhaledShape,
    };

/// Route-specific cannabis intensity: fast rise and short tail when inhaled, a delayed and
/// longer curve when eaten. Height scales with dose like the generic curve, via [doseFactor].
class CannabisCurve implements IntensityCurve {
  CannabisCurve(CurveIngestion ingestion, RouteOfAdministration roa)
      : occurredAt = ingestion.occurredAt,
        shape = cannabisShapeForRoute(roa.route),
        peakIntensity = doseFactor(ingestion.amount, roa);

  @override
  final DateTime occurredAt;
  final CannabisCurveShape shape;
  final double peakIntensity;

  @override
  DateTime get endsAt => occurredAt.add(Duration(microseconds: (shape.endMinutes() * Duration.microsecondsPerMinute).round()));

  @override
  double intensity(DateTime at) {
    final minutes = at.difference(occurredAt).inMicroseconds / Duration.microsecondsPerMinute;
    if (minutes <= 0) return 0.0;
    return peakIntensity * shape.normalized(minutes);
  }
}
