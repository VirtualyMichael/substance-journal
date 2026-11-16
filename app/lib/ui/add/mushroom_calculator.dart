import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/mushroom_reference.dart';
import '../../providers.dart';
import '../design.dart';
import '../safety/potency_testing_page.dart';
import '../toast.dart';
import 'dose_widgets.dart';

const _quickForms = {'dried', 'fresh', 'mg'};

const _otherForms = {
  'powder': 'Powder (weighed)',
  'capsule': 'Capsules',
  'edible': 'Chocolate / gummy',
  'tea': 'Tea (dried weight used)',
  'lemon_tek': 'Lemon tek (dried weight used)',
};

String _n(double v) => DoseInput.formatGrams(v);
String _mg(double v) => v.toStringAsFixed(v < 10 ? 1 : 0);

/// Psilocybin mushrooms in the add flow: what was weighed or counted, and a calculator that turns
/// it into an estimate of psilocybin equivalents with a range. The dose stays grams of dried
/// mushroom (what the bands, the tolerance model and older entries use); the estimate and the
/// inputs go into the entry's details. It informs, it never suggests an amount.
class MushroomEntry extends ConsumerWidget {
  const MushroomEntry({super.key, required this.roa, required this.value, required this.onChanged});

  final RouteOfAdministration roa;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  void _update({String? form, String? text, MushroomCalc? calc}) {
    final next = value.copyWith(mushroomForm: form, mushroomText: text, mushroomCalc: calc);
    final e = next.mushroomResult(roa).estimate;
    onChanged(next.copyWith(text: e == null ? '' : DoseInput.formatGrams(e.driedGrams)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = value.mushroomForm;
    final calc = value.mushroomCalc;
    final small = Theme.of(context).textTheme.bodySmall;
    final estimate = value.mushroomResult(roa).estimate;

    TextFormField number(String key, String label, String initial, String suffix, ValueChanged<String> changed) => TextFormField(
          key: ValueKey(key),
          initialValue: initial,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          onChanged: changed,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          key: const ValueKey('mushroom-form'),
          segments: const [
            ButtonSegment(value: 'dried', label: Text('Dried g')),
            ButtonSegment(value: 'fresh', label: Text('Fresh g')),
            ButtonSegment(value: 'mg', label: Text('Pure mg')),
            ButtonSegment(value: 'other', label: Text('Other')),
          ],
          selected: {_quickForms.contains(form) ? form : 'other'},
          onSelectionChanged: (s) => _update(form: s.first == 'other' ? 'capsule' : s.first),
        ),
        const SizedBox(height: Gap.sm),
        if (!_quickForms.contains(form)) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('mushroom-other-form'),
            initialValue: _otherForms.containsKey(form) ? form : 'capsule',
            decoration: const InputDecoration(labelText: 'Form'),
            items: [for (final e in _otherForms.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (f) => _update(form: f),
          ),
          const SizedBox(height: Gap.sm),
        ],
        if (form == 'capsule')
          Row(children: [
            Expanded(child: number('mushroom-count', 'Capsules', calc.count, '', (t) => _update(calc: value.mushroomCalc.copyWith(count: t)))),
            const SizedBox(width: Gap.sm),
            Expanded(child: number('mushroom-per-unit', 'Mushroom in each', calc.perUnit, 'mg', (t) => _update(calc: value.mushroomCalc.copyWith(perUnit: t)))),
          ])
        else if (form == 'edible') ...[
          Row(children: [
            Expanded(child: number('mushroom-count', 'Pieces', calc.count, '', (t) => _update(calc: value.mushroomCalc.copyWith(count: t)))),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: number('mushroom-per-unit-${calc.edibleUnit}', calc.edibleUnit == 'mg' ? 'Psilocybin per piece' : 'Mushroom per piece', calc.perUnit,
                  calc.edibleUnit, (t) => _update(calc: value.mushroomCalc.copyWith(perUnit: t))),
            ),
          ]),
          const SizedBox(height: Gap.sm),
          SegmentedButton<String>(
            key: const ValueKey('mushroom-edible-unit'),
            segments: const [
              ButtonSegment(value: 'g', label: Text('Label: g mushroom')),
              ButtonSegment(value: 'mg', label: Text('Label: mg psilocybin')),
            ],
            selected: {calc.edibleUnit},
            onSelectionChanged: (s) => _update(calc: value.mushroomCalc.copyWith(edibleUnit: s.first)),
          ),
        ] else
          number(
            'mushroom-amount-$form',
            switch (form) {
              'fresh' => 'Weight of fresh mushrooms',
              'mg' => 'Pure psilocybin',
              'powder' => 'Weight of powder',
              'tea' || 'lemon_tek' => 'Dried mushrooms used',
              _ => 'Weight of dried mushrooms',
            },
            value.mushroomText,
            form == 'mg' ? 'mg' : 'g',
            (t) => _update(text: t),
          ),
        const SizedBox(height: 4),
        Text(
          switch (form) {
            'fresh' => 'Fresh mushrooms are about 90% water, so this counts as a tenth of its weight in dried mushrooms.',
            'mg' => 'Converted at about 10 mg of psilocybin per gram of dried P. cubensis.',
            _ => 'Published analyses of dried P. cubensis range from under 2 to about 28 mg per gram; the app assumes 10 mg/g unless you give the batch\'s potency below.',
          },
          style: small,
        ),
        if (estimate != null && form != 'dried')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('= ${_n(estimate.driedGrams)} g dried (about ${_mg(estimate.expectedMg)} mg psilocybin)', key: const ValueKey('mushroom-dried'), style: small),
          ),
        const SizedBox(height: Gap.sm),
        if (form != 'mg' && !(form == 'edible' && calc.edibleUnit == 'mg'))
          _Calculator(roa: roa, value: value, update: _update)
        else
          _ResultCard(value: value, roa: roa),
        const SizedBox(height: Gap.sm),
      ],
    );
  }
}

