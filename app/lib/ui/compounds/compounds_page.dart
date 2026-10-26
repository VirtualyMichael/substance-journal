import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../add/add_ingestion_page.dart';
import '../design.dart';
import '../journal/journal_page.dart';
import 'compound_picker.dart';

/// Browse compounds; tap one for its reference page.
class CompoundsPage extends StatelessWidget {
  const CompoundsPage({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: CompoundPicker(
          personId: personId,
          onSelected: (s) => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CompoundDetailPage(substance: s, personId: personId)),
          ),
        ),
      ),
    );
  }
}

class CompoundDetailPage extends StatelessWidget {
  const CompoundDetailPage({super.key, required this.substance, required this.personId});

  final Substance substance;
  final String personId;

  String _duration(RouteOfAdministration roa, String phase) {
    final d = roa.duration(phase);
    if (d == null || (d.minMinutes == null && d.maxMinutes == null)) return '-';
    String f(double? m) {
      if (m == null) return '?';
      if (m < 1) return '${(m * 60).round()} s';
      if (m >= 90) return '${(m / 60).toStringAsFixed(m % 60 == 0 ? 0 : 1)} h';
      return '${m.round()} min';
    }

    return '${f(d.minMinutes)} - ${f(d.maxMinutes)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final interactions = [
      ('Dangerous', substance.dangerous),
      ('Unsafe', substance.unsafe),
      ('Uncertain', substance.uncertain),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(substance.name)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('log-this'),
        icon: const Icon(Icons.add),
        label: const Text('Log this'),
        onPressed: () => startAddIngestion(context, personId, substanceKey: substance.key),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
            children: [
              Text(substance.category, style: text.labelLarge),
              const SizedBox(height: Gap.sm),
              Text(substance.summary),
              if (substance.safetyNotes.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safety notes', style: text.titleSmall),
                        const SizedBox(height: Gap.sm),
                        for (final n in substance.safetyNotes)
                          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('- $n')),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              for (final roa in substance.roas)
                Card(
                  key: ValueKey('roa-${roa.route}'),
                  margin: const EdgeInsets.only(bottom: Gap.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titleCase(roa.route), style: text.titleMedium),
                        const SizedBox(height: Gap.sm),
                        Text(describeRoute(roa)),
                        const SizedBox(height: Gap.sm),
                        Wrap(
                          spacing: Gap.md,
                          runSpacing: 4,
                          children: [
                            for (final phase in const ['onset', 'comeup', 'peak', 'offset', 'total', 'afterglow'])
                              if (roa.duration(phase) != null)
                                Text('${titleCase(phase)}: ${_duration(roa, phase)}', style: text.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (substance.hasTolerance) ...[
                Text('Tolerance', style: text.titleMedium),
                Text(
                  [
                    if (substance.toleranceHalfDays != null) 'Halves in about ${substance.toleranceHalfDays!.toStringAsFixed(0)} days',
                    if (substance.toleranceZeroDays != null) 'back to baseline in about ${substance.toleranceZeroDays!.toStringAsFixed(0)} days',
                  ].join(', '),
                ),
                const SizedBox(height: Gap.md),
              ],
              Text('Combinations', style: text.titleMedium),
              for (final (label, names) in interactions)
                if (names.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$label: ${names.join(', ')}'),
                  ),
              if (substance.sources.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Text('Sources', style: text.titleMedium),
                for (final s in substance.sources) SelectableText(s, style: text.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
