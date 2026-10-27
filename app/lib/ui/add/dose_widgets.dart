import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/cannabis_products.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../units/custom_unit_picker.dart';
import 'dose_presets.dart';

enum CannabisEntryMode { product, label }

/// A custom unit ("1 pill = 120 mg") picked for the dose.
class CustomUnitChoice {
  const CustomUnitChoice({
    required this.id,
    required this.name,
    required this.singular,
    required this.plural,
    required this.dosePerUnit,
    this.stdDevPerUnit,
    this.isEstimate = false,
  });

  factory CustomUnitChoice.fromRow(CustomUnit row) => CustomUnitChoice(
        id: row.id,
        name: row.name,
        singular: row.unitSingular,
        plural: row.unitPlural ?? pluralize(row.unitSingular),
        dosePerUnit: row.doseOfOneUnit ?? 0,
        stdDevPerUnit: row.doseStdDev,
        isEstimate: row.isEstimate,
      );

  final String id;
  final String name;
  final String singular;
  final String plural;
  final double dosePerUnit;
  final double? stdDevPerUnit;
  final bool isEstimate;

  String label(double count) => count == 1 ? singular : plural;
}

/// "pill" becomes "pills"; units already plural-looking are left alone.
String pluralize(String unit) => unit.endsWith('s') ? unit : '${unit}s';

/// What the user has typed for the dose, kept as text until validated.
class DoseInput {
  const DoseInput({
    this.text = '',
    this.unknown = false,
    this.isEstimate = false,
    this.stdDevText = '',
    this.method,
    this.mode,
    this.gramsText = '',
    this.thcText = '',
    this.labelMgText = '',
    this.cbdText = '',
    this.fraction = 1.0,
    this.volumeText = '',
    this.volumeUnit = 'oz',
    this.abvText = '',
    this.unit,
    this.unitCountText = '',
    this.productId,
    this.productName,
    this.mushroomForm = 'dried',
    this.mushroomText = '',
    this.presetNonce = 0,
  });

  const DoseInput.empty() : this();

  final String text;
  final bool unknown;
  final bool isEstimate;
  final String stdDevText;

  // Cannabis
  final CannabisMethod? method;
  final CannabisEntryMode? mode;
  final String gramsText;
  final String thcText;
  final String labelMgText;
  final String cbdText;
  final double fraction;

  // Alcohol drink calculator
  final String volumeText;
  final String volumeUnit;
  final String abvText;

  // A custom unit ("2 pills") instead of a plain dose
  final CustomUnitChoice? unit;
  final String unitCountText;

  /// A saved cannabis product this dose came from.
  final String? productId;
  final String? productName;

  // Psilocybin mushrooms: what was weighed ('dried', 'fresh' or 'mg' of pure psilocybin) and the number typed.
  final String mushroomForm;
  final String mushroomText;

  /// Bumped when a preset fills the form, so fields that only read their starting value redraw.
  final int presetNonce;

  DoseInput copyWith({
    String? text,
    bool? unknown,
    bool? isEstimate,
    String? stdDevText,
    CannabisMethod? method,
    CannabisEntryMode? mode,
    String? gramsText,
    String? thcText,
    String? labelMgText,
    String? cbdText,
    double? fraction,
    String? volumeText,
    String? volumeUnit,
    String? abvText,
    bool clearMode = false,
    CustomUnitChoice? unit,
    bool clearUnit = false,
    String? unitCountText,
    String? productId,
    String? productName,
    bool clearProduct = false,
    String? mushroomForm,
    String? mushroomText,
    int? presetNonce,
  }) =>
      DoseInput(
        text: text ?? this.text,
        unknown: unknown ?? this.unknown,
        isEstimate: isEstimate ?? this.isEstimate,
        stdDevText: stdDevText ?? this.stdDevText,
        method: method ?? this.method,
        mode: clearMode ? null : (mode ?? this.mode),
        gramsText: gramsText ?? this.gramsText,
        thcText: thcText ?? this.thcText,
        labelMgText: labelMgText ?? this.labelMgText,
        cbdText: cbdText ?? this.cbdText,
        fraction: fraction ?? this.fraction,
        volumeText: volumeText ?? this.volumeText,
        volumeUnit: volumeUnit ?? this.volumeUnit,
        abvText: abvText ?? this.abvText,
        unit: clearUnit ? null : (unit ?? this.unit),
        unitCountText: unitCountText ?? this.unitCountText,
        productId: clearProduct ? null : (productId ?? this.productId),
        productName: clearProduct ? null : (productName ?? this.productName),
        mushroomForm: mushroomForm ?? this.mushroomForm,
        mushroomText: mushroomText ?? this.mushroomText,
        presetNonce: presetNonce ?? this.presetNonce,
      );

