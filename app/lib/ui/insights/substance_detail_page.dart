import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/history_stats.dart';
import '../../providers.dart';
import '../charts/interactive_line_chart.dart';
import '../design.dart';
import '../journal/experience_page.dart';
import '../journal/tolerance_card.dart' show ToleranceTrend;

/// "in 3 days (Thu Nov 13)", "today", or "now" when already there.
String whenText(DateTime? t, DateTime now) {
  if (t == null) return 'already there';
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final rel = days <= 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days');
  return '$rel (${chartDate(t)})';
}

String amountText(double v, String unit) {
  final digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} $unit'.trim();
}

/// Tolerance as a word, also for alcohol (whose multiplier is turned into the same four bands).
String toleranceBand(ToleranceView v) {
  if (!v.alcohol) return v.word;
  final m = v.multiplierNow ?? 1;
  if (m < 1.02) return 'None';
  if (m < 1.2) return 'Low';
  if (m < 1.5) return 'Moderate';
  return 'High';
}

int toleranceRank(ToleranceView v) => switch (toleranceBand(v)) { 'High' => 3, 'Moderate' => 2, 'Low' => 1, _ => 0 };

String trendWord(ToleranceTrend t) => switch (t) { ToleranceTrend.rising => 'rising', ToleranceTrend.falling => 'falling', ToleranceTrend.steady => 'steady' };

IconData trendIcon(ToleranceTrend t) => switch (t) { ToleranceTrend.rising => Icons.trending_up, ToleranceTrend.falling => Icons.trending_down, ToleranceTrend.steady => Icons.trending_flat };

/// The None/Low/Moderate/High bands behind a tolerance score chart.
List<ChartBand> scoreBands(ColorScheme scheme) => [
      ChartBand(baselineLevel, 0.5, 'Low', scheme.primary.withValues(alpha: 0.05)),
      ChartBand(0.5, 1.5, 'Moderate', scheme.tertiary.withValues(alpha: 0.07)),
      ChartBand(1.5, 100, 'High', scheme.error.withValues(alpha: 0.07)),
    ];

String formatScore(double v) => '${v.toStringAsFixed(2)} (${toleranceWord(v)})';
String formatMultiplier(double v) => '${v.toStringAsFixed(2)}x';

/// Everything about one substance in one person's journal: tolerance over time with when it halves,
/// a break planner, records, lifetime figures, the dose trend, patterns and the sessions that
/// raised tolerance most. All estimates from published ranges and the person's own log.
class SubstanceDetailPage extends ConsumerStatefulWidget {
  const SubstanceDetailPage({super.key, required this.person, required this.substanceKey});

  final Person person;
  final String substanceKey;

  @override
  ConsumerState<SubstanceDetailPage> createState() => _SubstanceDetailPageState();
}

class _SubstanceDetailPageState extends ConsumerState<SubstanceDetailPage> {
  ChartRange _range = ChartRange.month;
  bool _byGain = true;

  // Recalculated only when the journal changes or the hour turns, not on every tick or tap.
  Object? _cacheKey;
  List<SubstanceHistory> _histories = const [];

