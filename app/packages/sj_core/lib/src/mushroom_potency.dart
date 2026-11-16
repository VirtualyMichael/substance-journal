import 'dart:convert';
import 'dart:math';

/// Psilocybin mushroom calculator: from what was weighed (or counted) and what is known about the
/// batch, an estimate of psilocybin equivalents in mg with a low-expected-high range.
///
/// It informs, it does not advise: it never suggests an amount to take. Every constant below has
/// its source next to it, and the screen shows the formula and the assumptions with the result.

/// g/mol, PubChem CID 10624 (C12H17N2O4P).
const double psilocybinMolarMass = 284.25;

/// g/mol, PubChem CID 4980 (C12H16N2O).
const double psilocinMolarMass = 204.27;

/// Psilocybin is a phosphate prodrug of psilocin, so 1 mg of psilocin is as much active drug as
/// 284.25 / 204.27 = 1.39 mg of psilocybin.
const double psilocinToPsilocybin = psilocybinMolarMass / psilocinMolarMass;

const String molarMassSource = 'PubChem: psilocybin CID 10624 (284.25 g/mol), psilocin CID 4980 (204.27 g/mol)';

/// The app's long-standing assumption when nothing is known about a batch: 10 mg per gram (1%).
const double defaultPotencyPct = 1.0;

/// Published range for dried P. cubensis, as psilocybin equivalents (% of dry weight).
/// Low: a user-provided "Libelula" sample, psilocybin 0.056% + psilocin 0.098% (Rodriguez 2025).
/// High: psilocybin 2.57% + psilocin 0.16% in an oven-dried batch (Galdino 2025).
const double unknownCubensisLowPct = 0.19;
const double unknownCubensisHighPct = 2.8;
const List<String> unknownCubensisSources = [
  'Rodriguez L et al. (2025) Novel qNMR method to quantify psilocybin and psilocin in psychedelic mushrooms. ACS Omega 10:55725-55732. https://doi.org/10.1021/acsomega.5c07092',
  'Galdino TP et al. (2025) A new chromatographic method for psilocybin and psilocin in Psilocybe cubensis. ACS Omega 10:30695-30707. https://pmc.ncbi.nlm.nih.gov/articles/PMC12290642/',
  'Sharchaton A et al. (2026) Variability in tryptamine profiles of Psilocybe cubensis across 14 strains. J Fungi 12:486. https://doi.org/10.3390/jof12070486',
  'Goff R et al. (2024) Psilocybin and psilocin content in multiple Psilocybe cubensis strains by LC-MS/MS. Anal Chim Acta 1288:342161. https://doi.org/10.1016/j.aca.2023.342161',
  'Foster K et al. (2026) Toward standardized products containing biomass of Psilocybe cubensis. J AOAC Int 109:51-60 (mean 1.14 +/- 0.17%). https://doi.org/10.1093/jaoacint/qsaf072',
];

/// Largest fruiting-body-to-fruiting-body variation within one grow (coefficient of variation of
/// psilocybin, 12.8-23.4% across six strains): even a lab result on one sample can be this far off
/// for other mushrooms of the same batch.
const double fruitBodyCv = 0.234;
const String fruitBodyCvSource = 'Sharchaton A et al. (2026) J Fungi 12:486, Table 2. https://doi.org/10.3390/jof12070486';

/// Water in fresh culinary mushrooms, USDA FoodData Central (SR Legacy): white mushrooms 92.45 g,
/// enoki 88.3 g per 100 g. No measured figure for P. cubensis was found; the app's 90% sits inside.
const double freshWaterExpected = 0.90;
const double freshWaterLow = 0.883;
const double freshWaterHigh = 0.9245;