  /// What a preset remembers. A custom unit ("2 pills") is not saved: save the preset from a plain dose.
  Map<String, Object?> toPresetJson() => {
        'text': text,
        'isEstimate': isEstimate,
        'stdDevText': stdDevText,
        'method': method?.name,
        'mode': mode?.name,
        'gramsText': gramsText,
        'thcText': thcText,
        'labelMgText': labelMgText,
        'cbdText': cbdText,
        'fraction': fraction,
        'volumeText': volumeText,
        'volumeUnit': volumeUnit,
        'abvText': abvText,
        'productId': productId,
        'productName': productName,
        'mushroomForm': mushroomForm,
        'mushroomText': mushroomText,
      };

  /// Fills this input from a saved preset's JSON, ignoring anything it does not understand.
  DoseInput withPreset(Map<String, dynamic> j) {
    String str(String k, String fallback) => j[k] is String ? j[k] as String : fallback;
    CannabisMethod? method;
    CannabisEntryMode? mode;
    for (final m in CannabisMethod.values) {
      if (m.name == j['method']) method = m;
    }
    for (final m in CannabisEntryMode.values) {
      if (m.name == j['mode']) mode = m;
    }
    return DoseInput(
      text: str('text', ''),
      isEstimate: j['isEstimate'] == true,
      stdDevText: str('stdDevText', ''),
      method: method,
      mode: mode,
      gramsText: str('gramsText', ''),
      thcText: str('thcText', ''),
      labelMgText: str('labelMgText', ''),
      cbdText: str('cbdText', ''),
      fraction: (j['fraction'] as num?)?.toDouble() ?? 1.0,
      volumeText: str('volumeText', ''),
      volumeUnit: str('volumeUnit', 'oz'),
      abvText: str('abvText', ''),
      productId: j['productId'] as String?,
      productName: j['productName'] as String?,
      mushroomForm: str('mushroomForm', 'dried'),
      mushroomText: str('mushroomText', ''),
      presetNonce: presetNonce + 1,
    );
  }

  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  /// Grams of dried mushrooms for what was weighed: dried as is, fresh at a tenth (about 90% water),
  /// and pure psilocybin at about 10 mg per gram of dried P. cubensis.
  static double? mushroomDriedGrams(String form, String text) {
    final n = _num(text);
    if (n == null || n <= 0) return null;
    return switch (form) {
      'fresh' => n / 10,
      'mg' => n / 10,
      _ => n,
    };
  }

  /// "0.25" rather than "0.250000".
  static String formatGrams(double g) {
    final t = g.toStringAsFixed(3);
    return t.contains('.') ? t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : t;
  }

  double? get unitCount => _num(unitCountText);

  /// The dose in the route's unit: a custom unit's count times its dose, else the typed number.
  double? get dose {
    final u = unit;
    if (u != null) {
      final n = unitCount;
      return n == null ? null : n * u.dosePerUnit;
    }
    return _num(text);
  }

  double? get stdDev => _num(stdDevText);

  CannabisMethod methodFor(RouteOfAdministration roa) =>
      method != null && method!.route == roa.route
          ? method!
          : CannabisMethod.values.firstWhere((m) => m.route == roa.route);

  CannabisEntryMode modeFor(CannabisMethod m) => mode ?? (m.isInhaled ? CannabisEntryMode.product : CannabisEntryMode.label);

  /// The cannabis estimate if the typed numbers are valid, otherwise null.
  CannabisDoseEstimate? cannabisEstimate(RouteOfAdministration roa) {
    final m = methodFor(roa);
    try {
      if (modeFor(m) == CannabisEntryMode.product) {
        final grams = _num(gramsText);
        final thc = _num(thcText);
        if (grams == null || thc == null || grams <= 0 || thc <= 0) return null;
        return estimateCannabisDose(
          method: m,
          grams: grams,
          thcPercent: thc,
          cbdPercent: _num(cbdText),
          fractionUsed: m.isInhaled ? fraction : 1.0,
        );
      }
      final label = _num(labelMgText);
      if (label == null || label <= 0) return null;
      return estimateCannabisDose(method: m, labelThcMg: label, labelCbdMg: _num(cbdText));
    } on ArgumentError {
      return null;
    }
  }