  void _open(String experienceId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperiencePage(experienceId: experienceId)));

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final catalog = ref.watch(catalogProvider);
    final rows = ref.watch(personIngestionsProvider(widget.person.id)).value ?? const <Ingestion>[];
    final settings = ref.watch(estimateSettingsProvider(widget.person.id)).value ?? const EstimateSettings();
    final substance = catalog.byKey[widget.substanceKey];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cacheKey = (rows, settings, catalog, now.day, now.hour);
    if (cacheKey != _cacheKey) {
      _cacheKey = cacheKey;
      _histories = buildHistories(ingestions: rows, byKey: catalog.byKey, settings: settings, now: now);
    }
    final h = _histories.where((x) => x.key == widget.substanceKey).firstOrNull;
    final name = substance?.name ?? widget.substanceKey;
    if (h == null) {
      return Scaffold(appBar: AppBar(title: Text(name)), body: const Center(child: Text('Nothing logged for this substance.')));
    }

    final span = _range.span ?? now.difference(h.first).abs() + const Duration(days: 2);
    final from = now.subtract(span);
    final to = now.add(Duration(days: max(7, span.inDays ~/ 3)));
    final view = substance == null || (!substance.hasTolerance && substance.key != 'alcohol')
        ? null
        : toleranceView(substance: substance, ingestions: rows, byKey: catalog.byKey, settings: settings, from: from, to: to, now: now);
    final color = substanceColor(widget.substanceKey);

    Widget section(String title, List<Widget> children, {Key? key}) => Card(
          key: key,
          margin: const EdgeInsets.only(bottom: Gap.md),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: text.titleMedium), const SizedBox(height: Gap.sm), ...children]),
          ),
        );
    Widget row(String label, String value, {VoidCallback? onTap, Key? key}) => InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(label, style: text.bodyMedium)),
              Flexible(child: Text(value, textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18),
            ]),
          ),
        );

    final gains = [...h.gains];
    if (_byGain) gains.sort((a, b) => b.added.compareTo(a.added));
    String gainText(SessionGainRow g) => g.alcohol
        ? '${formatMultiplier(g.multiplierBefore)} → ${formatMultiplier(g.multiplierAfter)}'
        : '${toleranceWord(g.before)} ${g.before.toStringAsFixed(2)} → ${toleranceWord(g.after)} ${g.after.toStringAsFixed(2)}';

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              if (view != null)
                section('Tolerance', key: const ValueKey('detail-tolerance'), [
                  Wrap(spacing: Gap.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Chip(avatar: Icon(trendIcon(view.trend), size: 16), label: Text('${view.word} now, ${trendWord(view.trend)}'), visualDensity: VisualDensity.compact),
                    if (view.sharedWith.isNotEmpty) Text('Shared with ${view.sharedWith.join(', ')}', style: text.bodySmall),
                  ]),
                  const SizedBox(height: Gap.sm),
                  RangeChips(value: _range, onChanged: (r) => setState(() => _range = r)),
                  const SizedBox(height: Gap.sm),
                  InteractiveLineChart(
                    key: const ValueKey('detail-chart'),
                    series: [ChartSeries(label: view.alcohol ? 'Dose multiplier' : 'Tolerance', color: color, points: view.points, format: view.alcohol ? formatMultiplier : formatScore)],
                    from: from,
                    to: to,
                    yMin: view.alcohol ? 1 : 0,
                    yLabel: view.alcohol ? (v) => '${v.toStringAsFixed(2)}x' : null,
                    bands: view.alcohol ? const [] : scoreBands(scheme),
                    markers: [
                      ChartMarker(now, 'Now', color: scheme.error, dotted: false),
                      if (view.plan.half != null) ChartMarker(view.plan.half!, 'Half'),
                      if (view.plan.quarter != null) ChartMarker(view.plan.quarter!, 'Quarter'),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    [
                      if (view.plan.half != null) 'Half of today\'s tolerance by ${chartDate(view.plan.half!)}',
                      if (view.plan.quarter != null) 'a quarter by ${chartDate(view.plan.quarter!)}',
                      if (view.plan.baseline != null) 'back to baseline by ${chartDate(view.plan.baseline!)}' else 'at baseline now',
                    ].join(' · '),
                    key: const ValueKey('detail-halving'),
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    view.alcohol
                        ? 'The multiplier is roughly how much more alcohol it takes to feel what a tolerance-free drinker would. Higher tolerance does not lower BAC or impairment.'
                        : 'A score from published tolerance times and your own doses (1 = one common dose recently; repeat doses in one session count less). With raised tolerance, taking more to compensate is a common way to take too much.',
                    style: text.bodySmall,
                  ),
                ]),
              if (view != null)
                section('Break planner', key: const ValueKey('detail-planner'), [
                  Text('With no more use from now:', style: text.bodySmall),
                  row('Half of now', whenText(view.plan.half, now)),
                  row('A quarter of now', whenText(view.plan.quarter, now)),
                  if (!view.alcohol) row('Down to Low', whenText(view.plan.low, now)),
                  row('Back to baseline', whenText(view.plan.baseline, now)),
                ]),
              section('Records', key: const ValueKey('detail-records'), [
                for (final e in h.largestByRoute.entries)
                  row('Largest single dose (${e.key})', '${amountText(e.value.amount, e.value.unit)} · ${chartDate(e.value.at)}', onTap: () => _open(e.value.experienceId)),
                if (h.largestSession != null)
                  row('Largest session total', '${amountText(h.largestSession!.amount, h.largestSession!.unit)} · ${chartDate(h.largestSession!.at)}', onTap: () => _open(h.largestSession!.experienceId)),
                if (h.most24h != null)
                  row('Most in any 24 hours', '${amountText(h.most24h!.amount, h.most24h!.unit)} · from ${chartDate(h.most24h!.at)}', onTap: () => _open(h.most24h!.experienceId)),
                if (h.highestPeak != null)
                  row(
                    h.key == 'alcohol' ? 'Highest estimated BAC' : 'Highest estimated intensity',
                    '${h.key == 'alcohol' ? '${h.highestPeak!.amount.toStringAsFixed(3)}%' : '${h.highestPeak!.amount.toStringAsFixed(1)}x a common dose'} · ${chartDate(h.highestPeak!.at)}',
                    onTap: () => _open(h.highestPeak!.experienceId),
                  ),
              ]),
              section('Lifetime', key: const ValueKey('detail-lifetime'), [
                row('Doses', '${h.doses} in ${h.experiences} experiences'),
                row('Days used', '${h.daysUsed}'),
                row('First and last', '${chartDate(h.first)} - ${chartDate(h.last)}'),
                for (final e in h.totalByUnit.entries) row('Total', amountText(e.value, e.key)),
                if (h.averageDose != null) row('Average dose', amountText(h.averageDose!, h.mainUnit)),
                row('Longest break', h.longestBreakFrom == null ? 'none yet' : '${h.longestBreakDays} days (from ${chartDate(h.longestBreakFrom!)})'),
                row('Current run', h.currentRunDays == 0 ? 'not used today or yesterday' : '${h.currentRunDays} ${h.currentRunDays == 1 ? 'day' : 'days'} in a row'),
              ]),
              if (h.sessionTotals.length > 1)
                section('Amount per session', key: const ValueKey('detail-trend'), [
                  InteractiveLineChart(
                    series: [ChartSeries(label: 'Session total', color: color, points: h.sessionTotals, fill: false, format: (v) => amountText(v, h.mainUnit))],
                    from: h.sessionTotals.first.$1,
                    to: h.sessionTotals.last.$1.add(const Duration(days: 1)),
                    height: 180,
                  ),
                  Text('Watch for amounts creeping up over time.', style: text.bodySmall),
                ]),
              section('Patterns', key: const ValueKey('detail-patterns'), [
                Text('Day of the week', style: text.labelLarge),
                _Bars(values: h.byWeekday, labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'], color: color),
                const SizedBox(height: Gap.sm),
                Text('Time of day', style: text.labelLarge),
                _Bars(values: h.byHour, labels: [for (var n = 0; n < 24; n++) n % 6 == 0 ? '$n' : ''], color: color),
                const SizedBox(height: Gap.sm),
                Text('Routes: ${h.routes.entries.map((e) => '${e.key} ${e.value}').join(', ')}', style: text.bodyMedium),
                if (h.combos.isNotEmpty) Text('Taken with: ${h.combos.take(6).map((e) => '${e.key} (${e.value})').join(', ')}', style: text.bodyMedium),
              ]),
              if (gains.isNotEmpty)
                section('Sessions by tolerance added', key: const ValueKey('detail-gains'), [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: true, label: Text('Biggest')), ButtonSegment(value: false, label: Text('Newest'))],
                    selected: {_byGain},
                    onSelectionChanged: (v) => setState(() => _byGain = v.first),
                  ),
                  const SizedBox(height: Gap.sm),
                  for (final g in gains.take(20))
                    row(
                      chartDate(g.start),
                      '${gainText(g)}${g.percent == null ? ' (from none)' : ' (+${g.percent!.toStringAsFixed(0)}%)'}',
                      onTap: () => _open(g.experienceId),
                      key: ValueKey('gain-${g.experienceId}'),
                    ),
                ]),
              Text('Estimates from published ranges and your own log, not measurements.', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small labelled bars, for weekday and hour patterns.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color});
  final List<int> values;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = values.fold<int>(1, max);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 70,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Tooltip(
                message: '${values[i]}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 50 * values[i] / top,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(2)),
                  ),
                  SizedBox(height: 14, child: Text(labels[i], style: text.labelSmall)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
