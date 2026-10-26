import 'dart:math';

import 'package:flutter/material.dart';

import '../design.dart';
import 'timeline_data.dart';

/// Draws each ingestion's estimated intensity over time, with a "Now" line and note/rating
/// markers. Intensity is relative (1.0 is a common dose), not a measurement.
class TimelineChart extends StatelessWidget {
  const TimelineChart({
    super.key,
    required this.series,
    required this.now,
    this.markers = const [],
    this.height = 220,
  });

  final List<TimelineSeries> series;
  final List<TimelineMarker> markers;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final description = series.isEmpty
        ? 'Timeline with no ingestions'
        : 'Timeline of ${series.length} ingestions: ${series.map((s) => s.label).join(', ')}';
    return Semantics(
      label: description,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: TimelinePainter(
            series: series,
            markers: markers,
            now: now,
            axisColor: scheme.outline,
            gridColor: scheme.outlineVariant,
            textColor: scheme.onSurfaceVariant,
            nowColor: scheme.error,
          ),
        ),
      ),
    );
  }
}

class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.series,
    required this.markers,
    required this.now,
    required this.axisColor,
    required this.gridColor,
    required this.textColor,
    required this.nowColor,
  });

  final List<TimelineSeries> series;
  final List<TimelineMarker> markers;
  final DateTime now;
  final Color axisColor;
  final Color gridColor;
  final Color textColor;
  final Color nowColor;

  static const _leftPad = 8.0;
  static const _rightPad = 12.0;
  static const _topPad = 14.0;
  static const _bottomPad = 26.0;

  /// The time range shown: all curves and markers, plus the Now line when it is near them.
  (DateTime, DateTime)? range() {
    if (series.isEmpty) return null;
    var start = series.first.start;
    var end = series.first.end;
    for (final s in series) {
      if (s.start.isBefore(start)) start = s.start;
      if (s.end.isAfter(end)) end = s.end;
    }
    for (final m in markers) {
      if (m.time.isBefore(start)) start = m.time;
      if (m.time.isAfter(end)) end = m.time;
    }
    if (!now.isBefore(start) && now.difference(end) < const Duration(hours: 6)) {
      if (now.isAfter(end)) end = now;
    }
    final pad = Duration(minutes: max(5, end.difference(start).inMinutes ~/ 40));
    return (start.subtract(pad), end.add(pad));
  }

  double yMax() {
    var peak = 1.0;
    for (final s in series) {
      if (s.peak > peak) peak = s.peak;
    }
    return peak * 1.15;
  }

  /// Gap between time ticks, chosen so there are at most about eight.
  static Duration tickStep(Duration span) {
    const options = [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440];
    for (final m in options) {
      if (span.inMinutes / m <= 8) return Duration(minutes: m);
    }
    return const Duration(days: 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = range();
    final plot = Rect.fromLTRB(_leftPad, _topPad, size.width - _rightPad, size.height - _bottomPad);

    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);

    if (r == null) {
      _text(canvas, 'No ingestions yet', Offset(plot.center.dx, plot.center.dy), center: true);
      return;
    }
    final (start, end) = r;
    final spanMicros = end.difference(start).inMicroseconds.toDouble();
    double x(DateTime t) => plot.left + plot.width * (t.difference(start).inMicroseconds / spanMicros);
    final top = yMax();
    double y(double v) => plot.bottom - plot.height * (v / top);

    // Time grid and labels
    final step = tickStep(end.difference(start));
    final stepMicros = step.inMicroseconds;
    final first = DateTime.fromMicrosecondsSinceEpoch(
      ((start.microsecondsSinceEpoch ~/ stepMicros) + 1) * stepMicros,
      isUtc: start.isUtc,
    );
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final multiDay = end.difference(start) > const Duration(hours: 20);
    for (var t = first; t.isBefore(end); t = t.add(step)) {
      final tx = x(t);
      canvas.drawLine(Offset(tx, plot.top), Offset(tx, plot.bottom), grid);
      final label = multiDay && t.hour == 0 && t.minute == 0 ? '${t.month}/${t.day}' : formatClock(t);
      _text(canvas, label, Offset(tx, plot.bottom + 4), center: true);
    }

    // Reference line: a common dose.
    final common = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(plot.left, y(1.0)), Offset(plot.right, y(1.0)), common);
    _text(canvas, 'common dose', Offset(plot.left + 4, y(1.0) - 13));

    // Curves
    for (final s in series) {
      final path = Path();
      var started = false;
      for (final (t, v) in s.points) {
        final p = Offset(x(t), y(v));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      final fill = Path.from(path)
        ..lineTo(x(s.points.last.$1), plot.bottom)
        ..lineTo(x(s.points.first.$1), plot.bottom)
        ..close();
      canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: 0.16));
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Markers
    for (final m in markers) {
      final mx = x(m.time);
      canvas.drawLine(Offset(mx, plot.bottom), Offset(mx, plot.top + 6), Paint()..color = m.color.withValues(alpha: 0.5));
      final center = Offset(mx, plot.top + 6);
      if (m.isRating) {
        canvas.drawRect(Rect.fromCenter(center: center, width: 9, height: 9), Paint()..color = m.color);
      } else {
        canvas.drawCircle(center, 5, Paint()..color = m.color);
      }
    }

    // Now
    if (!now.isBefore(start) && !now.isAfter(end)) {
      final nx = x(now);
      final nowPaint = Paint()
        ..color = nowColor
        ..strokeWidth = 1.5;
      for (var dy = plot.top; dy < plot.bottom; dy += 6) {
        canvas.drawLine(Offset(nx, dy), Offset(nx, min(dy + 3, plot.bottom)), nowPaint);
      }
      _text(canvas, 'Now', Offset(nx, plot.top - 12), center: true, color: nowColor);
    }
  }

  void _text(Canvas canvas, String text, Offset at, {bool center = false, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 11, color: color ?? textColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? Offset(at.dx - tp.width / 2, at.dy - (tp.height > 0 ? 0 : 0)) : at);
  }

  @override
  bool shouldRepaint(TimelinePainter old) =>
      old.series != series || old.markers != markers || old.now != now || old.textColor != textColor;
}
