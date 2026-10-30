import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../timeline/timeline_chart.dart';
import '../timeline/timeline_data.dart';
import 'analytics_charts.dart';

/// Tolerance as the model sees it: a bounded dose multiplier that decays after drinking.
class ToleranceSummary {
  const ToleranceSummary({required this.series, required this.multiplierNow, required this.baselineBy});

  /// Multiplier per day, from six weeks back until it has decayed.
  final List<(DateTime, double)> series;
  final double multiplierNow;

  /// First day the multiplier is back to within 2% of baseline, if it is currently above it.
  final DateTime? baselineBy;
}

/// Tolerance for ONE person from their last four months of drinking (older nights have decayed).
ToleranceSummary summarizeTolerance({
  required List<Ingestion> allDrinks,
  required EstimateSettings settings,
  required DateTime now,
}) {
  final cutoff = now.subtract(const Duration(days: 120));
  final recent = [
    for (final d in allDrinks)
      if (!d.time.isBefore(cutoff)) alcoholDrinkFrom(d, settings),
  ];
  final today = dateOnly(now);
  if (recent.isEmpty) return const ToleranceSummary(series: [], multiplierNow: 1.0, baselineBy: null);

  final loads = dailyToleranceLoad(recent, settings);
  final series = toleranceMultiplierSeries(loads, today, settings);
  var nowValue = 1.0;
  for (final (t, v) in series) {
    if (dateOnly(t) == today) nowValue = v;
  }
  DateTime? baseline;
  if (nowValue > 1.02) {
    for (final (t, v) in series) {
      if (t.isAfter(today) && v <= 1.02) {
        baseline = t;
        break;
      }
    }
  }
  return ToleranceSummary(series: series, multiplierNow: nowValue, baselineBy: baseline);
}

class AlcoholAnalyticsPage extends ConsumerStatefulWidget {
  const AlcoholAnalyticsPage({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<AlcoholAnalyticsPage> createState() => _AlcoholAnalyticsPageState();
}

class _AlcoholAnalyticsPageState extends ConsumerState<AlcoholAnalyticsPage> {
  int _days = 30;
  late DateTime _month = DateTime(ref.read(clockProvider)().year, ref.read(clockProvider)().month);

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final settings = ref.watch(estimateSettingsProvider(widget.person.id)).value ?? const EstimateSettings();
    final drinks = ref.watch(alcoholDrinksProvider(widget.person.id));
    final today = dateOnly(now);
    final text = Theme.of(context).textTheme;

    final totals = dailyStandardDrinks(drinks, settings);
    final start = DateTime(today.year, today.month, today.day - (_days - 1));
    final shown = <(DateTime, double)>[
      for (var i = 0; i < _days; i++) (DateTime(start.year, start.month, start.day + i), totals[DateTime(start.year, start.month, start.day + i)] ?? 0.0),
    ];
    final total = shown.fold<double>(0, (s, d) => s + d.$2);
    final perDay = averageStandardDrinksPerDay(totals, start, today);
    final dayCount = averageDrinkingDays(totals, start, today);
    final heaviest = shown.fold<(DateTime, double)?>(null, (best, d) => d.$2 > (best?.$2 ?? 0) ? d : best);
    final tolerance = summarizeTolerance(allDrinks: drinks, settings: settings, now: now);

    Widget stat(String label, String value, {String? key}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.labelMedium),
                  const SizedBox(height: 4),
                  Text(value, key: key == null ? null : ValueKey(key), style: text.headlineSmall),
                ],
              ),
            ),
          ),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            Wrap(
              spacing: Gap.sm,
              children: [
                for (final d in const [7, 30, 90, 365])
                  ChoiceChip(
                    key: ValueKey('range-$d'),
                    label: Text(d == 365 ? '1 year' : '$d days'),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                stat('Drinks per day', perDay.toStringAsFixed(1), key: 'avg-drinks'),
                const SizedBox(width: Gap.sm),
                stat('Drinking days / week', dayCount.toStringAsFixed(1), key: 'avg-days'),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                stat('Total standard drinks', total.toStringAsFixed(1), key: 'total-drinks'),
                const SizedBox(width: Gap.sm),
                stat('Heaviest day', heaviest == null ? 'none' : '${heaviest.$2.toStringAsFixed(1)} on ${heaviest.$1.month}/${heaviest.$1.day}', key: 'heaviest'),
              ],
            ),
            const SizedBox(height: Gap.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Standard drinks by day', style: text.titleMedium),
                    const SizedBox(height: Gap.sm),
                    DailyBarsChart(key: const ValueKey('daily-bars'), days: shown, today: today),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: MonthHeatmap(
                  month: _month,
                  totals: totals,
                  today: today,
                  onShift: (m) => setState(() => _month = DateTime(_month.year, _month.month + m)),
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tolerance', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      tolerance.series.isEmpty
                          ? 'No recent drinking, so no tolerance is modelled.'
                          : 'The dose that feels like one drink at your tolerance-free baseline is about '
                              '${tolerance.multiplierNow.toStringAsFixed(2)}x right now.',
                      key: const ValueKey('tolerance-now'),
                    ),
                    if (tolerance.baselineBy != null)
                      Text('Projected back to baseline around ${formatDate(tolerance.baselineBy!)} if you do not drink.', key: const ValueKey('tolerance-baseline'), style: text.bodySmall),
                    const SizedBox(height: Gap.sm),
                    TimelineChart(
                      key: const ValueKey('tolerance-chart'),
                      series: tolerance.series.isEmpty
                          ? const []
                          : [TimelineSeries(label: 'Tolerance', color: const Color(0xFF7A6FF0), points: tolerance.series, ingestionId: 'tol')],
                      now: now,
                      reference: null,
                      yBase: 1.0,
                      yMinimum: 1.1,
                      yLabel: (v) => '${v.toStringAsFixed(1)}x',
                      emptyText: 'No recent drinking',
                      height: 200,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
