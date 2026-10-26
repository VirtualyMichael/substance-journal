import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';
import '../design.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Adds a drink by hand, or edits [existing]. Returns the logged drink when one was added.
Future<LoggedDrink?> showDrinkDialog(
  BuildContext context, {
  required AppDatabase db,
  required String personId,
  required DateTime now,
  required EstimateSettings settings,
  Ingestion? existing,
}) {
  return showDialog<LoggedDrink>(
    context: context,
    builder: (_) => _DrinkDialog(db: db, personId: personId, now: now, settings: settings, existing: existing),
  );
}

class _DrinkDialog extends StatefulWidget {
  const _DrinkDialog({required this.db, required this.personId, required this.now, required this.settings, this.existing});

  final AppDatabase db;
  final String personId;
  final DateTime now;
  final EstimateSettings settings;
  final Ingestion? existing;

  @override
  State<_DrinkDialog> createState() => _DrinkDialogState();
}

class _DrinkDialogState extends State<_DrinkDialog> {
  late final DrinkDetails _details = widget.existing == null ? const DrinkDetails() : DrinkDetails.of(widget.existing!);
  late final _name = TextEditingController(text: _details.name);
  late final _volume = TextEditingController(text: _details.volume == null ? '' : _plain(_details.volume!));
  late final _abv = TextEditingController(text: _details.abv == null ? '' : _plain(_details.abv!));
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final _took = TextEditingController(text: _initialDuration());
  late String _unit = _details.volumeUnit ?? 'oz';
  late DateTime _time = widget.existing?.time ?? widget.now;
  String? _error;

  String _initialDuration() {
    final e = widget.existing;
    if (e?.endTime == null) return '';
    return e!.endTime!.difference(e.time).inMinutes.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _volume.dispose();
    _abv.dispose();
    _notes.dispose();
    _took.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final volume = _num(_volume.text);
    final abv = _num(_abv.text);
    final took = _took.text.trim().isEmpty ? 0.0 : _num(_took.text);
    if (volume == null || volume <= 0) return setState(() => _error = 'Enter the volume.');
    if (abv == null || abv <= 0 || abv > 100) return setState(() => _error = 'ABV must be between 0 and 100%.');
    if (took == null || took < 0 || took > 600) return setState(() => _error = 'How long it took must be 0 to 600 minutes.');

    final existing = widget.existing;
    if (existing == null) {
      final logged = await widget.db.logDrink(
        personId: widget.personId,
        at: _time,
        volume: volume,
        volumeUnit: _unit,
        abvPercent: abv,
        name: _name.text.trim(),
        durationMinutes: took,
        notes: _notes.text.trim(),
        shotOz: widget.settings.standardDrinkVolumeOz,
      );
      if (mounted) Navigator.of(context).pop(logged);
      return;
    }
    await widget.db.updateIngestion(
      existing.id,
      time: _time,
      endTime: Value(took > 0 ? _time.add(Duration(minutes: took.round())) : null),
      dose: Value(drinkGrams(volume, _unit, abv, shotOz: widget.settings.standardDrinkVolumeOz)),
      notes: _notes.text.trim(),
      detailsJson: jsonEncode({'drink': _name.text.trim(), 'volume': volume, 'volumeUnit': _unit, 'abv': abv}),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final grams = (_num(_volume.text) != null && _num(_abv.text) != null && _num(_volume.text)! > 0 && _num(_abv.text)! > 0)
        ? drinkGrams(_num(_volume.text)!, _unit, _num(_abv.text)!, shotOz: widget.settings.standardDrinkVolumeOz)
        : null;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a drink' : 'Edit drink'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('drink-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'e.g. IPA'),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('drink-volume'),
                      controller: _volume,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Volume'),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  SegmentedButton<String>(
                    key: const ValueKey('drink-unit'),
                    segments: [for (final u in drinkVolumeUnits) ButtonSegment(value: u, label: Text(u))],
                    selected: {_unit},
                    onSelectionChanged: (s) => setState(() => _unit = s.first),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                key: const ValueKey('drink-abv'),
                controller: _abv,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ABV', suffixText: '%'),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (grams != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    '${grams.toStringAsFixed(1)} g ethanol, ${standardDrinksFromGrams(grams, widget.settings).toStringAsFixed(2)} standard drinks',
                    key: const ValueKey('drink-summary'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(formatDate(_time)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _time,
                          firstDate: DateTime(2000),
                          lastDate: widget.now.add(const Duration(days: 1)),
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
              TextField(
                key: const ValueKey('drink-took'),
                controller: _took,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Took a while (optional)', suffixText: 'min'),
              ),
              const SizedBox(height: Gap.sm),
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(_error!, key: const ValueKey('drink-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('drink-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Creates or edits a drink preset.
Future<void> showPresetDialog(BuildContext context, {required AppDatabase db, Preset? existing}) {
  return showDialog<void>(context: context, builder: (_) => _PresetDialog(db: db, existing: existing));
}

class _PresetDialog extends StatefulWidget {
  const _PresetDialog({required this.db, this.existing});

  final AppDatabase db;
  final Preset? existing;

  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _volume = TextEditingController(text: widget.existing == null ? '' : _plain(widget.existing!.amount));
  late final _abv = TextEditingController(text: _initialAbv());
  late String _unit = widget.existing?.unit ?? 'oz';
  String? _error;

  String _initialAbv() {
    final e = widget.existing;
    if (e == null) return '';
    final abv = presetDrink(e).abv;
    return abv == 0 ? '' : _plain(abv);
  }

  @override
  void dispose() {
    _name.dispose();
    _volume.dispose();
    _abv.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final volume = _num(_volume.text);
    final abv = _num(_abv.text);
    if (name.isEmpty) return setState(() => _error = 'Give the drink a name.');
    if (volume == null || volume <= 0) return setState(() => _error = 'Enter the volume.');
    if (abv == null || abv <= 0 || abv > 100) return setState(() => _error = 'ABV must be between 0 and 100%.');
    if (widget.existing == null) {
      await widget.db.addDrinkPreset(name: name, volume: volume, volumeUnit: _unit, abvPercent: abv);
    } else {
      await widget.db.updateDrinkPreset(widget.existing!.id, name: name, volume: volume, volumeUnit: _unit, abvPercent: abv);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New drink preset' : 'Edit drink preset'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(key: const ValueKey('preset-name'), controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('preset-volume'),
                      controller: _volume,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Volume'),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  SegmentedButton<String>(
                    segments: [for (final u in drinkVolumeUnits) ButtonSegment(value: u, label: Text(u))],
                    selected: {_unit},
                    onSelectionChanged: (s) => setState(() => _unit = s.first),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                key: const ValueKey('preset-abv'),
                controller: _abv,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ABV', suffixText: '%'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(_error!, key: const ValueKey('preset-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('preset-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// A preset's drink as volume, unit and ABV.
({double volume, String unit, double abv}) presetDrink(Preset preset) {
  final json = jsonDecode(preset.detailsJson) as Map<String, dynamic>;
  return (volume: preset.amount, unit: preset.unit, abv: (json['abv'] as num?)?.toDouble() ?? 0);
}