/// Water left in dried mushrooms: USDA dried shiitake holds 9.5 g per 100 g. Used as the low end
/// when it is not known how dry the material is.
const double driedWaterHigh = 0.095;
const String moistureSource = 'USDA FoodData Central: Mushrooms, white, raw (FDC 169251) 92.45 g water/100 g; Mushrooms, enoki, raw (FDC 169382) 88.3 g; Mushrooms, shiitake, dried (FDC 168436) 9.5 g';

/// Caps held about twice as much as stems (1.03 vs 0.52 wt%), but the difference was not
/// statistically significant because individual mushrooms varied so much.
const double capsOverStems = 1.03 / 0.52;
const String partsSource = 'Gotvaldova K et al. (2021) Stability of psilocybin and its four analogs in the biomass of Psilocybe cubensis. Drug Test Anal 13:439-446. https://doi.org/10.1002/dta.2950';

const String stabilitySource = 'Gotvaldova 2021 (dried, dark, room temperature kept best; fresh frozen at -80 C lost most; no loss rate given); Foster 2026 (encapsulated dried biomass kept its content for 11 months)';

/// Where a potency figure came from.
enum PotencySource { defaultValue, published, labTest, estimate, calibration }

String potencySourceLabel(PotencySource s) => switch (s) {
      PotencySource.defaultValue => 'App default (no batch data)',
      PotencySource.published => 'Published analysis',
      PotencySource.labTest => 'Your lab test',
      PotencySource.estimate => 'Your estimate',
      PotencySource.calibration => 'Your calibration',
    };

PotencySource potencySourceFrom(String? name) =>
    PotencySource.values.firstWhere((s) => s.name == name, orElse: () => PotencySource.defaultValue);

/// What was taken, as typed: everything is kept as text so a half-typed number survives a redraw.
class MushroomCalc {
  const MushroomCalc({
    this.count = '',
    this.perUnit = '',
    this.edibleUnit = 'g',
    this.dryness = 'typical',
    this.water = '',
    this.part = 'whole',
    this.psilocybinPct = '',
    this.psilocinPct = '',
    this.potencySource = 'defaultValue',
    this.potencyDetail = '',
    this.strain = '',
    this.degradationPct = 0,
    this.batchId,
    this.batchName,
    this.publishedLowPct,
    this.publishedHighPct,
  });

  /// Capsules or edible pieces.
  final String count;

  /// mg of mushroom powder per capsule, or g of mushroom / mg of psilocybin per edible piece.
  final String perUnit;

  /// For edibles: 'g' of mushroom per piece or 'mg' of psilocybin per piece, as labelled.
  final String edibleUnit;

  /// 'typical' (dried, not sure how dry), 'dry' (cracker or bone dry), 'damp' (with [water]).
  final String dryness;
  final String water;

  /// 'whole', 'caps' or 'stems'.
  final String part;
  final String psilocybinPct;
  final String psilocinPct;
  final String potencySource;

  /// Lab name and date, the study, or what the estimate is based on.
  final String potencyDetail;
  final String strain;

  /// The user's own guess of potency lost to age or storage, 0-50.
  final double degradationPct;

  /// The saved batch (dose preset) this came from.
  final String? batchId;
  final String? batchName;

  /// The published range (psilocybin equivalents, %) when the potency came from the strain reference.
  final double? publishedLowPct;
  final double? publishedHighPct;

  bool get hasPotency => _num(psilocybinPct) != null || _num(psilocinPct) != null;