/// The estimate in mg with its range, where it lands, warnings, and the formula behind it.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.value, required this.roa, this.children = const []});
  final DoseInput value;
  final RouteOfAdministration roa;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = value.mushroomResult(roa);
    final e = result.estimate;
    return Card(
      key: const ValueKey('mushroom-calculator'),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Psilocybin estimate', style: text.titleSmall),
            const SizedBox(height: 4),
            if (result.error != null)
              Text(result.error!, key: const ValueKey('mushroom-error'), style: TextStyle(color: scheme.error))
            else if (e == null)
              Text('Enter the amount to see an estimate.', style: text.bodySmall)
            else ...[
              Text(
                e.lowMg == e.highMg
                    ? 'About ${_mg(e.expectedMg)} mg psilocybin'
                    : 'About ${_mg(e.expectedMg)} mg psilocybin equivalents (range ${_mg(e.lowMg)} to ${_mg(e.highMg)} mg)',
                key: const ValueKey('mushroom-estimate'),
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (e.potencyPct != null)
                Text(
                  'At the app\'s 10 mg/g scale that is like ${_n(e.expectedMg / 10)} g of dried mushroom '
                  '(range ${_n(e.lowMg / 10)} to ${_n(e.highMg / 10)} g); the dose bands below use the middle figure.',
                  key: const ValueKey('mushroom-equivalent'),
                  style: text.bodySmall,
                ),
              for (var i = 0; i < e.warnings.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e.warnings[i], key: ValueKey('mushroom-warning-$i'), style: text.bodySmall?.copyWith(color: scheme.error)),
                ),
            ],
            ...children,
            ExpansionTile(
              key: const ValueKey('mushroom-formula'),
              tilePadding: EdgeInsets.zero,
              title: Text('How this is worked out', style: text.labelLarge),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mushroomFormula, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (e != null) for (final a in e.assumptions) Text('• $a', style: text.bodySmall),
                const SizedBox(height: 4),
                Text('Sources', style: text.labelMedium),
                for (final s in {molarMassSource, moistureSource, partsSource, fruitBodyCvSource, stabilitySource, ...unknownCubensisSources})
                  SelectableText(s, style: text.labelSmall),
              ],
            ),
            Text(
              'An estimate, not a measurement. Wild and home-grown mushrooms vary a lot, even between mushrooms of one batch, '
              'and caps and stems differ. This informs; it does not tell you how much to take.',
              key: const ValueKey('mushroom-caveat'),
              style: text.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('mushroom-get-tested'),
                icon: const Icon(Icons.science_outlined, size: 18),
                label: const Text('Get your batch tested'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PotencyTestingPage())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Potency, dryness, caps or stems, storage, the batch and its calibration.
class _Calculator extends ConsumerWidget {
  const _Calculator({required this.roa, required this.value, required this.update});
  final RouteOfAdministration roa;
  final DoseInput value;
  final void Function({String? form, String? text, MushroomCalc? calc}) update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final calc = value.mushroomCalc;
    final strains = ref.watch(strainReferenceProvider).value ?? StrainReference.empty;
    final selected = strains.find(calc.strain);
    final source = potencySourceFrom(calc.potencySource);
    void set(MushroomCalc c) => update(calc: c);
    final fieldKey = '${calc.strain}|${calc.potencySource}|${calc.batchId}';

    // Ratings recorded for this batch, for a personal calibration.
    final person = ref.watch(currentPersonProvider);
    final history = person == null ? const <Ingestion>[] : ref.watch(personIngestionsProvider(person.id)).value ?? const <Ingestion>[];
    final ratings = calc.batchId == null ? const <BatchFeel>[] : batchRatings(history, calc.batchId!);
    final estimate = value.mushroomResult(roa).estimate;
    final currentPct = estimate?.potencyPct ?? defaultPotencyPct;
    final calibration = calibrate(currentPct, ratings);

    return _ResultCard(
      value: value,
      roa: roa,
      children: [
        ExpansionTile(
          key: const ValueKey('mushroom-details'),
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: calc.hasPotency || calc.batchId != null,
          title: Text(calc.batchName == null ? 'Batch potency, dryness, caps or stems' : 'Batch: ${calc.batchName}', style: text.labelLarge),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('mushroom-strain-$fieldKey'),
              initialValue: selected?.name ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Strain (published analyses)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not listed / unknown')),
                for (final s in strains.strains) DropdownMenuItem(value: s.name, child: Text('${s.name}  (~${s.equivalentPct.toStringAsFixed(2)}%)')),
              ],
              onChanged: (name) {
                final s = strains.find(name ?? '');
                if (s == null) {
                  set(calc.copyWith(strain: '', clearPublished: true, potencySource: calc.potencySource == 'published' ? 'defaultValue' : null,
                      psilocybinPct: calc.potencySource == 'published' ? '' : null, psilocinPct: calc.potencySource == 'published' ? '' : null));
                  return;
                }
                set(calc.copyWith(
                  strain: s.name,
                  psilocybinPct: s.psilocybinPct.toStringAsFixed(3),
                  psilocinPct: s.psilocinPct.toStringAsFixed(3),
                  potencySource: 'published',
                  potencyDetail: s.analyses.first.source.split(',').first,
                  publishedLowPct: s.lowPct,
                  publishedHighPct: s.highPct,
                ));
              },
            ),
            if (selected != null) ...[
              const SizedBox(height: 4),
              for (final a in selected.analyses)
                Text('• ${a.psilocybinPct}% psilocybin, ${a.psilocinPct}% psilocin: ${a.material}. ${a.note} (${a.source})', style: text.bodySmall),
              if (selected.note.isNotEmpty) Text(selected.note, key: const ValueKey('mushroom-strain-note'), style: text.bodySmall),
            ] else
              Text(
                'Popular strains such as Golden Teacher have little or no published analysis, and community reports vary. '
                'Use your own lab result or estimate if you have one.',
                style: text.bodySmall,
              ),
            const SizedBox(height: Gap.sm),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('mushroom-psilocybin-$fieldKey'),
                  initialValue: calc.psilocybinPct,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Psilocybin', suffixText: '% dry'),
                  onChanged: (t) => set(value.mushroomCalc.copyWith(psilocybinPct: t, potencySource: _ownSource(value.mushroomCalc), clearPublished: value.mushroomCalc.potencySource == 'published')),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: TextFormField(
                  key: ValueKey('mushroom-psilocin-$fieldKey'),
                  initialValue: calc.psilocinPct,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Psilocin', suffixText: '% dry'),
                  onChanged: (t) => set(value.mushroomCalc.copyWith(psilocinPct: t, potencySource: _ownSource(value.mushroomCalc), clearPublished: value.mushroomCalc.potencySource == 'published')),
                ),
              ),
            ]),
            Text('1% = 10 mg per gram. Leave both empty to use the app\'s 10 mg/g with the full published range.', style: text.bodySmall),
            const SizedBox(height: Gap.sm),
            if (calc.hasPotency) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('mushroom-source-$fieldKey'),
                initialValue: source == PotencySource.defaultValue ? PotencySource.estimate.name : source.name,
                decoration: const InputDecoration(labelText: 'Where the number came from'),
                items: [
                  for (final s in [PotencySource.labTest, PotencySource.published, PotencySource.estimate, PotencySource.calibration])
                    DropdownMenuItem(value: s.name, child: Text(potencySourceLabel(s))),
                ],
                onChanged: (s) => set(value.mushroomCalc.copyWith(potencySource: s)),
              ),
              TextFormField(
                key: ValueKey('mushroom-source-detail-$fieldKey'),
                initialValue: calc.potencyDetail,
                decoration: const InputDecoration(labelText: 'Lab and date, study, or what it is based on'),
                onChanged: (t) => set(value.mushroomCalc.copyWith(potencyDetail: t)),
              ),
              const SizedBox(height: Gap.sm),
            ],
            if (value.mushroomForm != 'fresh') ...[
              Text('How dry', style: text.labelMedium),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                key: const ValueKey('mushroom-dryness'),
                segments: const [
                  ButtonSegment(value: 'typical', label: Text('Dried')),
                  ButtonSegment(value: 'dry', label: Text('Cracker dry')),
                  ButtonSegment(value: 'damp', label: Text('Not fully dry')),
                ],
                selected: {calc.dryness},
                onSelectionChanged: (s) => set(value.mushroomCalc.copyWith(dryness: s.first)),
              ),
              if (calc.dryness == 'damp')
                TextFormField(
                  key: const ValueKey('mushroom-water'),
                  initialValue: calc.water,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Water in the weight, roughly', suffixText: '%'),
                  onChanged: (t) => set(value.mushroomCalc.copyWith(water: t)),
                ),
              const SizedBox(height: Gap.sm),
            ],
            Text('Which part', style: text.labelMedium),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              key: const ValueKey('mushroom-part'),
              segments: const [
                ButtonSegment(value: 'whole', label: Text('Whole')),
                ButtonSegment(value: 'caps', label: Text('Caps')),
                ButtonSegment(value: 'stems', label: Text('Stems')),
              ],
              selected: {calc.part},
              onSelectionChanged: (s) => set(value.mushroomCalc.copyWith(part: s.first)),
            ),
            const SizedBox(height: Gap.sm),
            Text('Storage loss, your own guess: ${calc.degradationPct.round()}%', style: text.labelMedium),
            Slider(
              key: const ValueKey('mushroom-loss'),
              value: calc.degradationPct.clamp(0, 50).toDouble(),
              max: 50,
              divisions: 10,
              label: '${calc.degradationPct.round()}%',
              onChanged: (v) => set(value.mushroomCalc.copyWith(degradationPct: v)),
            ),
            Text(
              'No published loss rate for dried mushrooms was found. One study kept dried mushrooms best in the dark at room temperature '
              'and lost most from fresh mushrooms frozen at -80 C; another found capsules unchanged after 11 months.',
              style: text.bodySmall,
            ),
            if (calibration != null) ...[
              const SizedBox(height: Gap.sm),
              Text(
                'Your ${calibration.ratings} rating${calibration.ratings == 1 ? '' : 's'} of this batch suggest about '
                '${calibration.suggestedPct.toStringAsFixed(2)}% instead of ${currentPct.toStringAsFixed(2)}%. '
                'Personal calibration from how it felt, damped and limited to x${maxCalibrationFactor.toStringAsFixed(0)} either way. '
                'Feelings depend on tolerance, set and setting too: this is not a measurement and not dosing advice.',
                key: const ValueKey('mushroom-calibration'),
                style: text.bodySmall,
              ),
              TextButton(
                key: const ValueKey('mushroom-use-calibration'),
                onPressed: () => set(value.mushroomCalc.copyWith(
                  psilocybinPct: calibration.suggestedPct.toStringAsFixed(3),
                  psilocinPct: '0',
                  potencySource: PotencySource.calibration.name,
                  potencyDetail: 'From ${calibration.ratings} rating${calibration.ratings == 1 ? '' : 's'} of this batch',
                  clearPublished: true,
                )),
                child: const Text('Use the calibrated figure'),
              ),
            ],
            const SizedBox(height: Gap.sm),
            Wrap(spacing: Gap.sm, children: [
              if (estimate != null)
                OutlinedButton.icon(
                  key: const ValueKey('mushroom-save-batch'),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Save as batch'),
                  onPressed: () => _saveBatch(context, ref, existing: false),
                ),
              if (estimate != null && calc.batchId != null)
                OutlinedButton.icon(
                  key: const ValueKey('mushroom-update-batch'),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Update batch'),
                  onPressed: () => _saveBatch(context, ref, existing: true),
                ),
            ]),
          ],
        ),
      ],
    );
  }

  /// Typing your own figure over a published or default one makes it your estimate.
  static String? _ownSource(MushroomCalc c) =>
      c.potencySource == PotencySource.published.name || c.potencySource == PotencySource.defaultValue.name ? PotencySource.estimate.name : null;

  Future<void> _saveBatch(BuildContext context, WidgetRef ref, {required bool existing}) async {
    final calc = value.mushroomCalc;
    final estimate = value.mushroomResult(roa).estimate;
    if (estimate == null) return;
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _BatchDialog(name: existing ? (calc.batchName ?? '') : (calc.strain.isEmpty ? '' : '${calc.strain} batch'), strain: calc.strain),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    final (name, strain, notes) = result;
    final db = ref.read(databaseProvider);
    final batch = <String, Object?>{
      'strain': strain.trim(),
      'psilocybinPct': calc.psilocybinPct,
      'psilocinPct': calc.psilocinPct,
      'source': calc.potencySource,
      'sourceDetail': calc.potencyDetail,
      'notes': notes.trim(),
      'form': value.mushroomForm,
    };
    final withStrain = calc.copyWith(strain: strain.trim());
    String id;
    if (existing && calc.batchId != null) {
      id = calc.batchId!;
      final input = value.copyWith(mushroomCalc: withStrain.copyWith(batchName: name.trim())).toPresetJson();
      await db.updateDosePreset(id, name: name, amount: estimate.driedGrams, input: input, extra: {'batch': batch});
    } else {
      final preset = await db.addDosePreset(
        substanceKey: roa.substanceKey,
        route: roa.route,
        name: name,
        amount: estimate.driedGrams,
        unit: roa.unit,
        input: value.toPresetJson(),
        extra: {'batch': batch},
      );
      id = preset.id;
      // Store the batch's own id in its form, so every way of logging from it (presets, Quick log) links back.
      final input = value.copyWith(mushroomCalc: withStrain.copyWith(batchId: id, batchName: name.trim())).toPresetJson();
      await db.updateDosePreset(id, name: name, amount: estimate.driedGrams, input: input, extra: {'batch': batch});
    }
    update(calc: withStrain.copyWith(batchId: id, batchName: name.trim()));
    if (context.mounted) ScaffoldMessenger.of(context).showToast(SnackBar(content: Text('Batch "${name.trim()}" saved')));
  }

}

