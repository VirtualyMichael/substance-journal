import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import 'dose_widgets.dart';

/// A ready-made dose taken from the reference bands: the middle of the light, common and strong ranges.
class BuiltInPreset {
  const BuiltInPreset(this.label, this.amount);
  final String label;
  final double amount;
}

/// Two significant figures, so 1.75 g reads 1.8 g and 37.5 ug reads 38 ug.
double roundDose(double v) => double.parse(v.toStringAsPrecision(2));

double? _middle(DoseRange? r) {
  if (r == null) return null;
  final lo = r.min, hi = r.max;
  if (lo == null && hi == null) return null;
  if (lo == null || hi == null) return lo ?? hi;
  return (lo + hi) / 2;
}

/// Low, Medium and High for a route, from its published bands. Only bands the route has are offered.
/// Cannabis is left out: its bands are absorbed THC, which the cannabis calculator works out itself.
List<BuiltInPreset> builtInPresets(RouteOfAdministration roa) {
  if (roa.substanceKey == 'cannabis') return const [];
  return [
    if (_middle(roa.doseLight) case final v?) BuiltInPreset('Low', roundDose(v)),
    if (_middle(roa.doseCommon) case final v?) BuiltInPreset('Medium', roundDose(v)),
    if (_middle(roa.doseStrong) case final v?) BuiltInPreset('High', roundDose(v)),
  ];
}

String _amount(double v) => DoseInput.formatGrams(v);

/// Quick fills above the dose field: Low, Medium and High from the reference, plus presets you saved.
class DosePresetBar extends ConsumerWidget {
  const DosePresetBar({super.key, required this.substance, required this.roa, required this.value, required this.onChanged});

  final Substance substance;
  final RouteOfAdministration roa;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  DoseInput _applyBuiltIn(BuiltInPreset p) {
    final text = _amount(p.amount);
    return value.copyWith(
      text: text,
      unknown: false,
      isEstimate: false,
      stdDevText: '',
      clearUnit: true,
      mushroomForm: 'dried',
      mushroomText: text,
      presetNonce: value.presetNonce + 1,
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final estimate = substance.key == 'cannabis' ? value.cannabisEstimate(roa)?.absorbedCentralMg : null;
    final amount = estimate ?? value.dose ?? 0;
    final unit = substance.key == 'cannabis' ? 'mg' : roa.unit;
    final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(initial: '${_amount(amount)} $unit'));
    if (name == null || name.trim().isEmpty) return;
    await ref.read(databaseProvider).addDosePreset(
          substanceKey: substance.key,
          route: roa.route,
          name: name,
          amount: amount,
          unit: unit,
          input: value.toPresetJson(),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(dosePresetsProvider('${substance.key}|${roa.route}')).value ?? const <Preset>[];
    final builtIn = builtInPresets(roa);
    final canSave = !value.unknown && value.unit == null && value.validate(roa) == null;
    if (builtIn.isEmpty && saved.isEmpty && !canSave) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Presets', style: text.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: Gap.sm,
            runSpacing: 4,
            children: [
              for (final p in builtIn)
                ActionChip(
                  key: ValueKey('preset-${p.label.toLowerCase()}'),
                  label: Text('${p.label} ${_amount(p.amount)} ${roa.unit}'),
                  tooltip: 'The middle of the ${p.label.toLowerCase() == 'low' ? 'light' : p.label.toLowerCase() == 'medium' ? 'common' : 'strong'} range for this route',
                  onPressed: () => onChanged(_applyBuiltIn(p)),
                ),
              for (final p in saved)
                InputChip(
                  key: ValueKey('preset-saved-${p.id}'),
                  avatar: const Icon(Icons.bookmark_outline, size: 16),
                  label: Text(p.name),
                  onPressed: () {
                    try {
                      final input = (jsonDecode(p.detailsJson) as Map<String, dynamic>)['input'] as Map<String, dynamic>? ?? const {};
                      onChanged(value.withPreset(input));
                    } on Object {
                      // A preset written by another version: leave the form as it is.
                    }
                  },
                  onDeleted: () async {
                    final db = ref.read(databaseProvider);
                    await db.setPresetDeleted(p.id, true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${p.name} removed'),
                        action: SnackBarAction(label: 'Undo', onPressed: () => db.setPresetDeleted(p.id, false)),
                      ));
                    }
                  },
                ),
              if (canSave)
                ActionChip(
                  key: const ValueKey('save-preset'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Save as preset'),
                  onPressed: () => _save(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            builtIn.isEmpty
                ? 'Presets fill the whole dose in one tap.'
                : 'Low, Medium and High are the middle of the reference ranges. They are a starting point, not a recommendation.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Save as preset'),
        content: TextField(
          key: const ValueKey('preset-name'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('preset-save'), onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
        ],
      );
}