  /// Grams of ethanol from the drink calculator, or null if incomplete.
  double? get alcoholGrams {
    final volume = _num(volumeText);
    final abv = _num(abvText);
    if (volume == null || abv == null || volume <= 0 || abv <= 0 || abv > 100) return null;
    // Same formula as Alcohol mode and Alcohol Tracker, so a drink is the same number everywhere.
    return drinkGrams(volume, volumeUnit, abv);
  }

  String? validate(RouteOfAdministration roa) {
    if (roa.substanceKey == 'cannabis') {
      if (cannabisEstimate(roa) == null) return 'Enter the amount and THC (percent, or label mg).';
      return null;
    }
    final chosen = unit;
    if (chosen != null) {
      final n = unitCount;
      if (n == null || n <= 0) return 'Enter how many ${chosen.plural}.';
      return null;
    }
    if (unknown) return null;
    final d = dose;
    if (d == null) return 'Enter a dose, or mark it as unknown.';
    if (d <= 0) return 'The dose must be greater than zero.';
    if (isEstimate && stdDevText.trim().isNotEmpty && (stdDev == null || stdDev! < 0)) {
      return 'The uncertainty must be a number of zero or more.';
    }
    return null;
  }

  DoseStorage toStorage(RouteOfAdministration roa) {
    if (roa.substanceKey == 'cannabis') {
      final m = methodFor(roa);
      final e = cannabisEstimate(roa)!;
      return DoseStorage(
        dose: e.bandAmountCentralMg ?? e.productThcMg,
        unit: 'mg',
        isEstimate: true,
        stdDev: null,
        absorbedMg: e.absorbedCentralMg,
        method: m.name,
        productId: productId,
        details: {
          if (productName != null) 'product': productName,
          'mode': modeFor(m).name,
          if (modeFor(m) == CannabisEntryMode.product) ...{
            'grams': _num(gramsText),
            'thcPercent': _num(thcText),
            'fractionUsed': m.isInhaled ? fraction : 1.0,
          } else
            'labelThcMg': _num(labelMgText),
          'cbd': cbdText.trim(),
          'productThcMg': e.productThcMg,
          'productCbdMg': e.productCbdMg,
          'absorbedLowMg': e.absorbedLowMg,
          'absorbedCentralMg': e.absorbedCentralMg,
          'absorbedHighMg': e.absorbedHighMg,
          'bioavailability': [e.bioavailability.low, e.bioavailability.central, e.bioavailability.high],
        },
      );
    }
    final chosen = unit;
    if (chosen != null) {
      final n = unitCount!;
      return DoseStorage(
        dose: dose,
        unit: roa.unit,
        isEstimate: chosen.isEstimate,
        // Units from one batch are alike, so the uncertainty adds up rather than averaging out.
        stdDev: chosen.isEstimate && chosen.stdDevPerUnit != null ? n * chosen.stdDevPerUnit! : null,
        absorbedMg: null,
        method: null,
        customUnitId: chosen.id,
        details: {
          'unitCount': n,
          'unitName': chosen.name,
          'unitSingular': chosen.singular,
          'unitPlural': chosen.plural,
          'dosePerUnit': chosen.dosePerUnit,
        },
      );
    }
    final volume = _num(volumeText);
    final abv = _num(abvText);
    final drink = roa.substanceKey == 'alcohol' && !unknown && volume != null && abv != null && volume > 0 && abv > 0;
    return DoseStorage(
      dose: unknown ? null : dose,
      unit: roa.unit,
      isEstimate: !unknown && isEstimate,
      stdDev: !unknown && isEstimate ? stdDev : null,
      absorbedMg: null,
      method: null,
      // Keep what was actually poured, so it reads "12 fl oz at 5%" rather than grams of ethanol.
      details: drink
          ? {'drink': '', 'volume': volume, 'volumeUnit': volumeUnit, 'abv': abv}
          : (roa.substanceKey == 'psilocybin_mushrooms' && !unknown && mushroomText.trim().isNotEmpty)
              ? {'form': mushroomForm, 'entered': _num(mushroomText)}
              : const {},
    );
  }
}

