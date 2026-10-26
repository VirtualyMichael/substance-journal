import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../alcohol/analytics_charts.dart';
import '../design.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// A month at a glance for one person: how much, how often, of what, and how it compares with
/// the month before. Only this person's doses are counted.
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  DateTime? _month; // first of the shown month; null means this month

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final month = _month ?? DateTime(now.year, now.month);
    final isCurrent = month.year == now.year && month.month == now.month;
    final catalog = ref.watch(catalogProvider);
    final rows = ref.watch(personIngestionsProvider(widget.person.id)).value ?? const <Ingestion>[];
    final summary = monthSummary(
      [for (final i in rows) UsageEntry(substanceKey: i.substanceKey, time: i.time, dose: i.dose, unit: i.unit)],
      month.year,
      month.month,
    );
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    String delta(int n) => n == 0 ? 'same as last month' : '${n > 0 ? '+' : ''}$n vs last month';

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            Row(children: [
              IconButton(
                key: const ValueKey('insights-prev'),
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _month = DateTime(month.year, month.month - 1)),
              ),
              Expanded(
                child: Text('${_months[month.month - 1]} ${month.year}', key: const ValueKey('insights-month'), textAlign: TextAlign.center, style: text.titleLarge),
              ),
              IconButton(
                key: const ValueKey('insights-next'),
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: isCurrent ? null : () => setState(() => _month = DateTime(month.year, month.month + 1)),
              ),
            ]),
            const SizedBox(height: Gap.sm),
            if (summary.doses == 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Text(
                    summary.previousDoses > 0 ? 'Nothing logged this month (${summary.previousDoses} the month before).' : 'Nothing logged this month.',
                    key: const ValueKey('insights-empty'),
                  ),
                ),
              )
            else ...[
              Row(children: [
                Expanded(child: _Stat(label: 'Doses', value: '${summary.doses}', note: delta(summary.change), statKey: 'stat-doses')),
                const SizedBox(width: Gap.sm),
                Expanded(child: _Stat(label: 'Days with use', value: '${summary.daysWithUse} of ${summary.daysInMonth}', note: delta(summary.dayChange), statKey: 'stat-days')),
              ]),
              const SizedBox(height: Gap.sm),
              Row(children: [
                Expanded(child: _Stat(label: 'Substances', value: '${summary.bySubstance.length}', note: summary.bySubstance.isEmpty ? '' : (catalog.byKey[summary.bySubstance.first.key]?.name ?? summary.bySubstance.first.key), statKey: 'stat-substances')),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: _Stat(
                    label: 'Busiest day',
                    value: summary.busiestWeekday == null ? '-' : _weekdays[summary.busiestWeekday!],
                    note: summary.busiestWeekday == null ? '' : '${summary.weekdayDoses[summary.busiestWeekday!]} doses',
                    statKey: 'stat-weekday',
                  ),
                ),
              ]),
              const SizedBox(height: Gap.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Doses per day', style: text.titleMedium),
                      const SizedBox(height: Gap.sm),
                      DailyBarsChart(
                        key: const ValueKey('insights-bars'),
                        days: [for (var d = 0; d < summary.daysInMonth; d++) (DateTime(month.year, month.month, d + 1), summary.perDay[d].toDouble())],
                        today: now,
                        height: 180,
                        color: scheme.primary,
                        noun: 'Doses',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Text('By substance', style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              for (final u in summary.bySubstance)
                Card(
                  key: ValueKey('insights-${u.key}'),
                  margin: const EdgeInsets.only(bottom: Gap.sm),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: substanceColor(u.key),
                      radius: 14,
                      child: Text((catalog.byKey[u.key]?.name ?? '?').characters.first, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    title: Text(catalog.byKey[u.key]?.name ?? u.key),
                    subtitle: Text([
                      '${u.doses} ${u.doses == 1 ? 'dose' : 'doses'} on ${u.days} ${u.days == 1 ? 'day' : 'days'}',
                      if (u.totalDose != null) 'about ${formatDose(u.totalDose, u.unit)} in total',
                      if (u.unknownDoses > 0) '${u.unknownDoses} without an amount',
                    ].join('  |  ')),
                  ),
                ),
            ],
            const SizedBox(height: Gap.md),
            Text('Counts only ${widget.person.name}\'s own use. Totals add up the amounts you logged and skip doses with none.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.note, required this.statKey});

  final String label;
  final String value;
  final String note;
  final String statKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelMedium),
            const SizedBox(height: 2),
            Text(value, key: ValueKey(statKey), style: text.headlineSmall),
            if (note.isNotEmpty) Text(note, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
