import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import 'custom_unit_dialog.dart';
import '../toast.dart';

/// Manage custom units ("1 pill = 120 mg"): edit, archive and delete. New units are created
/// from the dose step, where the compound and route are known.
class CustomUnitsPage extends ConsumerWidget {
  const CustomUnitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(customUnitsProvider).value ?? const <CustomUnit>[];
    final catalog = ref.watch(catalogProvider);
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Custom units')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: units.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(Gap.lg),
                  child: Center(
                    child: Text(
                      'No custom units yet. While logging a dose, choose "New custom unit" '
                      'to save things like "1 pill = 120 mg".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Gap.md),
                  children: [
                    for (final u in units)
                      Card(
                        key: ValueKey('unit-${u.id}'),
                        margin: const EdgeInsets.only(bottom: Gap.sm),
                        child: ListTile(
                          leading: Icon(u.isArchived ? Icons.inventory_2_outlined : Icons.medication_outlined),
                          title: Text(u.name),
                          subtitle: Text(
                            '${catalog.byKey[u.substanceKey]?.name ?? u.substanceKey}, ${u.route}\n'
                            '1 ${u.unitSingular} = ${formatDose(u.doseOfOneUnit, u.originalUnit)}'
                            '${u.isEstimate ? ' (estimate)' : ''}${u.isArchived ? '  |  archived' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            key: ValueKey('unit-menu-${u.id}'),
                            onSelected: (v) async {
                              if (v == 'edit') {
                                await showCustomUnitDialog(
                                  context,
                                  db: db,
                                  substanceKey: u.substanceKey,
                                  substanceName: catalog.byKey[u.substanceKey]?.name ?? u.substanceKey,
                                  route: u.route,
                                  doseUnit: u.originalUnit,
                                  existing: u,
                                );
                              } else if (v == 'archive') {
                                await db.updateCustomUnit(u.id, isArchived: !u.isArchived);
                              } else if (v == 'delete') {
                                await db.setCustomUnitDeleted(u.id, true);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showToast(SnackBar(
                                    content: Text('${u.name} deleted'),
                                    action: SnackBarAction(label: 'Undo', onPressed: () => db.setCustomUnitDeleted(u.id, false)),
                                  ));
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'archive', child: Text(u.isArchived ? 'Restore' : 'Archive')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