class DoseStorage {
  const DoseStorage({
    required this.dose,
    required this.unit,
    required this.isEstimate,
    required this.stdDev,
    required this.absorbedMg,
    required this.method,
    required this.details,
    this.customUnitId,
    this.productId,
  });
  final double? dose;
  final String unit;
  final bool isEstimate;
  final double? stdDev;
  final double? absorbedMg;
  final String? method;
  final Map<String, Object?> details;
  final String? customUnitId;
  final String? productId;

  String get detailsJson => jsonEncode(details);
}

String doseClassLabel(DoseClass c) => switch (c) {
      DoseClass.belowThreshold => 'Below threshold',
      DoseClass.threshold => 'Threshold',
      DoseClass.light => 'Light',
      DoseClass.common => 'Common',
      DoseClass.strong => 'Strong',
      DoseClass.heavy => 'Heavy',
    };

Color doseClassColor(ColorScheme scheme, DoseClass c) => switch (c) {
      DoseClass.belowThreshold || DoseClass.threshold => scheme.surfaceContainerHighest,
      DoseClass.light => scheme.secondaryContainer,
      DoseClass.common => scheme.primaryContainer,
      DoseClass.strong => scheme.tertiaryContainer,
      DoseClass.heavy => scheme.errorContainer,
    };

/// The route's dose bands, with the band the current dose falls in highlighted.
class DoseBands extends StatelessWidget {
  const DoseBands({super.key, required this.roa, this.low, this.high});

  final RouteOfAdministration roa;

  /// The dose to highlight; give [low] and [high] for a range (cannabis).
  final double? low;
  final double? high;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String range(DoseRange? r) {
      if (r?.min == null || r?.max == null) return '';
      String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
      return '${f(r!.min!)}-${f(r.max!)}';
    }

    final lowClass = low == null ? null : classifyDose(roa, low!);
    final highClass = high == null ? lowClass : classifyDose(roa, high!);
    bool active(DoseClass c) =>
        lowClass != null && highClass != null && c.index >= lowClass.index && c.index <= highClass.index;

    final bands = <(DoseClass, String)>[
      if (roa.doseThreshold != null) (DoseClass.threshold, '${formatDose(roa.doseThreshold, null)}+'),
      if (roa.doseLight?.min != null) (DoseClass.light, range(roa.doseLight)),
      if (roa.doseCommon?.min != null) (DoseClass.common, range(roa.doseCommon)),
      if (roa.doseStrong?.min != null) (DoseClass.strong, range(roa.doseStrong)),
      if (roa.doseHeavy != null) (DoseClass.heavy, '${formatDose(roa.doseHeavy, null)}+'),
    ];
    if (bands.isEmpty) {
      return Text('No dose bands are published for this route.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final (cls, label) in bands)
              Container(
                key: ValueKey('band-${cls.name}'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: active(cls) ? doseClassColor(scheme, cls) : null,
                  border: Border.all(color: active(cls) ? scheme.primary : scheme.outlineVariant, width: active(cls) ? 2 : 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${doseClassLabel(cls)} $label ${roa.unit}', style: Theme.of(context).textTheme.labelMedium),
              ),
          ],
        ),
        if (lowClass != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Text(
              key: const ValueKey('dose-class-text'),
              lowClass == highClass
                  ? 'About a ${doseClassLabel(lowClass).toLowerCase()} dose'
                  : 'Between a ${doseClassLabel(lowClass).toLowerCase()} and a ${doseClassLabel(highClass!).toLowerCase()} dose',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
      ],
    );
  }
}

/// Dose entry for one route. Cannabis and alcohol get purpose-built helpers.
class DoseEditor extends StatelessWidget {
  const DoseEditor({super.key, required this.substance, required this.roa, required this.value, required this.onChanged});

  final Substance substance;
  final RouteOfAdministration roa;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  Widget build(BuildContext context) {
    final form = substance.key == 'cannabis'
        ? _CannabisForm(roa: roa, value: value, onChanged: onChanged)
        : _GenericForm(substance: substance, roa: roa, value: value, onChanged: onChanged);
    // Alcohol has its own drink presets and quick add; every other substance gets dose presets.
    if (substance.key == 'alcohol') return form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DosePresetBar(substance: substance, roa: roa, value: value, onChanged: onChanged),
        KeyedSubtree(key: ValueKey('dose-form-${value.presetNonce}'), child: form),
      ],
    );
  }
}

