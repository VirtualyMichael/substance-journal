import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import 'drink_dialogs.dart';
import 'import_flow.dart';
import '../toast.dart';

/// Alcohol mode switch, the body and model settings behind the estimates, and drink presets.
class AlcoholSettingsSection extends ConsumerWidget {
  const AlcoholSettingsSection({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final mode = ref.watch(alcoholModeProvider).value ?? false;
    final presets = ref.watch(drinkPresetsProvider).value ?? const <Preset>[];
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alcohol', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Alcohol mode turns the app into a drink tracker: quick-add drinks, an estimated blood alcohol curve, history and analytics.',
          style: text.bodySmall,
        ),
        SwitchListTile(
          key: const ValueKey('alcohol-mode-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Alcohol mode'),
          value: mode,
          onChanged: (v) async {
            if (v) await db.ensureDefaultDrinkPresets();
            await db.setSetting('alcoholMode', v ? 'true' : 'false');
          },
        ),
        EstimateSettingsForm(key: ValueKey('estimates-${person.id}'), person: person),
        const SizedBox(height: Gap.sm),
        LimitsForm(key: ValueKey('limits-${person.id}'), person: person),
        const SizedBox(height: Gap.sm),
        Text('Import from Alcohol Tracker', style: text.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Bring over your drinks and presets from an Alcohol Tracker export (.json) or its database. '
          'Nothing in Alcohol Tracker is changed, and importing the same file twice adds nothing.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('import-tracker-file'),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Choose a file...'),
              onPressed: () => runTrackerImport(context, ref),
            ),
            if (ref.watch(trackerDefaultPathProvider) case final String found)
              OutlinedButton.icon(
                key: const ValueKey('import-tracker-pc'),
                icon: const Icon(Icons.computer_outlined),
                label: const Text('Use Alcohol Tracker on this computer'),
                onPressed: () => runTrackerImport(context, ref, path: found),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(child: Text('Drink presets', style: text.titleSmall)),
            TextButton.icon(
              key: const ValueKey('add-preset'),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
              onPressed: () => showPresetDialog(context, db: db),
            ),
          ],
        ),
        if (presets.isEmpty) Text('No presets. Add one, or turn on Alcohol mode to get the starter set.', style: text.bodySmall),
        for (final p in presets)
          ListTile(
            key: ValueKey('preset-${p.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_bar_outlined),
            title: Text(p.name),
            subtitle: Text('${p.amount == p.amount.roundToDouble() ? p.amount.toStringAsFixed(0) : p.amount} ${p.unit}, ${presetDrink(p).abv}%'),
            onTap: () => showPresetDialog(context, db: db, existing: p),
            trailing: IconButton(
              key: ValueKey('delete-preset-${p.id}'),
              tooltip: 'Delete preset',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                db.setDrinkPresetDeleted(p.id, true);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showToast(SnackBar(
                    content: Text('${p.name} deleted'),
                    action: SnackBarAction(label: 'Undo', onPressed: () => db.setDrinkPresetDeleted(p.id, false)),
                  ));
              },
            ),
          ),
      ],
    );
  }
}

