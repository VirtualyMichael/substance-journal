import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../timeline/timeline_data.dart';

/// Edit an ingestion: when, how much, the compound and the route.
///
/// Cannabis keeps its compound and route: its dose comes from a product and method calculator,
/// so changing either means deleting the ingestion and logging it again.
class EditIngestionDialog extends ConsumerStatefulWidget {
  const EditIngestionDialog({super.key, required this.ingestion});

  final Ingestion ingestion;

  @override
  ConsumerState<EditIngestionDialog> createState() => _EditIngestionDialogState();
}

class _EditIngestionDialogState extends ConsumerState<EditIngestionDialog> {
  late String _substanceKey = widget.ingestion.substanceKey;
  late String _route = widget.ingestion.route;
  late DateTime _time = widget.ingestion.time;
  late final TextEditingController _dose = TextEditingController(
    text: widget.ingestion.dose == null ? '' : formatDose(widget.ingestion.dose, null),
  );
  late final TextEditingController _notes = TextEditingController(text: widget.ingestion.notes);
  late int? _color = ((jsonDecode(widget.ingestion.detailsJson) as Map<String, dynamic>)['color'] as num?)?.toInt();
  late final Map<String, dynamic> _details = jsonDecode(widget.ingestion.detailsJson) as Map<String, dynamic>;
  late final TextEditingController _unitCount = TextEditingController(
    text: _details['unitCount'] == null ? '' : formatDose((_details['unitCount'] as num).toDouble(), null),
  );
  late final DrinkDetails _drink = DrinkDetails.of(widget.ingestion);
  late final TextEditingController _volume = TextEditingController(
    text: _drink.hasVolume ? formatDose(_drink.volume, null) : formatDose(_ozFromGrams(widget.ingestion.dose), null),
  );
  late final TextEditingController _abv = TextEditingController(text: _drink.hasVolume ? formatDose(_drink.abv, null) : '40');
  late String _volumeUnit = _drink.hasVolume ? _drink.volumeUnit! : 'oz';
  String? _error;

  /// A drink with no recorded volume is shown as fl oz of 40% spirit, which is the same grams.
  static double? _ozFromGrams(double? grams) => grams == null ? null : grams / (0.4 * alcoholDensityGramsPerFlOz);

  /// An alcohol drink is edited as volume and strength, not grams of ethanol.
  bool get _isDrink => widget.ingestion.substanceKey == 'alcohol' && !_changedWhat;

  bool get _isCannabis => widget.ingestion.substanceKey == 'cannabis';
  bool get _changedWhat => _substanceKey != widget.ingestion.substanceKey || _route != widget.ingestion.route;

  /// Still tied to a custom unit ("2 pills") and the compound and route have not changed.
  bool get _usesUnit => widget.ingestion.customUnitId != null && _details['dosePerUnit'] != null && !_changedWhat;

  @override
  void dispose() {
    _dose.dispose();
    _volume.dispose();
    _abv.dispose();
    _notes.dispose();
    _unitCount.dispose();
    super.dispose();
  }

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final catalog = ref.read(catalogProvider);
    final substance = catalog.byKey[_substanceKey];
    final roa = substance?.route(_route);
    if (substance == null || roa == null) return setState(() => _error = 'Choose a compound and route.');

    double? dose;
    var detailsJson = widget.ingestion.detailsJson;
    Value<String?> customUnitId = const Value.absent();

    if (_isDrink) {
      final volume = _num(_volume.text);
      final abv = _num(_abv.text);
      if (volume == null || volume <= 0) return setState(() => _error = 'Enter the volume.');
      if (abv == null || abv <= 0 || abv > 100) return setState(() => _error = 'Enter a strength between 0 and 100%.');
      dose = drinkGrams(volume, _volumeUnit, abv);
      detailsJson = jsonEncode({..._details, 'volume': volume, 'volumeUnit': _volumeUnit, 'abv': abv});
    } else if (_usesUnit) {
      final count = _num(_unitCount.text);
      if (count == null || count <= 0) return setState(() => _error = 'Enter how many.');
      dose = count * (_details['dosePerUnit'] as num).toDouble();
      detailsJson = jsonEncode({..._details, 'unitCount': count});
    } else {
      final text = _dose.text.trim();
      if (text.isNotEmpty) {
        dose = _num(text);
        if (dose == null || dose <= 0) return setState(() => _error = 'Enter a positive number, or leave blank for unknown.');
      }
      if (widget.ingestion.customUnitId != null) {
        // The dose no longer comes from a custom unit.
        customUnitId = const Value(null);
        detailsJson = '{}';
      }
    }