  MushroomCalc copyWith({
    String? count,
    String? perUnit,
    String? edibleUnit,
    String? dryness,
    String? water,
    String? part,
    String? psilocybinPct,
    String? psilocinPct,
    String? potencySource,
    String? potencyDetail,
    String? strain,
    double? degradationPct,
    String? batchId,
    String? batchName,
    bool clearBatch = false,
    double? publishedLowPct,
    double? publishedHighPct,
    bool clearPublished = false,
  }) =>
      MushroomCalc(
        count: count ?? this.count,
        perUnit: perUnit ?? this.perUnit,
        edibleUnit: edibleUnit ?? this.edibleUnit,
        dryness: dryness ?? this.dryness,
        water: water ?? this.water,
        part: part ?? this.part,
        psilocybinPct: psilocybinPct ?? this.psilocybinPct,
        psilocinPct: psilocinPct ?? this.psilocinPct,
        potencySource: potencySource ?? this.potencySource,
        potencyDetail: potencyDetail ?? this.potencyDetail,
        strain: strain ?? this.strain,
        degradationPct: degradationPct ?? this.degradationPct,
        batchId: clearBatch ? null : (batchId ?? this.batchId),
        batchName: clearBatch ? null : (batchName ?? this.batchName),
        publishedLowPct: clearPublished ? null : (publishedLowPct ?? this.publishedLowPct),
        publishedHighPct: clearPublished ? null : (publishedHighPct ?? this.publishedHighPct),
      );

  Map<String, Object?> toJson() => {
        'count': count,
        'perUnit': perUnit,
        'edibleUnit': edibleUnit,
        'dryness': dryness,
        'water': water,
        'part': part,
        'psilocybinPct': psilocybinPct,
        'psilocinPct': psilocinPct,
        'potencySource': potencySource,
        'potencyDetail': potencyDetail,
        'strain': strain,
        'degradationPct': degradationPct,
        'batchId': batchId,
        'batchName': batchName,
        'publishedLowPct': publishedLowPct,
        'publishedHighPct': publishedHighPct,
      };

  /// Reads what [toJson] wrote, ignoring anything missing or of the wrong type.
  static MushroomCalc fromJson(Object? json) {
    if (json is! Map) return const MushroomCalc();
    String s(String k, String fallback) => json[k] is String ? json[k] as String : (json[k] is num ? '${json[k]}' : fallback);
    return MushroomCalc(
      count: s('count', ''),
      perUnit: s('perUnit', ''),
      edibleUnit: s('edibleUnit', 'g'),
      dryness: s('dryness', 'typical'),
      water: s('water', ''),
      part: s('part', 'whole'),
      psilocybinPct: s('psilocybinPct', ''),
      psilocinPct: s('psilocinPct', ''),
      potencySource: s('potencySource', 'defaultValue'),
      potencyDetail: s('potencyDetail', ''),
      strain: s('strain', ''),
      degradationPct: ((json['degradationPct'] as num?)?.toDouble() ?? 0).clamp(0.0, 50.0).toDouble(),
      batchId: json['batchId'] as String?,
      batchName: json['batchName'] as String?,
      publishedLowPct: (json['publishedLowPct'] as num?)?.toDouble(),
      publishedHighPct: (json['publishedHighPct'] as num?)?.toDouble(),
    );
  }
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// The calculator's answer.
class MushroomEstimate {
  const MushroomEstimate({
    required this.driedGrams,
    required this.expectedMg,
    required this.lowMg,
    required this.highMg,
    required this.potencyPct,
    required this.potencyLowPct,
    required this.potencyHighPct,
    required this.assumptions,
    required this.warnings,
  });

  /// Grams of dried mushroom, what the journal stores as the dose (the reference bands, the
  /// tolerance weights and older entries all use it).
  final double driedGrams;

  /// Psilocybin equivalents (psilocybin + psilocin x 1.39), mg.
  final double expectedMg;
  final double lowMg;
  final double highMg;

  /// The potency used, as psilocybin equivalents in % of dry weight (null when mg were entered).
  final double? potencyPct;
  final double? potencyLowPct;
  final double? potencyHighPct;
  final List<String> assumptions;
  final List<String> warnings;

