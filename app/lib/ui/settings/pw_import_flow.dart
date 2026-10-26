import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pw_journal_import.dart';
import '../../providers.dart';
import '../design.dart';

/// Pick a PsychonautWiki Journal export, show what is in it, and import it on confirmation.
Future<void> runPwImport(BuildContext context, WidgetRef ref, {String? path}) async {
  final pick = ref.read(pwFilePickerProvider);
  final chosen = path ?? await pick();
  if (chosen == null || !context.mounted) return;

  final PwExport export;
  try {
    export = parsePwJournalFile(chosen);
  } on PwImportException catch (e) {
    if (context.mounted) await _message(context, 'Could not import', e.message);
    return;
  } catch (e) {
    if (context.mounted) await _message(context, 'Could not import', 'Could not read that file: $e');
    return;
  }
  if (!context.mounted) return;

  if (export.experiences.isEmpty) {
    await _message(
      context,
      'Nothing to import',
      export.problems.isEmpty ? 'The file has no experiences.' : 'No experiences could be read. First problem: ${export.problems.first}',
    );
    return;
  }

  final confirmed = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(export: export));
  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: Gap.md), Text('Importing...')]),
    ),
  );
  PwImportResult? result;
  Object? failure;
  try {
    result = await importPwJournal(ref.read(databaseProvider), export, ref.read(catalogProvider));
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

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.export});

  final PwExport export;

  @override
  Widget build(BuildContext context) {
    final first = export.first;
    final last = export.last;
    final others = export.consumers.toList()..sort();
    final lines = <String>[
      '${export.experiences.length} experiences (${export.ingestionCount} ingestions, ${export.noteCount} timed notes, '
          '${export.ratingCount} ratings)'
          '${first == null ? '' : ' from ${formatDate(first)} to ${formatDate(last!)}'}.',
      if (export.customSubstances.isNotEmpty) '${export.customSubstances.length} custom substances become custom compounds.',
      if (export.customUnits.isNotEmpty) '${export.customUnits.length} custom units.',
      'Ingestions with no consumer go to your own journal.',
      if (others.isNotEmpty) 'People: ${others.join(', ')} (added if they do not exist yet).',
      'Experiences already in the journal are skipped, so importing the same file again adds nothing.',
      if (export.problems.isNotEmpty) '${export.problems.length} entries could not be read and will be skipped.',
    ];
    return AlertDialog(
      title: const Text('Import from PsychonautWiki Journal'),
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

  final PwImportResult result;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      '${result.experiencesImported} experiences imported (${result.ingestions} ingestions, ${result.notes} notes, ${result.ratings} ratings).',
      if (result.experiencesSkipped > 0) '${result.experiencesSkipped} already in the journal, skipped.',
      if (result.customCompoundsCreated.isNotEmpty) 'Custom compounds added: ${result.customCompoundsCreated.join(', ')}.',
      if (result.customUnitsCreated > 0) '${result.customUnitsCreated} custom units added.',
      if (result.peopleCreated.isNotEmpty) 'New people: ${result.peopleCreated.join(', ')}.',
      if (result.problems.isNotEmpty) '${result.problems.length} entries skipped. First: ${result.problems.first}',
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