    final withColor = jsonDecode(detailsJson) as Map<String, dynamic>;
    _color == null ? withColor.remove('color') : withColor['color'] = _color;
    detailsJson = jsonEncode(withColor);

    await db.updateIngestion(
      widget.ingestion.id,
      time: _time,
      dose: Value(dose),
      notes: _notes.text.trim(),
      substanceKey: _changedWhat ? _substanceKey : null,
      route: _changedWhat ? _route : null,
      unit: _changedWhat ? roa.unit : null,
      customUnitId: customUnitId,
      detailsJson: detailsJson == widget.ingestion.detailsJson ? null : detailsJson,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final current = catalog.byKey[_substanceKey];
    final options = [
      for (final s in catalog.substances)
        if (s.key != 'cannabis') s,
      if (current != null && !catalog.substances.any((s) => s.key == current.key) && !_isCannabis) current,
    ];
    final routes = current?.roas ?? const [];
    final unit = current?.route(_route)?.unit ?? widget.ingestion.unit;

    return AlertDialog(
      title: const Text('Edit ingestion'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isCannabis)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Text(
                    'Cannabis keeps its compound and route. To change them, delete this and log it again.',
                    style: Theme.of(context).textTheme.bodySmall,
                    key: const ValueKey('cannabis-locked'),
                  ),
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('edit-compound'),
                  initialValue: _substanceKey,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Compound'),
                  items: [for (final s in options) DropdownMenuItem(value: s.key, child: Text(s.name))],
                  onChanged: (key) {
                    if (key == null) return;
                    final next = catalog.byKey[key];
                    setState(() {
                      _substanceKey = key;
                      _route = (next?.route(_route) ?? next?.roas.firstOrNull)?.route ?? _route;
                    });
                  },
                ),
                const SizedBox(height: Gap.sm),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit-route-$_substanceKey'),
                  initialValue: routes.any((r) => r.route == _route) ? _route : null,
                  decoration: const InputDecoration(labelText: 'Route'),
                  items: [for (final r in routes) DropdownMenuItem(value: r.route, child: Text(titleCase(r.route)))],
                  onChanged: (v) => setState(() => _route = v ?? _route),
                ),
                const SizedBox(height: Gap.sm),
              ],
              if (_isDrink)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('edit-volume'),
                        controller: _volume,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Volume'),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    DropdownButton<String>(
                      key: const ValueKey('edit-volume-unit'),
                      value: _volumeUnit,
                      items: const [
                        DropdownMenuItem(value: 'oz', child: Text('fl oz')),
                        DropdownMenuItem(value: 'shots', child: Text('shots')),
                        DropdownMenuItem(value: 'ml', child: Text('ml')),
                      ],
                      onChanged: (v) => setState(() => _volumeUnit = v ?? _volumeUnit),
                    ),
                    const SizedBox(width: Gap.sm),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        key: const ValueKey('edit-abv'),
                        controller: _abv,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'ABV', suffixText: '%'),
                      ),
                    ),
                  ],
                )
              else if (_usesUnit)
                TextField(
                  key: const ValueKey('edit-unit-count'),
                  controller: _unitCount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'How many ${_details['unitPlural'] ?? 'units'}'),
                )
              else
                TextField(
                  key: const ValueKey('edit-dose'),
                  controller: _dose,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Dose', suffixText: unit),
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
                          lastDate: ref.read(clockProvider)().add(const Duration(days: 1)),
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
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              const SizedBox(height: Gap.sm),
              Align(alignment: Alignment.centerLeft, child: Text('Colour on the graph', style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('dose-color-auto'),
                    label: const Text('Auto'),
                    selected: _color == null,
                    onSelected: (_) => setState(() => _color = null),
                  ),
                  for (final c in dosePalette)
                    InkWell(
                      key: ValueKey('dose-color-${c.toARGB32()}'),
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c.toARGB32()),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c.toARGB32() ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(_error!, key: const ValueKey('edit-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('edit-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