  Map<String, Object?> toDetails() => {
        'psilocybinEqMg': _round(expectedMg),
        'psilocybinEqMgLow': _round(lowMg),
        'psilocybinEqMgHigh': _round(highMg),
        if (potencyPct != null) 'potencyPct': _round(potencyPct!),
      };
}

double _round(double v) => double.parse(v.toStringAsFixed(2));

/// The formula, as shown on screen.
const String mushroomFormula =
    'psilocybin-equivalent mg = dry grams x 1000 x (psilocybin % + psilocin % x 1.39) / 100 x part factor x (1 - storage loss)';

/// The result of reading the inputs: an estimate, an error to show, or neither (still typing).
class MushroomResult {
  const MushroomResult({this.estimate, this.error});
  final MushroomEstimate? estimate;
  final String? error;
}

/// Potency as psilocybin equivalents (%), with its range, from what the calculator holds.
/// [publishedLow]/[publishedHigh] come with a published strain value (see [StrainReference]).
(double, double, double, String) potencyRange(MushroomCalc c, {double? publishedLow, double? publishedHigh}) {
  final pb = _num(c.psilocybinPct);
  final pc = _num(c.psilocinPct);
  if ((pb == null || pb < 0) && (pc == null || pc < 0)) {
    return (defaultPotencyPct, unknownCubensisLowPct, unknownCubensisHighPct,
        'Potency unknown: the app assumes 1% (10 mg/g); published P. cubensis analyses range from about $unknownCubensisLowPct% to $unknownCubensisHighPct%.');
  }
  final eq = max(0.0, pb ?? 0) + max(0.0, pc ?? 0) * psilocinToPsilocybin;
  final source = potencySourceFrom(c.potencySource);
  switch (source) {
    case PotencySource.published when publishedLow != null && publishedHigh != null:
      return (eq, min(publishedLow, eq), max(publishedHigh, eq),
          'Published value for this strain; other grows of the "same" strain can differ several-fold.');
    case PotencySource.estimate:
    case PotencySource.defaultValue:
      return (eq, min(unknownCubensisLowPct, eq), max(unknownCubensisHighPct, eq),
          'Your own estimate, so the range is the whole published range for P. cubensis.');
    default:
      return (eq, eq * (1 - fruitBodyCv), eq * (1 + fruitBodyCv),
          'Range +/-${(fruitBodyCv * 100).toStringAsFixed(0)}%: how much single mushrooms of one grow differed in a 2026 study.');
  }
}

/// Reads [form] and [amountText] (and [c]) into an estimate. [heavyGrams] is the route's heavy
/// band (grams of dried mushroom), used only to warn about very large numbers.
MushroomResult estimateMushroom(
  String form,
  String amountText,
  MushroomCalc c, {
  double heavyGrams = 5.0,
  double? publishedLow,
  double? publishedHigh,
}) {
  final assumptions = <String>[];
  final warnings = <String>[];

  // 1. How much mushroom (or pure psilocybin) this was.
  double? weighed; // grams of material as weighed
  double? pureMg; // mg of psilocybin stated or entered
  switch (form) {
    case 'mg':
      final n = _num(amountText);
      if (n == null) return const MushroomResult();
      if (n <= 0) return const MushroomResult(error: 'The amount must be more than zero.');
      pureMg = n;
    case 'capsule':
      final count = _num(c.count);
      final each = _num(c.perUnit);
      if (count == null || each == null) return const MushroomResult();
      if (count <= 0 || each <= 0) return const MushroomResult(error: 'Enter how many capsules and the mg in each (more than zero).');
      weighed = count * each / 1000;
      assumptions.add('${_fmt(count)} capsules x ${_fmt(each)} mg of dried mushroom powder = ${_fmt(weighed)} g.');
    case 'edible':
      final count = _num(c.count);
      final each = _num(c.perUnit);
      if (count == null || each == null) return const MushroomResult();
      if (count <= 0 || each <= 0) return const MushroomResult(error: 'Enter how many pieces and the amount in each (more than zero).');
      if (c.edibleUnit == 'mg') {
        pureMg = count * each;
        assumptions.add('${_fmt(count)} pieces x ${_fmt(each)} mg psilocybin as labelled. Labels on unregulated products are not checked by anyone.');
      } else {
        weighed = count * each;
        assumptions.add('${_fmt(count)} pieces x ${_fmt(each)} g of mushroom as labelled = ${_fmt(weighed)} g. Labels on unregulated products are not checked by anyone.');
      }
    default:
      final n = _num(amountText);
      if (n == null) return const MushroomResult();
      if (n <= 0) return const MushroomResult(error: 'The amount must be more than zero.');
      weighed = n;
  }

  if (pureMg != null) {
    final dried = pureMg / (defaultPotencyPct * 10);
    if (pureMg > heavyGrams * 10 * 2) {
      warnings.add('${_fmt(pureMg)} mg is more than twice the start of the heavy band (${_fmt(heavyGrams * 10)} mg at 10 mg/g). Check the number and the unit.');
    }
    assumptions.add('Logged as ${_fmt(dried)} g of dried mushroom at the app\'s 10 mg per gram, so the dose bands and tolerance can use it.');
    return MushroomResult(
      estimate: MushroomEstimate(
        driedGrams: dried,
        expectedMg: pureMg,
        lowMg: pureMg,
        highMg: pureMg,
        potencyPct: null,
        potencyLowPct: null,
        potencyHighPct: null,
        assumptions: assumptions,
        warnings: warnings,
      ),
    );
  }

  // 2. Dry weight.
  final w = weighed!;
  double waterE, waterLo, waterHi; // expected, the one giving least, the one giving most psilocybin
  double driedForLog;
  if (form == 'fresh') {
    waterE = freshWaterExpected;
    waterLo = freshWaterHigh;
    waterHi = freshWaterLow;
    driedForLog = w * (1 - freshWaterExpected);
    assumptions.add('Fresh mushrooms: about ${(freshWaterExpected * 100).round()}% water (culinary mushrooms ${(freshWaterLow * 100).toStringAsFixed(1)}-${(freshWaterHigh * 100).toStringAsFixed(1)}%, USDA; no P. cubensis figure found), so ${_fmt(w)} g fresh is about ${_fmt(driedForLog)} g dried.');
  } else {
    driedForLog = w;
    switch (c.dryness) {
      case 'dry':
        waterE = 0;
        waterLo = 0;
        waterHi = 0;
        assumptions.add('Cracker or bone dry: no water counted.');
      case 'damp':
        final pct = _num(c.water);
        if (pct == null) return const MushroomResult(error: 'Enter roughly how much of the weight is water (%).');
        if (pct < 0 || pct >= 90) return const MushroomResult(error: 'Water must be between 0 and 90%. Use "Fresh" for fresh mushrooms.');
        waterE = pct / 100;
        waterLo = waterE;
        waterHi = waterE;
        assumptions.add('Not fully dry: ${_fmt(pct)}% of the weight counted as water (your figure).');
      default:
        waterE = 0;
        waterLo = driedWaterHigh;
        waterHi = 0;
        assumptions.add('Dried, dryness not known: no water counted; the low end allows ${(driedWaterHigh * 100).toStringAsFixed(1)}% water (USDA dried shiitake).');
    }
  }

  // 3. Potency.
  final (pE, pLo, pHi, potencyNote) = potencyRange(c, publishedLow: publishedLow ?? c.publishedLowPct, publishedHigh: publishedHigh ?? c.publishedHighPct);
  final pb = _num(c.psilocybinPct);
  final pc = _num(c.psilocinPct);
  if ((pb ?? 0) < 0 || (pc ?? 0) < 0) return const MushroomResult(error: 'Psilocybin and psilocin percentages cannot be negative.');
  if (c.hasPotency) {
    assumptions.add('Potency ${_fmt(pb ?? 0)}% psilocybin + ${_fmt(pc ?? 0)}% psilocin x 1.39 = ${_fmt(pE)}% psilocybin equivalents (${potencySourceLabel(potencySourceFrom(c.potencySource))}${c.potencyDetail.trim().isEmpty ? '' : ': ${c.potencyDetail.trim()}'}).');
  }
  assumptions.add(potencyNote);
  if (pE > 3) warnings.add('${_fmt(pE)}% is above every published P. cubensis analysis found (at most about 2.8%). Check that it is percent of dry weight (1% = 10 mg per gram).');
  if (pE <= 0) return const MushroomResult(error: 'Enter a potency above zero, or clear it to use the default.');

  // 4. Caps or stems.
  double partE = 1, partLo = 1, partHi = 1;
  if (c.part == 'caps') {
    partHi = capsOverStems;
    assumptions.add('Caps only: may be stronger than whole mushrooms; caps held about 2x the stems in one study, not statistically significant (Gotvaldova 2021). The high end allows x${capsOverStems.toStringAsFixed(2)}.');
  } else if (c.part == 'stems') {
    partLo = 1 / capsOverStems;
    assumptions.add('Stems only: may be weaker; the low end allows x${(1 / capsOverStems).toStringAsFixed(2)} (Gotvaldova 2021).');
  }

  // 5. Storage loss, the user's own guess.
  final loss = c.degradationPct.clamp(0.0, 50.0) / 100;
  if (loss > 0) assumptions.add('Storage loss: your guess of ${(loss * 100).round()}% applied to the expected and low values. No published loss rate for dried mushrooms was found.');

  if (form == 'tea' || form == 'lemon_tek') {
    assumptions.add('Assumes everything in the mushrooms ends up in what you drink. How much a ${form == 'tea' ? 'tea' : 'lemon-juice soak'} extracts has no published measurement that could be verified; onset and intensity may differ from eating them.');
  }

  double mg(double water, double pct, double part, double l) => w * (1 - water) * 1000 * pct / 100 * part * (1 - l);
  final expected = mg(waterE, pE, partE, loss);
  final low = mg(waterLo, pLo, partLo, loss);
  final high = mg(waterHi, pHi, partHi, 0);
  if (driedForLog > heavyGrams * 2) {
    warnings.add('${_fmt(driedForLog)} g dried is more than twice the heavy band (${_fmt(heavyGrams)} g+). Check the weight, the unit and dried vs fresh.');
  }
  return MushroomResult(
    estimate: MushroomEstimate(
      driedGrams: driedForLog,
      expectedMg: expected,
      lowMg: min(low, expected),
      highMg: max(high, expected),
      potencyPct: pE,
      potencyLowPct: pLo,
      potencyHighPct: pHi,
      assumptions: assumptions,
      warnings: warnings,
    ),
  );
}

String _fmt(double v) {
  final t = v.toStringAsFixed(v.abs() >= 100 ? 0 : (v.abs() >= 10 ? 1 : 2));
  return t.contains('.') ? t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : t;
}

// ---- personal calibration ----

/// How a batch felt against what was expected, recorded after an entry.
enum BatchFeel { muchWeaker, weaker, asExpected, stronger, muchStronger }

String batchFeelLabel(BatchFeel f) => switch (f) {
      BatchFeel.muchWeaker => 'Much weaker',
      BatchFeel.weaker => 'Weaker',
      BatchFeel.asExpected => 'As expected',
      BatchFeel.stronger => 'Stronger',
      BatchFeel.muchStronger => 'Much stronger',
    };

BatchFeel? batchFeelFrom(Object? name) {
  for (final f in BatchFeel.values) {
    if (f.name == name) return f;
  }
  return null;
}

/// The app's own rule of thumb for each rating (not from any study): how far one rating moves the
/// potency estimate.
const Map<BatchFeel, double> batchFeelStep = {
  BatchFeel.muchWeaker: 0.6,
  BatchFeel.weaker: 0.8,
  BatchFeel.asExpected: 1.0,
  BatchFeel.stronger: 1.25,
  BatchFeel.muchStronger: 1.6,
};

/// Calibration never moves the estimate further than this factor either way.
const double maxCalibrationFactor = 2.0;

/// A personal calibration suggestion for one batch.
class Calibration {
  const Calibration(this.factor, this.ratings, this.suggestedPct);