/// The ratings recorded on entries logged from batch [batchId].
List<BatchFeel> batchRatings(List<Ingestion> history, String batchId) {
  final out = <BatchFeel>[];
  for (final i in history) {
    if (i.deleted || i.substanceKey != 'psilocybin_mushrooms') continue;
    try {
      final d = jsonDecode(i.detailsJson);
      if (d is! Map || d['batchId'] != batchId) continue;
      final f = batchFeelFrom(d['batchFeel']);
      if (f != null) out.add(f);
    } on Object {
      continue;
    }
  }
  return out;
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({required this.name, required this.strain});
  final String name;
  final String strain;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _strain = TextEditingController(text: widget.strain);
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _strain.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Save batch'),
        content: SizedBox(
          width: min(420, MediaQuery.sizeOf(context).width),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('batch-name'), controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name, e.g. "Golden Teacher, spring grow"')),
            TextField(key: const ValueKey('batch-strain'), controller: _strain, decoration: const InputDecoration(labelText: 'Strain (optional)')),
            TextField(key: const ValueKey('batch-notes'), controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            const SizedBox(height: Gap.sm),
            Text(
              'Saves the potency, where it came from, the form and the amount as a preset, so the next entry from this batch is one tap.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('batch-save'),
            onPressed: () => Navigator.pop(context, (_name.text, _strain.text, _notes.text)),
            child: const Text('Save'),
          ),
        ],
      );
}
