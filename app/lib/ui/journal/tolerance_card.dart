import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/history_stats.dart';
import '../../data/tolerance_events.dart';
import '../../providers.dart';
import '../charts/interactive_line_chart.dart';
import '../design.dart';
import '../insights/substance_detail_page.dart' show formatMultiplier, formatScore, scoreBands;

/// The score a track had at [when], read off its day-by-day projection.
double _levelAt(ToleranceTrack track, DateTime when) {
  (DateTime, double)? best;
  for (final p in track.projection) {
    if (best == null || p.$1.difference(when).abs() < best.$1.difference(when).abs()) best = p;
  }
  return best?.$2 ?? track.level;
}

enum ToleranceTrend { rising, steady, falling }

ToleranceTrend toleranceTrend(ToleranceTrack track, DateTime now) {
  final before = _levelAt(track, now.subtract(const Duration(days: 7)));
  if (before <= 0.01) return track.level > 0.2 ? ToleranceTrend.rising : ToleranceTrend.steady;
  final change = track.level / before;
  return change > 1.1 ? ToleranceTrend.rising : (change < 0.9 ? ToleranceTrend.falling : ToleranceTrend.steady);
}

String _gap(Duration d) {
  if (d.inHours >= 47) return '${(d.inHours / 24).round()} days';
  if (d.inHours >= 2) return '${d.inHours} hours';
  return '${d.inMinutes} min';
}

/// 0 None, 1 Low, 2 Moderate, 3 High, for scores and alcohol multipliers alike.
int toleranceBandOf(ToleranceView v) {
  if (v.alcohol) {
    final m = v.multiplierNow ?? 1;
    return m < 1.02 ? 0 : (m < 1.2 ? 1 : (m < 1.5 ? 2 : 3));
  }
  return switch (v.word) { 'High' => 3, 'Moderate' => 2, 'Low' => 1, _ => 0 };
}

/// Where tolerance stands for what this session contains, as an interactive chart: drag across it
/// to read any day, see where this session sits, how much it added, and when tolerance halves from
/// the end of the session and from now. Alcohol is shown as its dose multiplier. A model from
/// published tolerance times and the person's own log, not a measurement.
class ToleranceCard extends ConsumerStatefulWidget {
  const ToleranceCard({super.key, required this.personId, required this.experience, required this.sessionIngestions});

  final String personId;
  final Experience experience;
  final List<Ingestion> sessionIngestions;

  @override
  ConsumerState<ToleranceCard> createState() => _ToleranceCardState();
}

class _ToleranceCardState extends ConsumerState<ToleranceCard> {
  /// Null: the default span, two weeks before the session until it is back to baseline.
  ChartRange? _range;

  List<Ingestion>? _cachedAll;
  EstimateSettings? _cachedSettings;
  Map<String, Substance>? _cachedCatalog;
  List<Ingestion> _cachedLive = const [];
  List<UseEvent> _cachedEvents = const [];
  Map<DateTime, double> _cachedLoads = const {};
  Map<String, List<Ingestion>> _cachedTracks = {};

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final catalog = ref.watch(catalogProvider);
    final all = ref.watch(personIngestionsProvider(widget.personId)).value ?? const <Ingestion>[];
    final settings = ref.watch(estimateSettingsProvider(widget.personId)).value ?? const EstimateSettings();
    final text = Theme.of(context).textTheme;
    final session = [for (final i in widget.sessionIngestions) if (!i.deleted) i]..sort((a, b) => a.time.compareTo(b.time));
    if (session.isEmpty) return const SizedBox.shrink();

    // One entry per track (substances sharing tolerance appear once), plus alcohol on its own model.
    final substances = <String, Substance>{};
    for (final i in session) {
      final s = catalog.byKey[i.substanceKey];
      if (s == null || (!s.hasTolerance && s.key != 'alcohol')) continue;
      substances.putIfAbsent(s.key == 'alcohol' ? 'alcohol' : toleranceTrackKey(s), () => s);
    }
    if (substances.isEmpty) return const SizedBox.shrink();