  /// Multiply the batch's potency by this.
  final double factor;
  final int ratings;
  final double suggestedPct;
}

/// Combines [ratings] into a damped factor: the geometric mean of the rating steps, weighted by
/// n / (n + 2) so one or two ratings move it only part way, and held within 1/[maxCalibrationFactor]
/// to [maxCalibrationFactor]. Null with no ratings.
Calibration? calibrate(double currentPct, List<BatchFeel> ratings) {
  if (ratings.isEmpty || currentPct <= 0) return null;
  var logSum = 0.0;
  for (final r in ratings) {
    logSum += log(batchFeelStep[r]!);
  }
  final n = ratings.length;
  final damped = exp(logSum / n * (n / (n + 2)));
  final factor = damped.clamp(1 / maxCalibrationFactor, maxCalibrationFactor).toDouble();
  return Calibration(factor, n, currentPct * factor);
}

// ---- built-in strain reference ----

/// One published analysis of one strain.
class StrainAnalysis {
  const StrainAnalysis({required this.psilocybinPct, required this.psilocinPct, required this.source, this.material = '', this.note = ''});
  final double psilocybinPct;
  final double psilocinPct;
  final String source;
  final String material;
  final String note;

  double get equivalentPct => psilocybinPct + psilocinPct * psilocinToPsilocybin;
}

class StrainInfo {
  const StrainInfo({required this.name, this.analyses = const [], this.note = ''});
  final String name;
  final List<StrainAnalysis> analyses;
  final String note;

