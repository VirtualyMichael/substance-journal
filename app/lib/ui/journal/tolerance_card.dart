import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

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

/// Where tolerance stands for what this session contains, which way it is heading, and how often
/// each compound has been used lately: context for reading the curve above it. A model from
/// published tolerance times and the person's own log, not a measurement.
class ToleranceCard extends ConsumerWidget {
  const ToleranceCard({super.key, required this.personId, required this.experience, required this.sessionIngestions});

  final String personId;
  final Experience experience;
  final List<Ingestion> sessionIngestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final catalog = ref.watch(catalogProvider);
    final all = ref.watch(personIngestionsProvider(personId)).value ?? const <Ingestion>[];
    final text = Theme.of(context).textTheme;

    final keys = <String>{};
    for (final i in sessionIngestions) {
      final s = catalog.byKey[i.substanceKey];
      if (s != null && s.hasTolerance) keys.add(toleranceTrackKey(s));
    }
    final tracks = [
      for (final t in toleranceTracks(events: [for (final i in all) if (!i.deleted) UseEvent(i.substanceKey, i.time)], byKey: catalog.byKey, now: now))
        if (keys.contains(t.key)) t,
    ];
    if (tracks.isEmpty) return const SizedBox.shrink();

    // Use before this session, for "days since last time" and how often lately.
    final start = sessionIngestions.map((i) => i.time).reduce((a, b) => a.isBefore(b) ? a : b);
    String contextFor(ToleranceTrack t) {
      final mine = [
        for (final i in all)
          if (!i.deleted && catalog.byKey[i.substanceKey] != null && toleranceTrackKey(catalog.byKey[i.substanceKey]!) == t.key) i,
      ];
      final earlier = [for (final i in mine) if (i.time.isBefore(start.subtract(const Duration(hours: 12)))) i];
      final last = earlier.isEmpty ? null : earlier.map((i) => i.time).reduce((a, b) => a.isAfter(b) ? a : b);
      final month = mine.where((i) => !i.time.isBefore(now.subtract(const Duration(days: 30))) && !i.time.isAfter(now)).length;
      final week = mine.where((i) => !i.time.isBefore(now.subtract(const Duration(days: 7))) && !i.time.isAfter(now)).length;
      return [
        last == null ? 'First use in your log' : 'Before this: ${_gap(start.difference(last))} earlier',
        '$week in the last 7 days',
        '$month in the last 30',
      ].join('  |  ');
    }

    return Card(
      key: const ValueKey('tolerance-card'),
      margin: const EdgeInsets.only(top: Gap.sm),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tolerance and recent use', style: text.titleSmall),
            const SizedBox(height: Gap.sm),
            for (final t in tracks) ...[
              Row(
                children: [
                  Expanded(child: Text(t.label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                  _TrendChip(track: t, trend: toleranceTrend(t, now)),
                ],
              ),
              Text(contextFor(t), key: ValueKey('tolerance-context-${t.key}'), style: text.bodySmall),
              const SizedBox(height: 4),
              SizedBox(height: 46, width: double.infinity, child: CustomPaint(painter: _SparkPainter(t, now, substanceColor(t.key), Theme.of(context).colorScheme.outline))),
              Text(
                t.baselineAt == null
                    ? 'Back to baseline.'
                    : 'Back to baseline around ${formatDate(t.baselineAt!)} with no more use.',
                style: text.bodySmall,
              ),
              if (t.word == 'Moderate' || t.word == 'High')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'With raised tolerance the same dose can feel weaker. Taking more to make up for it is a common way to take too much; waiting is the safer fix.',
                    style: text.bodySmall,
                  ),
                ),
              const SizedBox(height: Gap.sm),
            ],
          ],
        ),
      ),
    );
  }
}

String _gap(Duration d) {
  if (d.inHours >= 47) return '${(d.inHours / 24).round()} days';
  if (d.inHours >= 2) return '${d.inHours} hours';
  return '${d.inMinutes} min';
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.track, required this.trend});
  final ToleranceTrack track;
  final ToleranceTrend trend;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (trend) {
      ToleranceTrend.rising => (Icons.trending_up, 'rising'),
      ToleranceTrend.falling => (Icons.trending_down, 'falling'),
      ToleranceTrend.steady => (Icons.trending_flat, 'steady'),
    };
    return Chip(
      key: ValueKey('tolerance-trend-${track.key}'),
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text('${track.word}, $label'),
    );
  }
}

/// The last two weeks and the next weeks of the score as a small line, with a marker for today.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.track, this.now, this.color, this.axis);
  final ToleranceTrack track;
  final DateTime now;
  final Color color;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = track.projection;
    if (pts.length < 2) return;
    final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = pts.last.$1.millisecondsSinceEpoch.toDouble();
    var top = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    if (top < 1) top = 1;
    double x(DateTime t) => (t.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(double v) => size.height - 2 - (v / top) * (size.height - 6);
    final path = Path();
    for (var n = 0; n < pts.length; n++) {
      final o = Offset(x(pts[n].$1), y(pts[n].$2));
      n == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), Paint()..color = axis.withValues(alpha: 0.4));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
    final nx = x(now).clamp(0.0, size.width);
    canvas.drawLine(Offset(nx, 0), Offset(nx, size.height), Paint()..color = axis..strokeWidth = 1);
    canvas.drawCircle(Offset(nx, y(track.level)), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.track != track || old.now != now;
}
