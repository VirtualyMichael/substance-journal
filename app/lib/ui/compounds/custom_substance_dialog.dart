import 'package:flutter/material.dart';

import '../../data/custom_substances.dart';
import '../../data/database.dart';
import '../design.dart';

/// Creates or edits a compound that has no reference data. Returns the saved compound's
/// catalog key (`custom:<id>`), or null if cancelled.
Future<String?> showCustomSubstanceDialog(
  BuildContext context, {
  required AppDatabase db,
  CustomSubstance? existing,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CustomSubstanceDialog(db: db, existing: existing),
  );
}

class _CustomSubstanceDialog extends StatefulWidget {
  const _CustomSubstanceDialog({required this.db, this.existing});

  final AppDatabase db;
  final CustomSubstance? existing;

  @override
  State<_CustomSubstanceDialog> createState() => _CustomSubstanceDialogState();
}

class _CustomSubstanceDialogState extends State<_CustomSubstanceDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _onset = TextEditingController(text: '${widget.existing?.onsetMinutes ?? 30}');
  late final _hours = TextEditingController(
    text: formatDose(widget.existing?.durationHours ?? 4.0, null),
  );
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late String _units = widget.existing?.units ?? customUnitChoices.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _onset.dispose();
    _hours.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final onset = int.tryParse(_onset.text.trim());
    final hours = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (name.isEmpty) return setState(() => _error = 'Give the compound a name.');
    if (onset == null || onset < 0) return setState(() => _error = 'Onset is a number of minutes, zero or more.');
    if (hours == null || hours <= 0 || hours > 96) return setState(() => _error = 'Duration is a number of hours up to 96.');
    if (onset >= hours * 60) return setState(() => _error = 'Onset must be shorter than the whole duration.');

    final String id;
    if (widget.existing == null) {
      id = (await widget.db.addCustomSubstance(
        name: name,
        units: _units,
        description: _description.text.trim(),
        onsetMinutes: onset,
        durationHours: hours,
      ))
          .id;
    } else {
      id = widget.existing!.id;
      await widget.db.updateCustomSubstance(
        id,
        name: name,
        units: _units,
        description: _description.text.trim(),
        onsetMinutes: onset,
        durationHours: hours,
      );
    }
    if (mounted) Navigator.of(context).pop('$customKeyPrefix$id');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a custom compound' : 'Edit custom compound'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For anything the reference data does not cover. No dose bands or interaction data exist for it, '
              'so research it independently.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.md),
            TextField(
              key: const ValueKey('custom-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: Gap.sm),
            DropdownButtonFormField<String>(
              key: const ValueKey('custom-units'),
              initialValue: _units,
              decoration: const InputDecoration(labelText: 'Dose unit'),
              items: [for (final u in customUnitChoices) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => _units = v ?? _units),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom-onset'),
                    controller: _onset,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Onset', suffixText: 'min'),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom-hours'),
                    controller: _hours,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Lasts about', suffixText: 'h'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(_error!, key: const ValueKey('custom-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('custom-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