  bool get hasData => analyses.isNotEmpty;

  /// Mean of the published values, psilocybin and psilocin separately.
  double get psilocybinPct => analyses.isEmpty ? 0 : analyses.map((a) => a.psilocybinPct).reduce((a, b) => a + b) / analyses.length;
  double get psilocinPct => analyses.isEmpty ? 0 : analyses.map((a) => a.psilocinPct).reduce((a, b) => a + b) / analyses.length;
  double get equivalentPct => psilocybinPct + psilocinPct * psilocinToPsilocybin;

  /// Lowest and highest published values, widened by the fruit-body variation.
  double get lowPct => analyses.map((a) => a.equivalentPct).reduce(min) * (1 - fruitBodyCv);
  double get highPct => analyses.map((a) => a.equivalentPct).reduce(max) * (1 + fruitBodyCv);
}

class StrainReference {
  const StrainReference({required this.strains, this.verified = '', this.note = ''});
  final List<StrainInfo> strains;
  final String verified;
  final String note;

  static const empty = StrainReference(strains: []);

  StrainInfo? find(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final s in strains) {
      if (s.name.toLowerCase() == n) return s;
    }
    return null;
  }

  static StrainReference parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return StrainReference(
      verified: j['verified'] as String? ?? '',
      note: j['note'] as String? ?? '',
      strains: [
        for (final s in (j['strains'] as List).cast<Map<String, dynamic>>())
          StrainInfo(
            name: s['name'] as String,
            note: s['note'] as String? ?? '',
            analyses: [
              for (final a in (s['analyses'] as List? ?? const []).cast<Map<String, dynamic>>())
                StrainAnalysis(
                  psilocybinPct: (a['psilocybin_pct'] as num).toDouble(),
                  psilocinPct: (a['psilocin_pct'] as num?)?.toDouble() ?? 0,
                  source: a['source'] as String? ?? '',
                  material: a['material'] as String? ?? '',
                  note: a['note'] as String? ?? '',
                ),
            ],
          ),
      ],
    );
  }
}