/// The body and model constants behind one person's alcohol estimates.
class EstimateSettingsForm extends ConsumerStatefulWidget {
  const EstimateSettingsForm({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<EstimateSettingsForm> createState() => _EstimateSettingsFormState();
}

class _EstimateSettingsFormState extends ConsumerState<EstimateSettingsForm> {
  final _controllers = <String, TextEditingController>{};
  String _gender = 'M';
  String _model = bacModelWatson;
  bool _loaded = false;
  List<String> _problems = const [];
  bool _saved = false;

  static const _fields = <(String, String, String?)>[
    ('weight', 'Weight', 'lb'),
    ('height', 'Height', 'cm'),
    ('age', 'Age', 'years'),
    ('absorption', 'Absorption time', 'min'),
    ('lag', 'Absorption lag', 'min'),
    ('elimination', 'Elimination', 'drinks/h'),
    ('stdVolume', 'Standard drink volume', 'oz'),
    ('stdAbv', 'Standard drink ABV', '%'),
    ('tolHalfLife', 'Tolerance half-life', 'days'),
    ('tolMax', 'Tolerance: max extra dose', 'x'),
    ('tolHalfSat', 'Tolerance: half-saturation', '%BAC-h'),
  ];

  TextEditingController _c(String key) => _controllers.putIfAbsent(key, () => TextEditingController());

  String _n(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _fill(EstimateSettings s) {
    _c('weight').text = _n(s.userWeightLbs);
    _c('height').text = _n(s.userHeightCm);
    _c('age').text = _n(s.userAgeYears);
    _c('absorption').text = _n(s.absorptionMinutes);
    _c('lag').text = _n(s.absorptionLagMinutes);
    _c('elimination').text = _n(s.eliminationStandardDrinksPerHour);
    _c('stdVolume').text = _n(s.standardDrinkVolumeOz);
    _c('stdAbv').text = _n(s.standardDrinkAbvPercent);
    _c('tolHalfLife').text = _n(s.toleranceHalfLifeDays);
    _c('tolMax').text = _n(s.toleranceMaxExtraDose);
    _c('tolHalfSat').text = _n(s.toleranceHalfSaturationExposure);
    _gender = s.userGender.isEmpty ? 'M' : s.userGender.substring(0, 1).toUpperCase();
    _model = s.bacModel;
  }

  double? _num(String key) => double.tryParse(_c(key).text.trim().replaceAll(',', '.'));

  EstimateSettings? _read() {
    final values = {for (final f in _fields) f.$1: _num(f.$1)};
    final missing = [for (final f in _fields) if (values[f.$1] == null) f.$2];
    if (missing.isNotEmpty) {
      setState(() => _problems = ['Enter a number for: ${missing.join(', ')}.']);
      return null;
    }
    return EstimateSettings(
      userWeightLbs: values['weight']!,
      userHeightCm: values['height']!,
      userAgeYears: values['age']!,
      absorptionMinutes: values['absorption']!.round(),
      absorptionLagMinutes: values['lag']!,
      eliminationStandardDrinksPerHour: values['elimination']!,
      standardDrinkVolumeOz: values['stdVolume']!,
      standardDrinkAbvPercent: values['stdAbv']!,
      toleranceHalfLifeDays: values['tolHalfLife']!,
      toleranceMaxExtraDose: values['tolMax']!,
      toleranceHalfSaturationExposure: values['tolHalfSat']!,
      userGender: _gender,
      bacModel: _model,
    );
  }

  Future<void> _save() async {
    final s = _read();
    if (s == null) return;
    final problems = validateEstimateSettings(s);
    setState(() {
      _problems = problems;
      _saved = false;
    });
    if (problems.isNotEmpty) return;
    await ref.read(databaseProvider).setEstimateSettings(widget.person.id, s);
    if (mounted) setState(() => _saved = true);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(estimateSettingsProvider(widget.person.id));
    if (!_loaded && stored.hasValue) {
      _fill(stored.value!);
      _loaded = true;
    }
    return ExpansionTile(
      key: const ValueKey('estimates-tile'),
      tilePadding: EdgeInsets.zero,
      title: Text("${widget.person.name}'s body and estimate settings"),
      subtitle: const Text('These set how the blood alcohol estimate is calculated'),
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('est-gender'),
                initialValue: _gender,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sex'),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Male')),
                  DropdownMenuItem(value: 'F', child: Text('Female')),
                  DropdownMenuItem(value: 'O', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? _gender),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('est-model'),
                initialValue: _model,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'BAC model'),
                items: const [
                  DropdownMenuItem(value: bacModelWatson, child: Text('Watson (default)')),
                  DropdownMenuItem(value: bacModelWidmark, child: Text('Widmark')),
                ],
                onChanged: (v) => setState(() => _model = v ?? _model),
              ),
            ),
            for (final (key, label, suffix) in _fields)
              SizedBox(
                width: 170,
                child: TextField(
                  key: ValueKey('est-$key'),
                  controller: _c(key),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: label, suffixText: suffix),
                  onChanged: (_) => setState(() => _saved = false),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        for (final p in _problems) Text(p, key: const ValueKey('est-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Row(
          children: [
            FilledButton(key: const ValueKey('estimates-save'), onPressed: _save, child: const Text('Save')),
            const SizedBox(width: Gap.sm),
            TextButton(
              key: const ValueKey('estimates-reset'),
              onPressed: () => setState(() {
                _fill(const EstimateSettings());
                _problems = const [];
                _saved = false;
              }),
              child: const Text('Reset to defaults'),
            ),
            if (_saved) const Padding(padding: EdgeInsets.only(left: Gap.sm), child: Text('Saved', key: ValueKey('est-saved'))),
          ],
        ),
        const SizedBox(height: Gap.sm),
      ],
    );
  }
}

/// Limits this person sets for themselves; the Today view shows progress and warns when passed.
class LimitsForm extends ConsumerStatefulWidget {
  const LimitsForm({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<LimitsForm> createState() => _LimitsFormState();
}

class _LimitsFormState extends ConsumerState<LimitsForm> {
  final _daily = TextEditingController();
  final _weekly = TextEditingController();
  final _days = TextEditingController();
  bool _loaded = false;
  String? _message;

  @override
  void dispose() {
    _daily.dispose();
    _weekly.dispose();
    _days.dispose();
    super.dispose();
  }

  String _n(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final daily = _num(_daily.text);
    final weekly = _num(_weekly.text);
    final days = int.tryParse(_days.text.trim());
    final bad = (_daily.text.trim().isNotEmpty && (daily == null || daily <= 0)) ||
        (_weekly.text.trim().isNotEmpty && (weekly == null || weekly <= 0)) ||
        (_days.text.trim().isNotEmpty && (days == null || days < 0 || days > 7));
    if (bad) return setState(() => _message = 'Limits must be positive numbers (drinking days 0 to 7), or left blank.');
    await ref.read(databaseProvider).setLimits(widget.person.id, DrinkLimits(daily: daily, weekly: weekly, maxDrinkingDays: days));
    if (mounted) setState(() => _message = 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final limits = ref.watch(limitsProvider(widget.person.id));
    if (!_loaded && limits.hasValue) {
      final l = limits.value!;
      _daily.text = _n(l.daily);
      _weekly.text = _n(l.weekly);
      _days.text = l.maxDrinkingDays?.toString() ?? '';
      _loaded = true;
    }
    final text = Theme.of(context).textTheme;
    Widget field(String key, String label, TextEditingController c, String suffix) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: TextField(
              key: ValueKey(key),
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, suffixText: suffix),
              onChanged: (_) => setState(() => _message = null),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Limits', style: text.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Your own targets, in standard drinks. Today shows progress, and adding a drink that passes one tells you. Leave blank for none.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Row(children: [
          field('limit-daily', 'Per day', _daily, 'drinks'),
          field('limit-weekly', 'Per 7 days', _weekly, 'drinks'),
          field('limit-days', 'Drinking days', _days, 'of 7'),
        ]),
        const SizedBox(height: Gap.sm),
        Row(children: [
          FilledButton.tonal(key: const ValueKey('limits-save'), onPressed: _save, child: const Text('Save limits')),
          const SizedBox(width: Gap.sm),
          if (_message != null) Expanded(child: Text(_message!, key: const ValueKey('limits-message'), style: text.bodySmall)),
        ]),
      ],
    );
  }
}
