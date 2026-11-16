import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/tolerance_projection.dart';
import '../charts/interactive_line_chart.dart';
import '../design.dart';
import '../insights/substance_detail_page.dart' show formatScore, scoreBands;
import '../link_tile.dart';

/// "Day 3" (or "Day 3, 6 h" in the readout) counted from the hypothetical first dose.
String projectionDayLabel(DateTime t, {bool hours = false}) {
  final h = t.difference(toleranceOrigin).inMinutes / 60;
  final day = (h / 24).floor();
  if (!hours) return 'Day ${(h / 24).round()}';
  final rest = (h - day * 24).round();
  return rest == 0 ? 'Day $day' : 'Day $day, $rest h';
}

String _days(DateTime t) {
  final d = t.difference(toleranceOrigin).inMinutes / 1440;
  if (d < 2) return '${(d * 24).round()} hours';
  return '${d < 10 ? d.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '') : d.round()} days';
}

String scheduleLabel(int? everyDays) => switch (everyDays) {
      null => 'One dose',
      1 => 'Daily',
      7 => 'Weekly',
      14 => 'Every 2 weeks',
      _ => 'Every $everyDays days',
    };

/// How tolerance from a common dose rises and falls, for the compound page. LSD, psilocybin
/// mushrooms, psilocin and mescaline use their published tolerance profile (a percent loss of
/// effect with a band); everything else the generic shape from a published half-life.
class ToleranceGraph extends StatefulWidget {
  const ToleranceGraph({super.key, required this.substance, required this.byKey});

  final Substance substance;
  final Map<String, Substance> byKey;

  @override
  State<ToleranceGraph> createState() => _ToleranceGraphState();
}

class _ToleranceGraphState extends State<ToleranceGraph> {
  int? _every;
  ToleranceProjection? _projection;
  final Map<int?, List<ProjectionPoint>> _series = {};
  List<ScheduleOutcome>? _outcomes;

  ToleranceProjection? get projection {
    final p = _projection;
    if (p != null && identical(p.substance, widget.substance) && identical(p.byKey, widget.byKey)) return p;
    _series.clear();
    _outcomes = null;
    return _projection = ToleranceProjection.of(widget.substance, widget.byKey);
  }

