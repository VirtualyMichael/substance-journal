import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../add/dose_widgets.dart';
import '../design.dart';
import 'custom_unit_dialog.dart';

/// Pick a custom unit ("1 pill = 120 mg") and say how many, or create a new one.
class CustomUnitPicker extends ConsumerWidget {
  const CustomUnitPicker({
    super.key,
    required this.substance,
    required this.roa,
    required this.units,
    required this.value,
    required this.onChanged,
  });

  final Substance substance;
  final RouteOfAdministration roa;
  final List<CustomUnit> units;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = value.unit;
    final count = value.unitCount;
    final total = value.dose;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final u in units)
              ChoiceChip(
                key: ValueKey('custom-unit-${u.id}'),
                label: Text('${u.name} (1 ${u.unitSingular} = ${formatDose(u.doseOfOneUnit, u.originalUnit)})'),
                selected: chosen?.id == u.id,
                onSelected: (selected) => onChanged(
                  selected
                      ? value.copyWith(
                          unit: CustomUnitChoice.fromRow(u),
                          unitCountText: value.unitCountText.isEmpty ? '1' : value.unitCountText,
                        )
                      : value.copyWith(clearUnit: true),
                ),
              ),
            ActionChip(
              key: const ValueKey('new-custom-unit'),
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('New custom unit'),
              onPressed: () async {
                final created = await showCustomUnitDialog(
                  context,
                  db: ref.read(databaseProvider),
                  substanceKey: substance.key,
                  substanceName: substance.name,
                  route: roa.route,
                  doseUnit: roa.unit,
                );
                if (created != null) {
                  onChanged(value.copyWith(unit: CustomUnitChoice.fromRow(created), unitCountText: '1'));
                }
              },
            ),
          ],
        ),
        if (chosen != null) ...[
          const SizedBox(height: Gap.md),
          TextFormField(
            key: const ValueKey('unit-count'),
            initialValue: value.unitCountText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'How many ${chosen.plural}?'),
            onChanged: (t) => onChanged(value.copyWith(unitCountText: t)),
          ),
          if (count != null && count > 0 && total != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                '${formatDose(count, null)} ${chosen.label(count)} = ${formatDose(total, roa.unit)}'
                '${chosen.isEstimate ? ' (estimate)' : ''}',
                key: const ValueKey('unit-total'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
        ],
        const SizedBox(height: Gap.sm),
      ],
    );
  }
}
