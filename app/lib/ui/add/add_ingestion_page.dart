import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../compounds/compound_picker.dart';
import '../design.dart';
import 'dose_widgets.dart';

enum AddStep { compound, route, warnings, dose, when }

/// Step-by-step logging: compound, route, interaction check, dose, time.
///
/// Pops with the id of the experience the ingestion was saved into.
class AddIngestionPage extends ConsumerStatefulWidget {
  const AddIngestionPage({super.key, required this.personId, this.experienceId, this.initialSubstanceKey});

  final String personId;

  /// Add to this experience instead of choosing one.
  final String? experienceId;

  /// Skip the compound step (e.g. when launched from a compound's page).
  final String? initialSubstanceKey;

  @override
  ConsumerState<AddIngestionPage> createState() => _AddIngestionPageState();
}

class _AddIngestionPageState extends ConsumerState<AddIngestionPage> {
  AddStep _step = AddStep.compound;
  Substance? _substance;
  RouteOfAdministration? _roa;
  bool _acknowledged = false;
  DoseInput _dose = const DoseInput.empty();
  late DateTime _time;
  DateTime? _endTime;
  String? _experienceChoice; // null = new experience
  bool _experienceChosenByUser = false;
  String? _stomach;
  final _notes = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _time = ref.read(clockProvider)();
    _experienceChoice = widget.experienceId;
    _experienceChosenByUser = widget.experienceId != null;
    final key = widget.initialSubstanceKey;
    if (key != null) {
      final s = ref.read(catalogProvider).byKey[key];
      if (s != null) WidgetsBinding.instance.addPostFrameCallback((_) => _chooseSubstance(s));
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // ---- derived data ----

  List<Substance> _activeSubstances() {
    final reference = ref.read(catalogProvider);
    final now = ref.read(clockProvider)();
    final rows = ref.read(personIngestionsProvider(widget.personId)).value ?? const <Ingestion>[];
    final keys = <String>{
      for (final i in rows)
        if (!i.time.isBefore(now.subtract(const Duration(hours: 24)))) i.substanceKey,
    };
    return [for (final k in keys) if (reference.byKey[k] != null) reference.byKey[k]!];
  }

  List<InteractionWarning> _warnings() {
    final s = _substance;
    if (s == null) return const [];
    return checkInteractions(
      incoming: s,
      active: _activeSubstances(),
      pairs: ref.read(interactionPairsProvider),
    );
  }

  // ---- navigation ----

  void _chooseSubstance(Substance s) {
    setState(() {
      _substance = s;
      _roa = s.roas.length == 1 ? s.roas.first : null;
      _acknowledged = false;
      _dose = const DoseInput.empty();
      _error = null;
      _step = _roa == null ? AddStep.route : _afterRoute();
    });
  }

  AddStep _afterRoute() => _warnings().isEmpty ? AddStep.dose : AddStep.warnings;

  void _chooseRoute(RouteOfAdministration roa) {
    setState(() {
      _roa = roa;
      _acknowledged = false;
      _dose = const DoseInput.empty();
      _step = _afterRoute();
    });
  }

  void _back() {
    setState(() {
      _error = null;
      switch (_step) {
        case AddStep.compound:
          Navigator.of(context).maybePop();
        case AddStep.route:
          _step = AddStep.compound;
        case AddStep.warnings:
          _step = (_substance?.roas.length ?? 0) > 1 ? AddStep.route : AddStep.compound;
        case AddStep.dose:
          _step = _warnings().isEmpty
              ? ((_substance?.roas.length ?? 0) > 1 ? AddStep.route : AddStep.compound)
              : AddStep.warnings;
        case AddStep.when:
          _step = AddStep.dose;
      }
    });
  }

  void _toWhen() {
    final error = _dose.validate(_roa!);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _step = AddStep.when;
    });
  }

  Future<void> _save() async {
    final roa = _roa!;
    final substance = _substance!;
    if (_endTime != null && _endTime!.isBefore(_time)) {
      setState(() => _error = 'The end time is before the start time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = ref.read(databaseProvider);
    try {
      Experience experience;
      if (_experienceChoice == null) {
        experience = await db.addExperience(personId: widget.personId, sortDate: _time);
      } else {
        experience = await (db.select(db.experiences)..where((t) => t.id.equals(_experienceChoice!))).getSingle();
        if (_time.isBefore(experience.sortDate)) {
          await db.updateExperience(experience.id, sortDate: _time);
        }
      }
      final values = _dose.toStorage(roa);
      await db.addIngestion(
        experience: experience,
        substanceKey: substance.key,
        route: roa.route,
        time: _time,
        endTime: _endTime,
        dose: values.dose,
        unit: values.unit,
        doseIsEstimate: values.isEstimate,
        doseStdDev: values.stdDev,
        stomachFullness: roa.route == 'oral' ? _stomach : null,
        absorbedMg: values.absorbedMg,
        method: values.method,
        notes: _notes.text.trim(),
        details: values.details,
        customUnitId: values.customUnitId,
      );
      if (mounted) Navigator.of(context).pop(experience.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  // ---- build ----

  String get _title => switch (_step) {
        AddStep.compound => 'Choose a compound',
        AddStep.route => 'Route of administration',
        AddStep.warnings => 'Combinations',
        AddStep.dose => _substance == null ? 'Dose' : '${_substance!.name} dose',
        AddStep.when => 'When',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(_title),
        actions: [
          if (_substance != null && _step != AddStep.compound)
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Chip(
                avatar: CircleAvatar(backgroundColor: substanceColor(_substance!.key), radius: 6),
                label: Text(_substance!.name),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(key: ValueKey(_step), child: _buildStep(context)),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case AddStep.compound:
        return CompoundPicker(personId: widget.personId, onSelected: _chooseSubstance, autofocusSearch: false);
      case AddStep.route:
        return _routeStep();
      case AddStep.warnings:
        return _warningsStep();
      case AddStep.dose:
        return _doseStep();
      case AddStep.when:
        return _whenStep();
    }
  }

  Widget _routeStep() {
    final s = _substance!;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        for (final roa in s.roas)
          Card(
            margin: const EdgeInsets.only(bottom: Gap.sm),
            child: ListTile(
              key: ValueKey('route-${roa.route}'),
              title: Text(titleCase(roa.route)),
              subtitle: Text(describeRoute(roa)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _chooseRoute(roa),
            ),
          ),
      ],
    );
  }

  Widget _warningsStep() {
    final warnings = _warnings();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                'You have used something in the last 24 hours that interacts with ${_substance!.name}.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: Gap.md),
              for (final w in warnings)
                Card(
                  margin: const EdgeInsets.only(bottom: Gap.sm),
                  color: severityContainer(scheme, w.severity),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(severityIcon(w.severity)),
                            const SizedBox(width: Gap.sm),
                            Text(
                              '${severityLabel(w.severity)}: ${w.incoming.name} + ${w.other.name}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.sm),
                        for (final r in w.reasons) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(r)),
                      ],
                    ),
                  ),
                ),
              CheckboxListTile(
                key: const ValueKey('acknowledge'),
                value: _acknowledged,
                onChanged: (v) => setState(() => _acknowledged = v ?? false),
                title: const Text('I have read this and want to continue'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        _bottomBar(
          label: 'Continue',
          onPressed: _acknowledged ? () => setState(() => _step = AddStep.dose) : null,
        ),
      ],
    );
  }

  Widget _doseStep() {
    final roa = _roa!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text('${titleCase(roa.route)}  |  ${describeRoute(roa)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: Gap.md),
              DoseEditor(
                substance: _substance!,
                roa: roa,
                value: _dose,
                onChanged: (v) => setState(() {
                  _dose = v;
                  _error = null;
                }),
              ),
              if (_error != null) _errorText(),
            ],
          ),
        ),
        _bottomBar(label: 'Next', onPressed: _toWhen),
      ],
    );
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Text(_error!, key: const ValueKey('error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );

  Widget _whenStep() {
    final now = ref.read(clockProvider)();
    final experiences = ref.watch(experiencesProvider(widget.personId)).value ?? const <Experience>[];
    final ingestions = ref.watch(personIngestionsProvider(widget.personId)).value ?? const <Ingestion>[];

    // Default target: the latest experience that was active in the last 12 hours.
    if (!_experienceChosenByUser && _experienceChoice == null) {
      final recent = <String>{
        for (final i in ingestions)
          if (now.difference(i.time) < const Duration(hours: 12) && !i.time.isAfter(now)) i.experienceId,
      };
      final candidate = experiences.where((e) => recent.contains(e.id)).firstOrNull;
      if (candidate != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_experienceChosenByUser) setState(() => _experienceChoice = candidate.id);
        });
      }
    }

    Widget quick(String label, Duration ago) => ActionChip(
          label: Text(label),
          onPressed: () => setState(() => _time = now.subtract(ago)),
        );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Wrap(
                spacing: Gap.sm,
                children: [
                  quick('Now', Duration.zero),
                  quick('15 min ago', const Duration(minutes: 15)),
                  quick('30 min ago', const Duration(minutes: 30)),
                  quick('1 h ago', const Duration(hours: 1)),
                  quick('2 h ago', const Duration(hours: 2)),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('pick-date'),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(formatDate(_time)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _time,
                          firstDate: DateTime(2000),
                          lastDate: now.add(const Duration(days: 1)),
                        );
                        if (picked != null) {
                          setState(() => _time = DateTime(picked.year, picked.month, picked.day, _time.hour, _time.minute));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('pick-time'),
                      icon: const Icon(Icons.schedule),
                      label: Text(formatClock(_time)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
                        if (picked != null) {
                          setState(() => _time = DateTime(_time.year, _time.month, _time.day, picked.hour, picked.minute));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              SwitchListTile(
                key: const ValueKey('has-end'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Took a while (sipped, smoked over time)'),
                subtitle: _endTime == null ? null : Text('Until ${formatClock(_endTime!)}'),
                value: _endTime != null,
                onChanged: (v) => setState(() => _endTime = v ? _time.add(const Duration(minutes: 30)) : null),
              ),
              if (_endTime != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('End ${formatClock(_endTime!)}'),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_endTime!));
                      if (picked != null) {
                        var end = DateTime(_time.year, _time.month, _time.day, picked.hour, picked.minute);
                        if (end.isBefore(_time)) end = end.add(const Duration(days: 1));
                        setState(() => _endTime = end);
                      }
                    },
                  ),
                ),
              if (_roa!.route == 'oral') ...[
                const SizedBox(height: Gap.sm),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('stomach'),
                  initialValue: _stomach,
                  decoration: const InputDecoration(labelText: 'Stomach (affects oral onset)'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Not specified')),
                    DropdownMenuItem(value: 'empty', child: Text('Empty')),
                    DropdownMenuItem(value: 'quarter', child: Text('Quarter full')),
                    DropdownMenuItem(value: 'half', child: Text('Half full')),
                    DropdownMenuItem(value: 'full', child: Text('Full')),
                    DropdownMenuItem(value: 'veryFull', child: Text('Very full')),
                  ],
                  onChanged: (v) => setState(() => _stomach = v),
                ),
              ],
              const SizedBox(height: Gap.md),
              DropdownButtonFormField<String?>(
                key: const ValueKey('experience-target'),
                initialValue: _experienceChoice,
                decoration: const InputDecoration(labelText: 'Add to'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('New experience')),
                  for (final e in experiences.take(12))
                    DropdownMenuItem(
                      value: e.id,
                      child: Text(e.title.isEmpty ? formatDateTime(e.sortDate) : '${e.title} (${formatDate(e.sortDate)})'),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _experienceChoice = v;
                  _experienceChosenByUser = true;
                }),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                key: const ValueKey('notes'),
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (_error != null) _errorText(),
            ],
          ),
        ),
        _bottomBar(label: _saving ? 'Saving...' : 'Save ingestion', onPressed: _saving ? null : _save),
      ],
    );
  }

  Widget _bottomBar({required String label, required VoidCallback? onPressed}) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(key: const ValueKey('primary-action'), onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}

