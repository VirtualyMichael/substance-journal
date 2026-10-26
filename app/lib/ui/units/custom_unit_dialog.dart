import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../design.dart';

/// Creates or edits a custom unit such as "Blue Superman pill: 1 pill = 120 mg".
///
/// Returns the saved unit, or null if cancelled. The dose is always in the route's unit
/// ([doseUnit]) so a count of units converts straight to a dose.
Future<CustomUnit?> showCustomUnitDialog(
  BuildContext context, {
  required AppDatabase db,
  required String substanceKey,
  required String substanceName,
  required String route,
  required String doseUnit,
  CustomUnit? existing,
}) {
  return showDialog<CustomUnit>(
    context: context,
    builder: (context) => _CustomUnitDialog(
      db: db,
      substanceKey: substanceKey,
      substanceName: substanceName,
      route: route,
      doseUnit: doseUnit,
      existing: existing,
    ),
  );
}

class _CustomUnitDialog extends StatefulWidget {
  const _CustomUnitDialog({
    required this.db,
    required this.substanceKey,
    required this.substanceName,
    required this.route,
    required this.doseUnit,
    this.existing,
  });

  final AppDatabase db;
  final String substanceKey;
  final String substanceName;
  final String route;
  final String doseUnit;
  final CustomUnit? existing;

  @override
  State<_CustomUnitDialog> createState() => _CustomUnitDialogState();
}

class _CustomUnitDialogState extends State<_CustomUnitDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _singular = TextEditingController(text: widget.existing?.unitSingular ?? 'pill');
  late final _plural = TextEditingController(text: widget.existing?.unitPlural ?? '');
  late final _dose = TextEditingController(
    text: widget.existing?.doseOfOneUnit == null ? '' : formatDose(widget.existing!.doseOfOneUnit, null),
  );
  late final _std = TextEditingController(
    text: widget.existing?.doseStdDev == null ? '' : formatDose(widget.existing!.doseStdDev, null),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late bool _estimate = widget.existing?.isEstimate ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _singular.dispose();
    _plural.dispose();
    _dose.dispose();
    _std.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final name = _name.text.trim();
    final singular = _singular.text.trim();
    final dose = _num(_dose.text);
    final std = _std.text.trim().isEmpty ? null : _num(_std.text);
    if (name.isEmpty) return setState(() => _error = 'Give the unit a name.');
    if (singular.isEmpty) return setState(() => _error = 'What do you call one (for example "pill")?');
    if (dose == null || dose <= 0) return setState(() => _error = 'Enter how much one ${singular.toLowerCase()} contains.');
    if (_estimate && _std.text.trim().isNotEmpty && (std == null || std < 0)) {
      return setState(() => _error = 'The uncertainty must be zero or more.');
    }
    final plural = _plural.text.trim().isEmpty ? null : _plural.text.trim();
    final CustomUnit saved;
    if (widget.existing == null) {
      saved = await widget.db.addCustomUnit(
        substanceKey: widget.substanceKey,
        route: widget.route,
        name: name,
        unitSingular: singular,
        unitPlural: plural,
        doseOfOneUnit: dose,
        doseStdDev: _estimate ? std : null,
        originalUnit: widget.doseUnit,
        isEstimate: _estimate,
        note: _note.text.trim(),
      );
    } else {
      await widget.db.updateCustomUnit(
        widget.existing!.id,
        name: name,
        unitSingular: singular,
        unitPlural: Value(plural),
        doseOfOneUnit: dose,
        doseStdDev: Value(_estimate ? std : null),
        isEstimate: _estimate,
        note: _note.text.trim(),
      );
      saved = await (widget.db.select(widget.db.customUnits)..where((t) => t.id.equals(widget.existing!.id))).getSingle();
    }
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New custom unit' : 'Edit custom unit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.substanceName}, ${widget.route}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Gap.sm),
            TextField(
              key: const ValueKey('unit-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Blue Superman'),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('unit-singular'),
                    controller: _singular,
                    decoration: const InputDecoration(labelText: 'One is a...', hintText: 'pill'),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('unit-plural'),
                    controller: _plural,
                    decoration: const InputDecoration(labelText: 'Plural (optional)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              key: const ValueKey('unit-dose'),
              controller: _dose,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'One contains', suffixText: widget.doseUnit),
            ),
            SwitchListTile(
              key: const ValueKey('unit-estimate'),
              contentPadding: EdgeInsets.zero,
              title: const Text('This amount is an estimate'),
              value: _estimate,
              onChanged: (v) => setState(() => _estimate = v),
            ),
            if (_estimate)
              TextField(
                key: const ValueKey('unit-std'),
                controller: _std,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Plus or minus (optional)', suffixText: widget.doseUnit),
              ),
            const SizedBox(height: Gap.sm),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(_error!, key: const ValueKey('unit-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('unit-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
