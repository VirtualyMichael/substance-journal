import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/csv_export.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

/// Every dose as a spreadsheet-ready CSV: for your own records, a doctor, or another tool.
class CsvExportSection extends ConsumerStatefulWidget {
  const CsvExportSection({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<CsvExportSection> createState() => _CsvExportSectionState();
}

class _CsvExportSectionState extends ConsumerState<CsvExportSection> {
  bool _busy = false;
  String? _message;

  Future<void> _export({required bool share}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final now = ref.read(clockProvider)();
      final person = widget.person;
      final csv = buildIngestionsCsv(
        ingestions: await db.ingestionsForPerson(person.id),
        experiences: await db.watchExperiences(person.id).first,
        products: await db.watchProducts('cannabis').first,
        reference: ref.read(catalogProvider),
      );
      final name = 'substance-journal-${person.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
      final bytes = csvBytes(csv);
      if (share) {
        await ref.read(fileSharerProvider)(name, bytes);
        setState(() => _message = 'Ready to share.');
      } else {
        final saved = await ref.read(fileSaverProvider)(name, bytes);
        setState(() => _message = saved == null ? 'Not saved.' : 'Saved to $saved');
      }
    } on Object catch (e) {
      setState(() => _message = 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export as CSV', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          "Every dose in ${widget.person.name}'s journal as a spreadsheet: date, time, compound, route, dose, product and notes. "
          'It is made on this device and goes only where you save or share it.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('csv-save'),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Save CSV'),
              onPressed: _busy ? null : () => _export(share: false),
            ),
            OutlinedButton.icon(
              key: const ValueKey('csv-share'),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
              onPressed: _busy ? null : () => _export(share: true),
            ),
          ],
        ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_message!, key: const ValueKey('csv-message'), style: text.bodySmall)),
      ],
    );
  }
}