String describeRoute(RouteOfAdministration roa) {
  final common = roa.doseCommon;
  final parts = <String>[];
  if (common?.min != null && common?.max != null) {
    parts.add('common ${common!.min!.toStringAsFixed(common.min! < 10 ? 1 : 0).replaceAll(RegExp(r'\.0$'), '')}'
        '-${common.max!.toStringAsFixed(common.max! < 10 ? 1 : 0).replaceAll(RegExp(r'\.0$'), '')} ${roa.unit}');
  }
  final total = roa.duration('total');
  if (total?.maxMinutes != null) {
    final hi = total!.maxMinutes!;
    parts.add(hi >= 60 ? 'lasts up to ${(hi / 60).toStringAsFixed(hi % 60 == 0 ? 0 : 1)} h' : 'lasts up to ${hi.round()} min');
  }
  return parts.isEmpty ? 'No dose reference for this route' : parts.join('  |  ');
}

Color severityContainer(ColorScheme scheme, InteractionSeverity s) => switch (s) {
      InteractionSeverity.dangerous => scheme.errorContainer,
      InteractionSeverity.unsafe => scheme.tertiaryContainer,
      _ => scheme.secondaryContainer,
    };

IconData severityIcon(InteractionSeverity s) => switch (s) {
      InteractionSeverity.dangerous => Icons.dangerous,
      InteractionSeverity.unsafe => Icons.warning_amber,
      _ => Icons.info_outline,
    };

String severityLabel(InteractionSeverity s) => switch (s) {
      InteractionSeverity.dangerous => 'Dangerous',
      InteractionSeverity.unsafe => 'Unsafe',
      InteractionSeverity.caution => 'Caution',
      InteractionSeverity.lowRisk => 'Low risk',
    };