    // The clock ticks every 30 seconds but the journal does not change, so the heavy inputs are kept
    // until the journal, the settings or the catalogue actually change.
    if (!identical(_cachedAll, all) || !identical(_cachedSettings, settings) || !identical(_cachedCatalog, catalog.byKey)) {
      final live = [for (final i in all) if (!i.deleted) i];
      _cachedLive = live;
      _cachedEvents = useEventsFor(live, catalog.byKey);
      _cachedLoads = alcoholLoads([for (final i in live) if (i.substanceKey == 'alcohol') i], settings);
      _cachedTracks = {};
      _cachedAll = all;
      _cachedSettings = settings;
      _cachedCatalog = catalog.byKey;
    }
    final ctx = _Context(
      catalog: catalog.byKey,
      events: _cachedEvents,
      live: _cachedLive,
      loads: _cachedLoads,
      tracks: _cachedTracks,
      settings: settings,
      now: now,
      start: session.first.time,
    );

    return Card(
      key: const ValueKey('tolerance-card'),
      margin: const EdgeInsets.only(top: Gap.sm),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tolerance and recent use', style: text.titleMedium),
            Text('Drag across a chart to read any day. Dotted lines: half and a quarter of the tolerance at the end of this session.', style: text.bodySmall),
            const SizedBox(height: Gap.sm),
            Wrap(spacing: 6, runSpacing: 4, children: [
              ChoiceChip(
                key: const ValueKey('tolerance-range-session'),
                label: const Text('Session'),
                visualDensity: VisualDensity.compact,
                selected: _range == null,
                onSelected: (_) => setState(() => _range = null),
              ),
              for (final r in ChartRange.values)
                ChoiceChip(
                  key: ValueKey('tolerance-range-${r.name}'),
                  label: Text(r.label),
                  visualDensity: VisualDensity.compact,
                  selected: _range == r,
                  onSelected: (_) => setState(() => _range = r),
                ),
            ]),
            const SizedBox(height: Gap.sm),
            for (final entry in substances.entries) ..._track(context, ctx, entry.key, entry.value, session),
          ],
        ),
      ),
    );
  }

  List<Widget> _track(BuildContext context, _Context c, String key, Substance s, List<Ingestion> session) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alcohol = key == 'alcohol';
    bool inTrack(Ingestion i) {
      if (alcohol) return i.substanceKey == 'alcohol';
      final sub = c.catalog[i.substanceKey];
      return sub != null && i.substanceKey != 'alcohol' && toleranceTrackKey(sub) == key;
    }

    final mine = [for (final i in session) if (inTrack(i)) i];
    if (mine.isEmpty) return const [];
    final first = mine.first.time;
    final end = mine.last.endTime ?? mine.last.time;
    final names = {for (final i in mine) c.catalog[i.substanceKey]?.name ?? i.substanceKey}.toList()..sort();
    final color = substanceColor(mine.first.substanceKey);
    if (!alcohol && hasToleranceProfile(c.catalog, key)) return _profileTrack(context, c, key, mine, names, color, inTrack);

    // Before and after this session, and when it halves from its end.
    double scoreAt(DateTime t, {bool before = false}) => alcohol
        ? alcoholToleranceScoreAt({for (final e in c.loads.entries) if (before ? e.key.isBefore(t) : !e.key.isAfter(t)) e.key: e.value}, t, c.settings)
        : currentToleranceLevel([for (final e in c.events) if (before ? e.at.isBefore(t) : !e.at.isAfter(t)) e], c.catalog, key, t);
    final before = scoreAt(first, before: true);
    final after = scoreAt(end);
    final pastLoads = {for (final e in c.loads.entries) if (!e.key.isAfter(end)) e.key: e.value};
    DateTime? fromEnd(double fraction) =>
        alcohol ? alcoholTimeToScore(pastLoads, end, after * fraction, c.settings) : timeToFraction(c.events, c.catalog, key, end, fraction);
    final half = fromEnd(0.5);
    final quarter = fromEnd(0.25);
    final baselineEnd =
        alcohol ? alcoholTimeToScore(pastLoads, end, alcoholBaselineScore(c.settings), c.settings) : timeToLevel(c.events, c.catalog, key, end, baselineLevel);

    // The span to draw.
    final range = _range;
    final DateTime from;
    final DateTime to;
    if (range == null) {
      from = first.subtract(const Duration(days: 14));
      final until = [end.add(const Duration(days: 7)), ?baselineEnd, if (c.now.isAfter(end)) c.now.add(const Duration(days: 2))].reduce((a, b) => a.isAfter(b) ? a : b);
      to = until.isAfter(first.add(const Duration(days: 365))) ? first.add(const Duration(days: 365)) : until;
    } else {
      final anchor = c.now.isAfter(end) ? c.now : end;
      final span = range.span ?? anchor.difference(c.live.first.time) + const Duration(days: 2);
      from = anchor.subtract(span);
      to = anchor.add(Duration(days: max(7, span.inDays ~/ 3)));
    }
    final view = toleranceView(substance: s, ingestions: c.live, byKey: c.catalog, settings: c.settings, from: from, to: to, now: c.now);

    String fmt(double score) => alcohol ? formatMultiplier(toleranceMultiplier(score, c.settings)) : formatScore(score);
    final gainPct = before < 0.05 ? null : (after - before) / before * 100;

    // How recently and how often, before this session.
    final track = c.tracks[key] ??= [for (final i in c.live) if (inTrack(i)) i];
    final earlier = [for (final i in track) if (i.time.isBefore(c.start.subtract(const Duration(hours: 12)))) i];
    final last = earlier.isEmpty ? null : earlier.map((i) => i.time).reduce((a, b) => a.isAfter(b) ? a : b);
    final month = track.where((i) => !i.time.isBefore(c.now.subtract(const Duration(days: 30))) && !i.time.isAfter(c.now)).length;
    final week = track.where((i) => !i.time.isBefore(c.now.subtract(const Duration(days: 7))) && !i.time.isAfter(c.now)).length;
    final trend = view.trend;

    return [
      Row(children: [
        Expanded(child: Text(names.join(' / '), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
        Chip(
          key: ValueKey('tolerance-trend-$key'),
          visualDensity: VisualDensity.compact,
          avatar: Icon(switch (trend) { ToleranceTrend.rising => Icons.trending_up, ToleranceTrend.falling => Icons.trending_down, ToleranceTrend.steady => Icons.trending_flat }, size: 16),
          label: Text('${view.word} now, ${trend.name}'),
        ),
      ]),
      Text(
        [
          last == null ? 'First use in your log' : 'Before this: ${_gap(c.start.difference(last))} earlier',
          '$week in the last 7 days',
          '$month in the last 30',
        ].join('  |  '),
        key: ValueKey('tolerance-context-$key'),
        style: text.bodySmall,
      ),
      Text(
        'This session: ${fmt(before)} → ${fmt(after)}${gainPct == null ? ' (from none)' : ' (+${gainPct.toStringAsFixed(0)}%)'}',
        key: ValueKey('tolerance-gain-$key'),
        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      InteractiveLineChart(
        key: ValueKey('tolerance-chart-$key'),
        series: [ChartSeries(label: alcohol ? 'Dose multiplier' : 'Tolerance', color: color, points: view.points, format: alcohol ? formatMultiplier : formatScore)],
        from: from,
        to: to,
        height: 190,
        yMin: alcohol ? 1 : 0,
        yLabel: alcohol ? (v) => '${v.toStringAsFixed(2)}x' : null,
        bands: alcohol ? const [] : scoreBands(scheme),
        markers: [
          ChartMarker(first, 'This session', color: color, dotted: false),
          if (c.now.isAfter(end)) ChartMarker(c.now, 'Now', color: scheme.error, dotted: false),
          if (half != null) ChartMarker(half, 'Half'),
          if (quarter != null) ChartMarker(quarter, 'Quarter'),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        [
          'From the end of this session: ${half == null ? 'already at baseline' : 'half by ${chartDate(half)}'}${quarter == null ? '' : ', a quarter by ${chartDate(quarter)}'}${baselineEnd == null ? '' : ', baseline by ${chartDate(baselineEnd)}'}.',
          if (c.now.isAfter(end.add(const Duration(hours: 1))))
            'From now: ${view.plan.half == null ? 'at baseline' : 'half by ${chartDate(view.plan.half!)}'}${view.plan.baseline == null ? '' : ', baseline by ${chartDate(view.plan.baseline!)}'}.',
        ].join(' '),
        key: ValueKey('tolerance-halving-$key'),
        style: text.bodySmall,
      ),
      if (toleranceBandOf(view) >= 2)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            alcohol
                ? 'With raised tolerance, drinks can feel weaker while BAC and impairment are just as high. Drinking more to feel it is a common way to drink too much.'
                : 'With raised tolerance the same dose can feel weaker. Taking more to make up for it is a common way to take too much; waiting is the safer fix.',
            style: text.bodySmall,
          ),
        ),
      const SizedBox(height: Gap.md),
    ];
  }

  /// LSD and psilocybin mushrooms: the estimated loss of effect for a same-size dose from the
  /// published tolerance profile (see sj_core tolerance_profile.dart), with its band and sources.
  List<Widget> _profileTrack(
    BuildContext context,
    _Context c,
    String key,
    List<Ingestion> mine,
    List<String> names,
    Color color,
    bool Function(Ingestion) inTrack,
  ) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final catalog = c.catalog;
    final events = c.events;
    final profile = trackProfile(catalog, key, preferSubstance: mine.first.substanceKey)!;
    final first = mine.first.time;
    final end = mine.last.endTime ?? mine.last.time;
    EffectLoss lossAt(DateTime t, {DateTime? upTo}) => effectLossAt(events, catalog, key, t, upTo: upTo);
    final before = lossAt(first, upTo: first.subtract(const Duration(microseconds: 1)));
    final (peakAt, _) = projectedPeak(events, catalog, key, end);
    final peak = lossAt(peakAt, upTo: end);
    final now = lossAt(c.now);
    final half = timeToFraction(events, catalog, key, end, 0.5);
    DateTime? gone(ToleranceBand band) => effectRecoveredAt(events, catalog, key, end, band: band);
    final goneExpected = gone(ToleranceBand.expected);
    final goneEarliest = gone(ToleranceBand.low);
    final goneLatest = gone(ToleranceBand.high);

    // The span to draw.
    final range = _range;
    final DateTime from;
    final DateTime to;
    if (range == null) {
      from = first.subtract(const Duration(days: 7));
      final until = [end.add(const Duration(days: 7)), ?goneLatest?.add(const Duration(days: 1)), if (c.now.isAfter(end)) c.now.add(const Duration(days: 2))]
          .reduce((a, b) => a.isAfter(b) ? a : b);
      to = until;
    } else {
      final anchor = c.now.isAfter(end) ? c.now : end;
      final span = range.span ?? anchor.difference(c.live.first.time) + const Duration(days: 2);
      from = anchor.subtract(span);
      to = anchor.add(Duration(days: max(7, span.inDays ~/ 3)));
    }
    final step = Duration(minutes: max(60, to.difference(from).inMinutes ~/ 240));
    final line = effectLossTimeline(events, catalog, key, from, to, step: step);
    List<(DateTime, double)> pick(double Function(EffectLoss) f) => [for (final (t, l) in line) (t, f(l) * 100)];
    String pct(double v) => '${v.round()}%';

    final track = c.tracks[key] ??= [for (final i in c.live) if (inTrack(i)) i];
    final earlier = [for (final i in track) if (i.time.isBefore(c.start.subtract(const Duration(hours: 12)))) i];
    final last = earlier.isEmpty ? null : earlier.map((i) => i.time).reduce((a, b) => a.isAfter(b) ? a : b);
    final month = track.where((i) => !i.time.isBefore(c.now.subtract(const Duration(days: 30))) && !i.time.isAfter(c.now)).length;
    final week = track.where((i) => !i.time.isBefore(c.now.subtract(const Duration(days: 7))) && !i.time.isAfter(c.now)).length;
    final uncounted = uncountedInProfile(events, catalog, key);
    final noticeable = now.expected >= baselineEffectLoss;

    return [
      Row(children: [
        Expanded(child: Text(names.join(' / '), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
        Chip(
          key: ValueKey('tolerance-trend-$key'),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.percent, size: 16),
          label: Text(noticeable ? 'About ${now.percent}% weaker now (est.)' : 'No tolerance now (est.)'),
        ),
      ]),
      Text(
        [
          last == null ? 'First use in your log' : 'Before this: ${_gap(c.start.difference(last))} earlier',
          '$week in the last 7 days',
          '$month in the last 30',
        ].join('  |  '),
        key: ValueKey('tolerance-context-$key'),
        style: text.bodySmall,
      ),
      Text(
        'This session: ${before.percent}% → ${peak.percent}% weaker for a same-size dose at its peak '
        '(range ${peak.lowPercent}-${peak.highPercent}%)',
        key: ValueKey('tolerance-gain-$key'),
        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      InteractiveLineChart(
        key: ValueKey('tolerance-chart-$key'),
        series: [
          ChartSeries(label: 'Estimate', color: color, points: pick((l) => l.expected), format: pct),
          ChartSeries(label: 'High end', color: color.withValues(alpha: 0.45), points: pick((l) => l.high), fill: false, format: pct),
          ChartSeries(label: 'Low end', color: color.withValues(alpha: 0.45), points: pick((l) => l.low), fill: false, format: pct),
        ],
        from: from,
        to: to,
        height: 190,
        yMin: 0,
        yMax: 100,
        yLabel: (v) => '${v.round()}%',
        markers: [
          ChartMarker(first, 'This session', color: color, dotted: false),
          if (c.now.isAfter(end)) ChartMarker(c.now, 'Now', color: scheme.error, dotted: false),
          ChartMarker(peakAt, 'Peak'),
          if (goneExpected != null) ChartMarker(goneExpected, 'Gone (est.)'),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'After the last dose of this session (${chartDate(end)}): largest around ${chartDate(peakAt)} (about ${peak.percent}%)'
        '${half == null ? '' : ', half by ${chartDate(half)}'}'
        '${goneExpected == null ? '' : ', gone by about ${chartDate(goneExpected)}'}'
        '${goneEarliest == null || goneLatest == null ? '' : ' (between ${chartDate(goneEarliest)} and ${chartDate(goneLatest)})'}.',
        key: ValueKey('tolerance-halving-$key'),
        style: text.bodySmall,
      ),
      const SizedBox(height: 4),
      Text(
        'What this shows: how much weaker the same dose would feel, as a percent, with the shaded estimate between a low and a high end. '
        '${profile.summary}',
        key: ValueKey('tolerance-explain-$key'),
        style: text.bodySmall,
      ),
      Text(profile.limits, style: text.bodySmall),
      const SizedBox(height: 4),
      Text(
        'No "dose to feel like normal" is given: in the studies, even 2 to 4 times the dose did not bring the full effect back during daily use, '
        'and a bigger dose adds risk without a reliable return. Waiting is what lowers tolerance.',
        key: ValueKey('tolerance-no-compensation-$key'),
        style: text.bodySmall,
      ),
      if (uncounted.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Not counted: ${(uncounted.toList()..sort()).join(', ')}. They share this group in the reference data, but no published cross-tolerance figure was found.',
            style: text.bodySmall,
          ),
        ),
      ExpansionTile(
        key: ValueKey('tolerance-sources-$key'),
        tilePadding: EdgeInsets.zero,
        title: Text('Sources and assumptions', style: text.labelLarge),
        childrenPadding: const EdgeInsets.only(bottom: Gap.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, v) in [
            ('Starts', profile.riseStartHours),
            ('Largest', profile.peakHours),
            ('One dose', profile.singleDoseLoss),
            ('Most measured', profile.maxLoss),
            ('Gone after', profile.recoveryDays),
            ('Dose size', profile.doseExponent),
          ]) ...[
            Text('$label: ${v.note}', style: text.bodySmall),
            for (final s in v.sources) Padding(padding: const EdgeInsets.only(left: Gap.sm), child: SelectableText(s, style: text.labelSmall)),
            const SizedBox(height: 4),
          ],
          for (final x in profile.crossTolerance) ...[
            Text('With ${catalog[x.substanceKey]?.name ?? x.substanceKey}: ${x.note}', style: text.bodySmall),
            for (final s in x.sources) Padding(padding: const EdgeInsets.only(left: Gap.sm), child: SelectableText(s, style: text.labelSmall)),
            const SizedBox(height: 4),
          ],
        ],
      ),
      const SizedBox(height: Gap.md),
    ];
  }
}

/// What every track on the card is calculated from.
class _Context {
  const _Context({required this.catalog, required this.events, required this.live, required this.loads, required this.tracks, required this.settings, required this.now, required this.start});
  final Map<String, Substance> catalog;
  final List<UseEvent> events;
  final List<Ingestion> live;
  final Map<DateTime, double> loads;

  /// Each track's own ingestions, found once per journal state.
  final Map<String, List<Ingestion>> tracks;
  final EstimateSettings settings;
  final DateTime now;
  final DateTime start;
}