  @override
  Widget build(BuildContext context) {
    final p = projection;
    if (p == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.substance;
    final color = substanceColor(s.key);
    final key = s.key;

    // How far to draw: a single dose until it is gone (at least two weeks), schedules six weeks.
    final gone = p.baselineAt(band: ToleranceBand.high) ?? p.baselineAt();
    final singleDays = gone == null ? 14 : (gone.difference(toleranceOrigin).inHours / 24).ceil().clamp(7, 60) + 2;
    final days = _every == null ? singleDays : 42;
    final points = _series[_every] ??= p.series(everyDays: _every, days: days);
    final outcomes = _outcomes ??= p.schedules();
    final (peakAt, peakValue) = p.peak;
    final half = p.halfAt;
    final from = toleranceOrigin.subtract(const Duration(days: 1));
    final to = toleranceOrigin.add(Duration(days: days));
    String pct(double v) => '${v.round()}%';

    final chart = p.profiled
        ? InteractiveLineChart(
            key: ValueKey('tolerance-graph-chart-$key'),
            series: [
              ChartSeries(label: 'Estimate', color: color, points: [for (final q in points) (q.at, q.value * 100)], format: pct),
              ChartSeries(label: 'High end', color: color.withValues(alpha: 0.45), points: [for (final q in points) (q.at, (q.high ?? q.value) * 100)], fill: false, format: pct),
              ChartSeries(label: 'Low end', color: color.withValues(alpha: 0.45), points: [for (final q in points) (q.at, (q.low ?? q.value) * 100)], fill: false, format: pct),
            ],
            from: from,
            to: to,
            height: 190,
            yMin: 0,
            yMax: 100,
            yLabel: (v) => '${v.round()}%',
            xLabel: projectionDayLabel,
            markers: [
              ChartMarker(toleranceOrigin, 'Dose', color: color, dotted: false),
              if (_every == null) ChartMarker(peakAt, 'Peak'),
              if (_every == null && gone != null) ChartMarker(p.baselineAt() ?? gone, 'Gone (est.)'),
            ],
          )
        : InteractiveLineChart(
            key: ValueKey('tolerance-graph-chart-$key'),
            series: [ChartSeries(label: 'Tolerance', color: color, points: [for (final q in points) (q.at, q.value)], format: formatScore)],
            from: from,
            to: to,
            height: 190,
            yMin: 0,
            xLabel: projectionDayLabel,
            bands: scoreBands(scheme),
            markers: [
              ChartMarker(toleranceOrigin, 'Dose', color: color, dotted: false),
              if (_every == null && half != null) ChartMarker(half, 'Half'),
              if (_every == null && gone != null) ChartMarker(gone, 'Baseline'),
            ],
          );

    final loss = p.peakLoss;
    final facts = p.profiled
        ? 'After one common dose: largest about ${_days(peakAt)} later (about ${loss.percent}% weaker for a same-size dose, '
            'range ${loss.lowPercent}-${loss.highPercent}%)'
            '${half == null ? '' : ', half by about ${_days(half)}'}'
            '${p.baselineAt() == null ? '' : ', gone after about ${_days(p.baselineAt()!)}'}'
            '${p.baselineAt(band: ToleranceBand.low) == null || gone == null ? '' : ' (${_days(p.baselineAt(band: ToleranceBand.low)!)} to ${_days(gone)})'}.'
        : 'After one common dose: a score of ${formatScore(peakValue)} that halves about every ${_fmtDays(p.halfLifeDays)}'
            '${gone == null ? '' : ', back to baseline after about ${_days(gone)}'}.';

    final members = p.groupMembers;
    final group = s.toleranceGroup;

    return Column(
      key: ValueKey('tolerance-graph-$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.profiled
              ? 'Estimated loss of effect: how much weaker the same dose would feel, as a percent, with the shaded estimate between a low and a high end.'
              : 'A rough shape from a published half-life, not a measurement. 1.0 is the tolerance right after one common dose.',
          key: ValueKey('tolerance-graph-kind-$key'),
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final n in <int?>[null, ...toleranceRepeatDays])
            ChoiceChip(
              key: ValueKey('tolerance-schedule-${n ?? 0}'),
              label: Text(scheduleLabel(n)),
              visualDensity: VisualDensity.compact,
              selected: _every == n,
              onSelected: (_) => setState(() => _every = n),
            ),
        ]),
        const SizedBox(height: Gap.sm),
        chart,
        const SizedBox(height: 4),
        Text(facts, key: ValueKey('tolerance-graph-facts-$key'), style: text.bodySmall),
        if (s.toleranceFull != null && s.toleranceFull!.isNotEmpty) Text('Builds: ${s.toleranceFull}', style: text.bodySmall),
        if (group != null && group.isNotEmpty)
          Text(
            'Cross-tolerance group: ${titleCase(group)}.'
            '${members.isEmpty ? '' : ' Shares tolerance with ${members.take(8).join(', ')}${members.length > 8 ? ' and ${members.length - 8} more' : ''}.'}',
            key: ValueKey('tolerance-graph-group-$key'),
            style: text.bodySmall,
          ),
        const SizedBox(height: Gap.sm),
        Text('If you take a common dose every few days', style: text.titleSmall),
        for (final o in outcomes)
          Padding(
            key: ValueKey('tolerance-repeat-${o.everyDays}'),
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              p.profiled
                  ? '${scheduleLabel(o.everyDays)}: the next dose would feel about ${(o.beforeDose * 100).round()}% weaker '
                      '(range ${((o.low ?? o.beforeDose) * 100).round()}-${((o.high ?? o.beforeDose) * 100).round()}%).'
                  : '${scheduleLabel(o.everyDays)}: settles around ${formatScore(o.beforeDose)} just before each dose'
                      '${o.afterDose == null ? '' : ' and ${formatScore(o.afterDose!)} just after'}.',
              style: text.bodySmall,
            ),
          ),
        Text('After eight weeks of the pattern. Computed with the same model as the tolerance card on an experience.', style: text.labelSmall),
        const SizedBox(height: 4),
        Text(
          'With raised tolerance the same dose can feel weaker. Taking more to make up for it is a common way to take too much; waiting is what lowers tolerance.',
          style: text.bodySmall,
        ),
        if (p.profiled) ..._profileSources(context, p.profile!) else ..._genericSources(context, s),
      ],
    );
  }

  String _fmtDays(double d) => d < 1 ? '${(d * 24).round()} hours' : '${d.toStringAsFixed(d < 10 ? 1 : 0).replaceAll(RegExp(r'\.0$'), '')} days';

  List<Widget> _genericSources(BuildContext context, Substance s) {
    final text = Theme.of(context).textTheme;
    return [
      Text(
        'Source: ${[
          if (s.toleranceHalf != null && s.toleranceHalf!.isNotEmpty) 'half tolerance ${s.toleranceHalf}',
          if (s.toleranceZero != null && s.toleranceZero!.isNotEmpty) 'back to baseline ${s.toleranceZero}',
        ].join(', ').ifEmpty('no published tolerance times; a 3-day half-life is assumed')} (PsychonautWiki). '
        'The curve assumes tolerance is largest right after a dose and halves at a steady rate, which real tolerance does not exactly do.',
        key: ValueKey('tolerance-graph-source-${s.key}'),
        style: text.bodySmall,
      ),
      if (s.wikiUrl != null) LinkTile(s.wikiUrl!, label: 'Tolerance on PsychonautWiki'),
    ];
  }

  List<Widget> _profileSources(BuildContext context, ToleranceProfile profile) {
    final text = Theme.of(context).textTheme;
    return [
      const SizedBox(height: 4),
      Text(profile.summary, key: ValueKey('tolerance-graph-source-${widget.substance.key}'), style: text.bodySmall),
      if (profile.limits.isNotEmpty) Text(profile.limits, style: text.bodySmall),
      ExpansionTile(
        key: ValueKey('tolerance-graph-sources-${widget.substance.key}'),
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
            for (final src in v.sources) Padding(padding: const EdgeInsets.only(left: Gap.sm), child: SelectableText(src, style: text.labelSmall)),
            const SizedBox(height: 4),
          ],
          for (final x in profile.crossTolerance) ...[
            Text('With ${widget.byKey[x.substanceKey]?.name ?? x.substanceKey}: ${x.note}', style: text.bodySmall),
            for (final src in x.sources) Padding(padding: const EdgeInsets.only(left: Gap.sm), child: SelectableText(src, style: text.labelSmall)),
            const SizedBox(height: 4),
          ],
        ],
      ),
    ];
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
