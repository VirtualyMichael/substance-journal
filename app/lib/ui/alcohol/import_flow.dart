import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alcohol_import.dart';
import '../../providers.dart';
import '../design.dart';

/// Pick (or take) an Alcohol Tracker file, show what is in it, and import it on confirmation.
Future<void> runTrackerImport(BuildContext context, WidgetRef ref, {String? path}) async {
  final pick = ref.read(trackerFilePickerProvider);
  final chosen = path ?? await pick();
  if (chosen == null || !context.mounted) return;

  final TrackerExport export;
  try {
    export = parseTrackerFile(chosen);
  } on TrackerImportException catch (e) {
    if (context.mounted) await _message(context, 'Could not import', e.message);
    return;
  } catch (e) {
    if (context.mounted) await _message(context, 'Could not import', 'Could not read that file: $e');
    return;
  }
  if (!context.mounted) return;

  if (export.drinks.isEmpty && export.presets.isEmpty) {
    await _message(
      context,
      'Nothing to import',
      export.problems.isEmpty ? 'The file has no drinks or presets.' : 'No drinks could be read. First problem: ${export.problems.first}',
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDialog(export: export),
  );
  if (confirmed != true || !context.mounted) return;

  final db = ref.read(databaseProvider);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: Gap.md), Text('Importing...')]),
    ),
  );
  TrackerImportResult? result;
  Object? failure;
  try {
    result = await importTrackerExport(db, export);
  } catch (e) {
    failure = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // progress

  if (result == null) {
    await _message(context, 'Import failed', 'Nothing was changed. $failure');
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _ResultDialog(result: result!));
}

Future<void> _message(BuildContext context, String title, String body) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body, key: const ValueKey('import-message')),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );

String _day(DateTime? t) => t == null ? '' : formatDate(t);

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.export});

  final TrackerExport export;

  @override
  Widget build(BuildContext context) {
    final others = export.consumers.where((c) => c.toLowerCase() != 'me').toList()..sort();
    final lines = <String>[
      if (export.drinks.isNotEmpty)
        '${export.drinks.length} drinks from ${_day(export.firstDrink)} to ${_day(export.lastDrink)} '
            '(${export.standardDrinks.toStringAsFixed(1)} standard drinks).',
      if (export.presets.isNotEmpty) '${export.presets.length} drink presets.',
      if (export.drinks.any((d) => d.consumer.toLowerCase() == 'me')) 'Drinks by "Me" go to your own journal.',
      if (others.isNotEmpty) 'People: ${others.join(', ')} (added if they do not exist yet).',
      'Drinks already in the journal are skipped, so importing the same file again adds nothing.',
      if (export.recipeCount > 0) '${export.recipeCount} recipes (your own and edited ones are added; unedited built-ins are skipped).',
      if (export.problems.isNotEmpty) '${export.problems.length} rows could not be read and will be skipped.',
    ];
    return AlertDialog(
      title: const Text('Import from Alcohol Tracker'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Gap.sm), child: Text(l))],
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('import-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('import-confirm'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Import')),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final TrackerImportResult result;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      '${result.imported} drinks imported in ${result.experiencesCreated} new experiences.',
      if (result.duplicatesSkipped > 0) '${result.duplicatesSkipped} already in the journal, skipped.',
      if (result.presetsAdded > 0) '${result.presetsAdded} presets added.',
      if (result.recipesAdded > 0) '${result.recipesAdded} recipes added.',
      if (result.presetsSkipped > 0) '${result.presetsSkipped} presets already existed.',
      if (result.peopleCreated.isNotEmpty) 'New people: ${result.peopleCreated.join(', ')}.',
      if (result.problems.isNotEmpty) '${result.problems.length} rows skipped. First: ${result.problems.first}',
    ];
    return AlertDialog(
      title: const Text('Import complete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Gap.sm), child: Text(l, key: const ValueKey('import-result-line')))],
      ),
      actions: [FilledButton(key: const ValueKey('import-done'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}
