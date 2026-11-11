import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';
import '../../data/history_stats.dart';
import '../../providers.dart';
import '../charts/interactive_line_chart.dart';
import '../design.dart';

/// The session's alcohol figures at a glance, as in Alcohol Tracker. While the session is still
/// working: standard drinks, active now, BAC now, the estimated peak, when it is near zero and the
/// tolerance multiplier now. Afterwards: standard drinks, the peak, when it reached near zero and
/// tolerance before and after. All estimates.
class AlcoholSessionTiles extends ConsumerWidget {
  const AlcoholSessionTiles({super.key, required this.personId, required this.sessionDrinks});

  final String personId;

  /// This experience's drinks.
  final List<Ingestion> sessionDrinks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final settings = ref.watch(estimateSettingsProvider(personId)).value ?? const EstimateSettings();
    final all = ref.watch(personIngestionsProvider(personId)).value ?? const <Ingestion>[];
    final drinks = [for (final d in sessionDrinks) if (!d.deleted) d]..sort((a, b) => a.time.compareTo(b.time));
    if (drinks.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final start = drinks.first.time;
    final end = drinks.last.endTime ?? drinks.last.time;
    final std = drinks.fold<double>(0, (a, d) => a + standardDrinksOf(d, settings));
    final session = [for (final d in drinks) alcoholDrinkFrom(d, settings)];
    final exposure = sessionExposure(session, settings);

    // Everything still in play now: this session plus anything drunk in the 36 hours before now.
    final allDrinks = [for (final i in all) if (i.substanceKey == 'alcohol' && !i.deleted) i];
    final recent = [
      for (final d in allDrinks)
        if (now.difference(d.time) < const Duration(hours: 36) && !d.time.isAfter(now)) alcoholDrinkFrom(d, settings),
    ];
    final activeNow = estimateActiveStandardDrinks(recent, now, settings);
    final inBody = estimateAlcoholInBody(recent, now, settings);
    final live = !start.isAfter(now) && now.difference(end) < const Duration(hours: 36) && (inBody > 0.005 || activeNow > 0.001);

    DateTime? clearOf(List<AlcoholIngestion> list, DateTime anchor) =>
        estimatedClearTime(effectSeries(list, anchor, settings)) ?? estimatedClearTime(effectSeries(list, anchor, settings, null, anchor.add(const Duration(days: 3))));
    final clear = live ? clearOf(recent, now) : clearOf(session, start);

    final loads = alcoholLoads(allDrinks, settings);
    double scoreAt(DateTime t, {bool before = false}) =>
        alcoholToleranceScoreAt({for (final e in loads.entries) if (before ? e.key.isBefore(t) : !e.key.isAfter(t)) e.key: e.value}, t, settings);
    final multNow = toleranceMultiplier(scoreAt(now), settings);
    final multBefore = toleranceMultiplier(scoreAt(start, before: true), settings);
    final multAfter = toleranceMultiplier(scoreAt(end), settings);

    String clock(DateTime t) => '${formatClock(t)}${t.day != now.day || t.month != now.month ? ', ${chartDate(t)}' : ''}';
    final tiles = <(String, String, String)>[
      ('std', std.toStringAsFixed(2), 'standard drinks'),
      if (live) ('active', activeNow.toStringAsFixed(2), 'active now'),
      if (live) ('bac', '${estimateBac(activeNow, settings).toStringAsFixed(3)}%', 'est. BAC %'),
      ('peak', '${exposure.peakBac.toStringAsFixed(3)}%', exposure.peakAt == null ? 'estimated peak' : 'estimated peak, ${clock(exposure.peakAt!)}'),
      ('clear', clear == null ? 'later' : formatClock(clear), live ? 'near zero' : 'reached near zero'),
      if (live) ('tolerance', '${multNow.toStringAsFixed(2)}x', 'tolerance now') else ('tolerance', '${multBefore.toStringAsFixed(2)}x → ${multAfter.toStringAsFixed(2)}x', 'tolerance before → after'),
    ];

    return Card(
      key: const ValueKey('alcohol-tiles'),
      margin: const EdgeInsets.only(top: Gap.sm),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alcohol${live ? ' now' : ' this session'}', style: text.titleMedium),
            Text(
              '${drinks.length} ${drinks.length == 1 ? 'drink' : 'drinks'}. Estimates use ${settings.absorptionLagMinutes.toStringAsFixed(0)} min absorption and '
              '${settings.eliminationStandardDrinksPerHour.toStringAsFixed(2)} standard drinks/hr elimination.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            LayoutBuilder(builder: (context, box) {
              final columns = box.maxWidth >= 720 ? 6 : 3;
              final w = (box.maxWidth - (columns - 1) * Gap.sm) / columns;
              return Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final (key, value, label) in tiles)
                    Container(
                      key: ValueKey('alcohol-tile-$key'),
                      width: w,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: text.titleLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700))),
                        Text(label, style: text.bodySmall, maxLines: 2),
                      ]),
                    ),
                ],
              );
            }),
            const SizedBox(height: 4),
            Text('Tolerance does not lower BAC or impairment. "Near zero" is an estimate, never a sign that it is safe to drive.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
