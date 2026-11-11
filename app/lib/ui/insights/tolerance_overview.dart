import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/history_stats.dart';
import '../../providers.dart';
import '../charts/interactive_line_chart.dart';
import '../design.dart';
import 'substance_detail_page.dart';

/// Tolerance for everything this person has used in the last year: one chart for the substances
/// that share the score scale, one for alcohol's multiplier, and a card per substance that opens
/// its full history.
class ToleranceOverview extends ConsumerStatefulWidget {
  const ToleranceOverview({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<ToleranceOverview> createState() => _ToleranceOverviewState();
}

class _ToleranceOverviewState extends ConsumerState<ToleranceOverview> {
  ChartRange _range = ChartRange.month;

  // The figures only change when the journal does, so they are kept between the 30-second ticks.
  Object? _cacheKey;
  List<SubstanceHistory> _histories = const [];

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final catalog = ref.watch(catalogProvider);
    final rows = ref.watch(personIngestionsProvider(widget.person.id)).value ?? const <Ingestion>[];
    final settings = ref.watch(estimateSettingsProvider(widget.person.id)).value ?? const EstimateSettings();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final key = (rows, settings, catalog, now.day, now.hour);
    if (key != _cacheKey) {
      _cacheKey = key;
      _histories = buildHistories(ingestions: rows, byKey: catalog.byKey, settings: settings, now: now);
    }
    final recent = [for (final h in _histories) if (now.difference(h.last) <= const Duration(days: 365)) h];
    if (recent.isEmpty) return const SizedBox.shrink();

    final span = _range.span ?? now.difference(recent.map((h) => h.first).reduce((a, b) => a.isBefore(b) ? a : b)) + const Duration(days: 2);
    final from = now.subtract(span);
    final to = now.add(Duration(days: max(7, span.inDays ~/ 3)));

    final views = <String, ToleranceView>{};
    for (final h in recent) {
      final s = catalog.byKey[h.key];
      if (s == null || (!s.hasTolerance && s.key != 'alcohol')) continue;
      views[h.key] = toleranceView(substance: s, ingestions: rows, byKey: catalog.byKey, settings: settings, from: from, to: to, now: now);
    }

    // One line per tolerance track (substances sharing one would draw the same line twice).
    final tracks = <String, (List<String>, ToleranceView, String)>{};
    for (final e in views.entries) {
      // Leave out lines that stay at baseline for the whole range: they only add noise.
      if (e.value.alcohol || e.value.points.every((p) => p.$2 < baselineLevel)) continue;
      final existing = tracks[e.value.trackKey];
      final name = catalog.byKey[e.key]?.name ?? e.key;
      tracks[e.value.trackKey] = existing == null ? ([name], e.value, e.key) : ([...existing.$1, name], existing.$2, existing.$3);
    }
    final alcohol = views['alcohol'];

    final cards = [...recent]..sort((a, b) {
        final ra = views[a.key] == null ? -1 : toleranceRank(views[a.key]!);
        final rb = views[b.key] == null ? -1 : toleranceRank(views[b.key]!);
        return rb != ra ? rb.compareTo(ra) : b.last.compareTo(a.last);
      });

    return Column(
      key: const ValueKey('tolerance-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tolerance', style: text.titleLarge),
        const SizedBox(height: 4),
        Text('Drag across a chart to read any day. Dotted lines show where today\'s tolerance halves.', style: text.bodySmall),
        const SizedBox(height: Gap.sm),
        RangeChips(value: _range, onChanged: (r) => setState(() => _range = r)),
        const SizedBox(height: Gap.sm),
        if (tracks.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All substances (score)', style: text.titleSmall),
                const SizedBox(height: Gap.sm),
                InteractiveLineChart(
                  key: const ValueKey('overview-chart'),
                  series: [
                    for (final t in tracks.values) ChartSeries(label: t.$1.join(' / '), color: substanceColor(t.$3), points: t.$2.points, format: formatScore, fill: false),
                  ],
                  from: from,
                  to: to,
                  bands: scoreBands(scheme),
                  markers: [ChartMarker(now, 'Now', color: scheme.error, dotted: false)],
                ),
              ]),
            ),
          ),
        if (alcohol != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Alcohol (dose multiplier)', style: text.titleSmall),
                const SizedBox(height: Gap.sm),
                InteractiveLineChart(
                  key: const ValueKey('overview-alcohol-chart'),
                  series: [ChartSeries(label: 'Alcohol', color: substanceColor('alcohol'), points: alcohol.points, format: formatMultiplier)],
                  from: from,
                  to: to,
                  yMin: 1,
                  height: 160,
                  yLabel: (v) => '${v.toStringAsFixed(2)}x',
                  markers: [
                    ChartMarker(now, 'Now', color: scheme.error, dotted: false),
                    if (alcohol.plan.half != null) ChartMarker(alcohol.plan.half!, 'Half'),
                  ],
                ),
              ]),
            ),
          ),
        const SizedBox(height: Gap.sm),
        Text('By substance', style: text.titleMedium),
        const SizedBox(height: Gap.sm),
        for (final h in cards) _SubstanceCard(person: widget.person, history: h, view: views[h.key], now: now),
      ],
    );
  }
}

class _SubstanceCard extends StatelessWidget {
  const _SubstanceCard({required this.person, required this.history, required this.view, required this.now});
  final Person person;
  final SubstanceHistory history;
  final ToleranceView? view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final h = history;
    final v = view;
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(h.last.year, h.last.month, h.last.day)).inDays;
    final last = days == 0 ? 'today' : (days == 1 ? 'yesterday' : '$days days ago');
    final color = substanceColor(h.key);
    return Card(
      key: ValueKey('substance-card-${h.key}'),
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubstanceDetailPage(person: person, substanceKey: h.key))),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 12, backgroundColor: color, child: Text(h.name.characters.first, style: const TextStyle(color: Colors.white, fontSize: 12))),
              const SizedBox(width: Gap.sm),
              Expanded(child: Text(h.name, style: text.titleMedium)),
              if (v != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(trendIcon(v.trend), size: 16),
                  label: Text('${v.word}, ${trendWord(v.trend)}'),
                ),
              const Icon(Icons.chevron_right),
            ]),
            if (v != null && v.points.length > 1)
              SizedBox(height: 36, width: double.infinity, child: CustomPaint(painter: _Spark(v.points, color, now))),
            Text(
              [
                if (v != null && v.plan.half != null) 'half by ${chartDate(v.plan.half!)}',
                'last used $last',
                '${h.doses} ${h.doses == 1 ? 'dose' : 'doses'}',
                if (h.currentRunDays > 1) '${h.currentRunDays} days in a row',
              ].join(' · '),
              style: text.bodySmall,
            ),
            if (v != null && v.sharedWith.isNotEmpty) Text('Tolerance shared with ${v.sharedWith.join(', ')}', style: text.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _Spark extends CustomPainter {
  _Spark(this.points, this.color, this.now);
  final List<(DateTime, double)> points;
  final Color color;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = points.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = max(points.last.$1.millisecondsSinceEpoch.toDouble(), t0 + 1);
    final lo = points.map((p) => p.$2).reduce(min);
    final hi = max(points.map((p) => p.$2).reduce(max), lo + 0.5);
    double x(DateTime t) => (t.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(double v) => size.height - 3 - (v - lo) / (hi - lo) * (size.height - 6);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(x(points[i].$1), y(points[i].$2));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final nx = x(now).clamp(0.0, size.width);
    canvas.drawLine(Offset(nx, 0), Offset(nx, size.height), Paint()..color = color.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(_Spark old) => old.points != points || old.now != now;
}
