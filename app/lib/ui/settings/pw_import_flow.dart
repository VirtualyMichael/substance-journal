import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pw_journal_import.dart';
import '../../providers.dart';
import '../design.dart';
import 'pw_review_page.dart';

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

  final db = ref.read(databaseProvider);
  final saved = jsonDecode(await db.getSetting('pwMappings') ?? '{}');
  if (!context.mounted) return;
  final plan = PwImportPlan(export, ref.read(catalogProvider), saved: saved is Map<String, dynamic> ? saved : const {});
  final confirmed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PwReviewPage(plan: plan)));
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
    result = await importPwJournal(db, export, ref.read(catalogProvider), plan: plan);
    await db.setSetting('pwMappings', jsonEncode(plan.toSaved()));
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

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final PwImportResult result;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      '${result.experiencesImported} experiences imported (${result.ingestions} ingestions, ${result.notes} notes, ${result.ratings} ratings).',
      if (result.experiencesCreated != result.experiencesImported) 'Doses close together were combined into ${result.experiencesCreated} experiences.',
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
