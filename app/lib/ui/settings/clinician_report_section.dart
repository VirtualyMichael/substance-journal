import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/clinician_report.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

/// Makes a printable PDF of one person's last weeks or months: totals, alcohol, and a session list.
class ClinicianReportSection extends ConsumerStatefulWidget {
  const ClinicianReportSection({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<ClinicianReportSection> createState() => _ClinicianReportSectionState();
}

class _ClinicianReportSectionState extends ConsumerState<ClinicianReportSection> {
  int _days = 90;
  bool _busy = false;
  String? _message;

  Future<void> _make({required bool share}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final now = ref.read(clockProvider)();
      final person = widget.person;
      final experiences = await db.watchExperiences(person.id).first;
      final ingestions = await db.ingestionsForPerson(person.id);
      final ratings = await db.watchRatingsForPerson(person.id).first;
      final settings = await db.getEstimateSettings(person.id);
      final data = buildReportData(
        person: person,
        ingestions: ingestions,
        experiences: experiences,
        ratings: ratings,
        reference: ref.read(catalogProvider),
        alcoholSettings: settings,
        from: now.subtract(Duration(days: _days - 1)),
        to: now,
        now: now,
      );
      final bytes = await buildReportPdf(data);
      final name = 'substance-summary-${person.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';
      if (share) {
        await ref.read(fileSharerProvider)(name, bytes);
        setState(() => _message = 'Ready to share.');
      } else {
        final saved = await ref.read(fileSaverProvider)(name, bytes);
        setState(() => _message = saved == null ? 'Not saved.' : 'Saved to $saved');
      }
    } on Object catch (e) {
      setState(() => _message = 'Could not make the summary: $e');
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
        Text('Summary for a clinician', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'A printable PDF of ${widget.person.name}\'s log: totals per compound, alcohol in standard drinks, and a list of sessions. '
          'It is made on this device and goes only where you save or share it.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              key: const ValueKey('report-days'),
              value: _days,
              items: const [
                DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                DropdownMenuItem(value: 90, child: Text('Last 3 months')),
                DropdownMenuItem(value: 180, child: Text('Last 6 months')),
                DropdownMenuItem(value: 365, child: Text('Last year')),
              ],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
            FilledButton.icon(
              key: const ValueKey('report-save'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Save PDF'),
              onPressed: _busy ? null : () => _make(share: false),
            ),
            OutlinedButton.icon(
              key: const ValueKey('report-share'),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
              onPressed: _busy ? null : () => _make(share: true),
            ),
          ],
        ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_message!, key: const ValueKey('report-message'), style: text.bodySmall)),
      ],
    );
  }
}