class _GenericForm extends ConsumerStatefulWidget {
  const _GenericForm({required this.substance, required this.roa, required this.value, required this.onChanged});

  final Substance substance;
  final RouteOfAdministration roa;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  ConsumerState<_GenericForm> createState() => _GenericFormState();
}

class _GenericFormState extends ConsumerState<_GenericForm> {
  // A controller (rather than initialValue) so "Use" from the drink calculator can fill the field.
  late final TextEditingController _doseController = TextEditingController(text: widget.value.text);

  @override
  void didUpdateWidget(_GenericForm old) {
    super.didUpdateWidget(old);
    if (widget.value.text != _doseController.text) _doseController.text = widget.value.text;
  }

  @override
  void dispose() {
    _doseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final substance = widget.substance;
    final roa = widget.roa;
    final value = widget.value;
    final onChanged = widget.onChanged;
    final dose = value.dose;
    final units = [
      for (final u in ref.watch(customUnitsProvider).value ?? const <CustomUnit>[])
        if (u.substanceKey == substance.key && u.route == roa.route && !u.isArchived && u.doseOfOneUnit != null) u,
    ];
    final chosen = value.unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomUnitPicker(
          substance: substance,
          roa: roa,
          units: units,
          value: value,
          onChanged: onChanged,
        ),
        if (!value.unknown && chosen == null && _isMushroom(substance, roa)) _MushroomEntry(value: value, onChanged: onChanged),
        if (!value.unknown && chosen == null && !_isMushroom(substance, roa))
          TextField(
            key: const ValueKey('dose-field'),
            controller: _doseController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Dose', suffixText: roa.unit),
            onChanged: (t) => onChanged(value.copyWith(text: t)),
          ),
        if (substance.key == 'alcohol' && !value.unknown && chosen == null) ...[
          const SizedBox(height: Gap.md),
          _AlcoholCalculator(value: value, onChanged: onChanged),
        ],
        if (chosen == null)
        SwitchListTile(
          key: const ValueKey('unknown-dose'),
          contentPadding: EdgeInsets.zero,
          title: const Text("I don't know the dose"),
          value: value.unknown,
          onChanged: (v) => onChanged(value.copyWith(unknown: v)),
        ),
        if (!value.unknown || chosen != null) ...[
          if (chosen == null) SwitchListTile(
            key: const ValueKey('estimate-dose'),
            contentPadding: EdgeInsets.zero,
            title: const Text('This is an estimate'),
            value: value.isEstimate,
            onChanged: (v) => onChanged(value.copyWith(isEstimate: v)),
          ),
          if (value.isEstimate && chosen == null)
            TextFormField(
              key: const ValueKey('std-dev'),
              initialValue: value.stdDevText,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Plus or minus (optional)', suffixText: roa.unit),
              onChanged: (t) => onChanged(value.copyWith(stdDevText: t)),
            ),
          const SizedBox(height: Gap.md),
          DoseBands(roa: roa, low: dose != null && dose > 0 ? dose : null),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Text(
              'Without a dose the timeline uses the common dose for this route.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

bool _isMushroom(Substance substance, RouteOfAdministration roa) => substance.key == 'psilocybin_mushrooms' && roa.route == 'oral';

/// Mushrooms are weighed in grams, dried or fresh, not in mg of psilocybin. This takes either (or mg
/// of pure psilocybin) and keeps the dose as grams of dried mushrooms, which is what the reference
/// bands and the timeline use.
class _MushroomEntry extends StatelessWidget {
  const _MushroomEntry({required this.value, required this.onChanged});

  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  Widget build(BuildContext context) {
    final form = value.mushroomForm;
    final dried = DoseInput.mushroomDriedGrams(form, value.mushroomText);
    final small = Theme.of(context).textTheme.bodySmall;

    void update({String? newForm, String? text}) {
      final f = newForm ?? form;
      final t = text ?? value.mushroomText;
      final g = DoseInput.mushroomDriedGrams(f, t);
      onChanged(value.copyWith(mushroomForm: f, mushroomText: t, text: g == null ? '' : DoseInput.formatGrams(g)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          key: const ValueKey('mushroom-form'),
          segments: const [
            ButtonSegment(value: 'dried', label: Text('Dried g')),
            ButtonSegment(value: 'fresh', label: Text('Fresh g')),
            ButtonSegment(value: 'mg', label: Text('Pure mg')),
          ],
          selected: {form},
          onSelectionChanged: (s) => update(newForm: s.first),
        ),
        const SizedBox(height: Gap.sm),
        TextFormField(
          key: ValueKey('mushroom-amount-$form'),
          initialValue: value.mushroomText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: switch (form) {
              'fresh' => 'Weight of fresh mushrooms',
              'mg' => 'Pure psilocybin',
              _ => 'Weight of dried mushrooms',
            },
            suffixText: form == 'mg' ? 'mg' : 'g',
          ),
          onChanged: (t) => update(text: t),
        ),
        const SizedBox(height: 4),
        Text(
          switch (form) {
            'fresh' => 'Fresh mushrooms are about 90% water, so this counts as a tenth of its weight in dried mushrooms.',
            'mg' => 'Converted at about 10 mg of psilocybin per gram of dried P. cubensis.',
            _ => 'Dried P. cubensis holds roughly 6 to 12 mg psilocybin per gram and varies up to 10x between batches.',
          },
          style: small,
        ),
        if (dried != null && form != 'dried')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('= ${DoseInput.formatGrams(dried)} g dried (about ${(dried * 10).toStringAsFixed(dried * 10 < 10 ? 1 : 0)} mg psilocybin)', key: const ValueKey('mushroom-dried'), style: small),
          ),
        const SizedBox(height: Gap.sm),
      ],
    );
  }
}

class _AlcoholCalculator extends StatelessWidget {
  const _AlcoholCalculator({required this.value, required this.onChanged});

  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  Widget build(BuildContext context) {
    final grams = value.alcoholGrams;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drink calculator', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('drink-volume'),
                    initialValue: value.volumeText,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Volume'),
                    onChanged: (t) => onChanged(value.copyWith(volumeText: t)),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'oz', label: Text('fl oz')),
                    ButtonSegment(value: 'shots', label: Text('shots')),
                    ButtonSegment(value: 'ml', label: Text('ml')),
                  ],
                  selected: {value.volumeUnit},
                  onSelectionChanged: (s) => onChanged(value.copyWith(volumeUnit: s.first)),
                ),
                const SizedBox(width: Gap.sm),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    key: const ValueKey('drink-abv'),
                    initialValue: value.abvText,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ABV', suffixText: '%'),
                    onChanged: (t) => onChanged(value.copyWith(abvText: t)),
                  ),
                ),
              ],
            ),
            if (grams != null) ...[
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${grams.toStringAsFixed(1)} g ethanol (about ${(grams / 14).toStringAsFixed(1)} US standard drinks)',
                      key: const ValueKey('alcohol-grams'),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('use-grams'),
                    onPressed: () => onChanged(value.copyWith(text: grams.toStringAsFixed(1))),
                    child: const Text('Use'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CannabisForm extends ConsumerWidget {
  const _CannabisForm({required this.roa, required this.value, required this.onChanged});

  final RouteOfAdministration roa;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  static String methodLabel(CannabisMethod m) => switch (m) {
        CannabisMethod.joint => 'Joint',
        CannabisMethod.blunt => 'Blunt',
        CannabisMethod.pipe => 'Pipe',
        CannabisMethod.bong => 'Bong',
        CannabisMethod.vape => 'Vape',
        CannabisMethod.dab => 'Dab',
        CannabisMethod.edible => 'Edible',
        CannabisMethod.tincture => 'Tincture',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(cannabisProductsProvider).value ?? const <Product>[];
    final methods = [for (final m in CannabisMethod.values) if (m.route == roa.route) m];
    final method = value.methodFor(roa);
    final mode = value.modeFor(method);
    final estimate = value.cannabisEstimate(roa);
    final range = estimate?.classRange(roa);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saved.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            key: const ValueKey('cannabis-product-pick'),
            initialValue: saved.any((p) => p.id == value.productId) ? value.productId : null,
            decoration: const InputDecoration(labelText: 'Saved product (optional)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final p in saved) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
            ],
            onChanged: (id) {
              if (id == null) return onChanged(value.copyWith(clearProduct: true));
              onChanged(_withProduct(value, saved.firstWhere((p) => p.id == id)));
            },
          ),
          const SizedBox(height: Gap.md),
        ],
        KeyedSubtree(
          key: ValueKey('cannabis-fields-${value.productId}'),
          child: _fields(context, methods, method, mode, estimate, range),
        ),
      ],
    );
  }

  /// Fills the THC and CBD from a saved product, and the label mg for edibles.
  static DoseInput _withProduct(DoseInput v, Product p) {
    final d = ProductDetails.of(p);
    String n(double? x) => x == null ? '' : (x == x.roundToDouble() ? x.toStringAsFixed(0) : '$x');
    final label = d.thcMgPerUnit != null;
    return v.copyWith(
      productId: p.id,
      productName: p.name,
      thcText: n(p.thcPercent),
      cbdText: label ? '' : n(p.cbdPercent),
      labelMgText: n(d.thcMgPerUnit),
      mode: label ? CannabisEntryMode.label : (p.thcPercent != null ? CannabisEntryMode.product : null),
    );
  }

  Widget _fields(BuildContext context, List<CannabisMethod> methods, CannabisMethod method, CannabisEntryMode mode,
      CannabisDoseEstimate? estimate, (dynamic, dynamic)? range) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (methods.length > 1)
          DropdownButtonFormField<CannabisMethod>(
            key: const ValueKey('cannabis-method'),
            initialValue: method,
            decoration: const InputDecoration(labelText: 'How'),
            items: [for (final m in methods) DropdownMenuItem(value: m, child: Text(methodLabel(m)))],
            onChanged: (m) => onChanged(value.copyWith(method: m, clearMode: true)),
          ),
        const SizedBox(height: Gap.md),
        SegmentedButton<CannabisEntryMode>(
          segments: const [
            ButtonSegment(value: CannabisEntryMode.product, label: Text('Flower / concentrate')),
            ButtonSegment(value: CannabisEntryMode.label, label: Text('Label mg')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onChanged(value.copyWith(mode: s.first)),
        ),
        const SizedBox(height: Gap.md),
        if (mode == CannabisEntryMode.product) ...[
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('cannabis-grams'),
                  initialValue: value.gramsText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', suffixText: 'g'),
                  onChanged: (t) => onChanged(value.copyWith(gramsText: t)),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('cannabis-thc'),
                  initialValue: value.thcText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'THC', suffixText: '%'),
                  onChanged: (t) => onChanged(value.copyWith(thcText: t)),
                ),
              ),
            ],
          ),
          if (method.isInhaled) ...[
            const SizedBox(height: Gap.sm),
            Text('Share you consumed: ${(value.fraction * 100).round()}%'),
            Slider(
              key: const ValueKey('cannabis-fraction'),
              value: value.fraction,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              label: '${(value.fraction * 100).round()}%',
              onChanged: (v) => onChanged(value.copyWith(fraction: v)),
            ),
            Text(
              'A joint passed around or left unfinished is not 100%.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ] else
          TextFormField(
            key: const ValueKey('cannabis-label-mg'),
            initialValue: value.labelMgText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'THC on the label', suffixText: 'mg'),
            onChanged: (t) => onChanged(value.copyWith(labelMgText: t)),
          ),
        const SizedBox(height: Gap.md),
        if (estimate == null)
          Text('Enter the amount to see an estimate.', style: Theme.of(context).textTheme.bodySmall)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THC consumed: ${estimate.productThcMg.toStringAsFixed(1)} mg', key: const ValueKey('cannabis-product')),
                  const SizedBox(height: 4),
                  Text(
                    'Estimated absorbed: ${estimate.absorbedLowMg.toStringAsFixed(1)} to ${estimate.absorbedHighMg.toStringAsFixed(1)} mg '
                    '(about ${estimate.absorbedCentralMg.toStringAsFixed(1)} mg)',
                    key: const ValueKey('cannabis-absorbed'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Absorption varies several-fold between people and products (${estimate.bioavailability.confidence} confidence).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.md),
                  if (range != null && range.$1 != null)
                    DoseBands(roa: roa, low: estimate.bandAmountLowMg, high: estimate.bandAmountHighMg)
                  else
                    Text(
                      'This route has no published dose bands, so no dose class is shown.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Gap.sm),
        TextFormField(
          key: const ValueKey('cannabis-cbd'),
          initialValue: value.cbdText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'CBD (optional)',
            suffixText: mode == CannabisEntryMode.product ? '%' : 'mg',
          ),
          onChanged: (t) => onChanged(value.copyWith(cbdText: t)),
        ),
      ],
    );
  }
}
