import 'dart:math';

import 'package:flutter/material.dart';

import '../design.dart';
import 'timeline_data.dart';

/// A labelled horizontal line at a value, e.g. "common dose".
class ReferenceLine {
  const ReferenceLine(this.value, this.label);
  final double value;
  final String label;
}

/// Draws each series over time, with a "Now" line and note/rating markers.
///
/// By default the vertical scale is relative intensity (1.0 is a common dose). Give
/// [yLabel] to show a real axis (the Alcohol mode BAC chart), and [reference] / [yMinimum] to
/// change the guide line and the smallest top of the scale.
class TimelineChart extends StatefulWidget {
  const TimelineChart({
    super.key,
    required this.series,
    required this.now,
    this.markers = const [],
    this.height = 220,
    this.reference = const ReferenceLine(1.0, 'common dose'),
    this.yMinimum = 1.0,
    this.yBase = 0.0,
    this.yLabel,
    this.emptyText = 'No ingestions yet',
    this.extraInfo,
  });

  final List<TimelineSeries> series;
  final List<TimelineMarker> markers;
  final DateTime now;
  final double height;

  /// More lines for the hover read-out at a moment (drinks so far, time to clear, ...).
  final List<String> Function(DateTime t)? extraInfo;

  /// The value at the bottom of the chart (0 unless a series only varies a little above a baseline).
  final double yBase;
  final ReferenceLine? reference;
  final double yMinimum;
  final String Function(double value)? yLabel;
  final String emptyText;

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  /// Where the pointer is over the chart (mouse hover, or the last touch), if anywhere.
  Offset? _hover;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final series = w.series;
    final scheme = Theme.of(context).colorScheme;
    final description = series.isEmpty
        ? 'Timeline with no ingestions'
        : 'Timeline of ${series.length} substances: ${series.map((s) => s.label).join(', ')}';
    return Semantics(
      label: description,
      child: SizedBox(
        height: w.height,
        width: double.infinity,
        child: MouseRegion(
          onHover: (e) => setState(() => _hover = e.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setState(() => _hover = d.localPosition),
            onHorizontalDragStart: (d) => setState(() => _hover = d.localPosition),
            onHorizontalDragUpdate: (d) => setState(() => _hover = d.localPosition),
            child: CustomPaint(
              painter: TimelinePainter(
                series: series,
                markers: w.markers,
                now: w.now,
                axisColor: scheme.outline,
                gridColor: scheme.outlineVariant,
                textColor: scheme.onSurfaceVariant,
                nowColor: scheme.error,
                reference: w.reference,
                yMinimum: w.yMinimum,
                yBase: w.yBase,
                yLabel: w.yLabel,
                emptyText: w.emptyText,
                hover: _hover,
                extraInfo: w.extraInfo,
                tipBackground: scheme.inverseSurface,
                tipText: scheme.onInverseSurface,
              ),
            ),
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
    this.reference = const ReferenceLine(1.0, 'common dose'),
    this.yMinimum = 1.0,
    this.yBase = 0.0,
    this.yLabel,
    this.emptyText = 'No ingestions yet',
    this.hover,
    this.extraInfo,
    this.tipBackground = const Color(0xFF303030),
    this.tipText = Colors.white,
  });

  /// Pointer position to show a read-out for (null for none).
  final Offset? hover;
  final List<String> Function(DateTime t)? extraInfo;
  final Color tipBackground;
  final Color tipText;

  final List<TimelineSeries> series;
  final List<TimelineMarker> markers;
  final DateTime now;
  final Color axisColor;
  final Color gridColor;
  final Color textColor;
  final Color nowColor;
  final ReferenceLine? reference;
  final double yMinimum;
  final double yBase;
  final String Function(double value)? yLabel;
  final String emptyText;

  static const _rightPad = 12.0;
  static const _topPad = 14.0;
  static const _bottomPad = 26.0;

  double get _leftPad => yLabel == null ? 8.0 : 48.0;

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
    var peak = yMinimum;
    for (final s in series) {
      if (s.peak > peak) peak = s.peak;
    }
    return yBase + (peak - yBase) * 1.15;
  }

  /// Gap between time ticks, chosen so there are at most about eight.
  static Duration tickStep(Duration span) {
    // Minutes: up to half a day, then whole days (1, 2, 7, 14, 30).
    const options = [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 2880, 10080, 20160, 43200];
    for (final m in options) {
      if (span.inMinutes / m <= 8) return Duration(minutes: m);
    }
    return const Duration(days: 90);
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
      _text(canvas, emptyText, Offset(plot.center.dx, plot.center.dy), center: true);
      return;
    }
    final (start, end) = r;
    final spanMicros = end.difference(start).inMicroseconds.toDouble();
    double x(DateTime t) => plot.left + plot.width * (t.difference(start).inMicroseconds / spanMicros);
    final top = yMax();
    double y(double v) => plot.bottom - plot.height * ((v - yBase) / (top - yBase));

    // Time grid and labels
    final step = tickStep(end.difference(start));
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final multiDay = end.difference(start) > const Duration(hours: 20);
    final ticks = <DateTime>[];
    if (step >= const Duration(days: 1)) {
      // Whole days: tick on local midnights so labels are dates.
      final days = step.inDays;
      var t = DateTime(start.year, start.month, start.day + 1);
      while (t.isBefore(end)) {
        ticks.add(t);
        t = DateTime(t.year, t.month, t.day + days);
      }
    } else {
      final stepMicros = step.inMicroseconds;
      var t = DateTime.fromMicrosecondsSinceEpoch(
        ((start.microsecondsSinceEpoch ~/ stepMicros) + 1) * stepMicros,
        isUtc: start.isUtc,
      );
      while (t.isBefore(end)) {
        ticks.add(t);
        t = t.add(step);
      }
    }
    for (final t in ticks) {
      final tx = x(t);
      canvas.drawLine(Offset(tx, plot.top), Offset(tx, plot.bottom), grid);
      final label = step >= const Duration(days: 1) || (multiDay && t.hour == 0 && t.minute == 0) ? '${t.month}/${t.day}' : formatClock(t);
      _text(canvas, label, Offset(tx, plot.bottom + 4), center: true);
    }

    // Value axis
    final labelOf = yLabel;
    if (labelOf != null) {
      for (var i = 0; i <= 3; i++) {
        final v = yBase + (top - yBase) * i / 3;
        final ty = y(v);
        if (i > 0) canvas.drawLine(Offset(plot.left, ty), Offset(plot.right, ty), grid);
        _text(canvas, labelOf(v), Offset(plot.left - 6, ty - 6), right: true);
      }
    }

    // Reference line
    final ref = reference;
    if (ref != null) {
      final common = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      canvas.drawLine(Offset(plot.left, y(ref.value)), Offset(plot.right, y(ref.value)), common);
      _text(canvas, ref.label, Offset(plot.left + 4, y(ref.value) - 13));
    }

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

    // Where each dose was taken: a dotted line up to the curve, and a dot on it.
    for (final s in series) {
      for (final t in s.doses) {
        if (t.isBefore(start) || t.isAfter(end)) continue;
        final dx = x(t);
        final dy = y(_valueAt(s, t));
        final line = Paint()
          ..color = s.color.withValues(alpha: 0.7)
          ..strokeWidth = 1.2;
        for (var yy = plot.bottom; yy > dy; yy -= 5) {
          canvas.drawLine(Offset(dx, yy), Offset(dx, max(yy - 2.5, dy)), line);
        }
        canvas.drawCircle(Offset(dx, dy), 4.5, Paint()..color = s.color);
      }
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

    final pointer = hover;
    if (pointer != null && pointer.dx >= plot.left && pointer.dx <= plot.right) {
      _paintReadout(canvas, size, plot, start, end, pointer.dx, x, y);
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

  /// Crosshair at [px] with a box giving the time, each curve's level there, any doses taken
  /// close to that moment, and notes or ratings pinned near it.
  void _paintReadout(Canvas canvas, Size size, Rect plot, DateTime start, DateTime end, double px, double Function(DateTime) x, double Function(double) y) {
    final spanMicros = end.difference(start).inMicroseconds;
    final t = start.add(Duration(microseconds: (spanMicros * (px - plot.left) / plot.width).round()));
    final multiDay = end.difference(start) > const Duration(hours: 20);
    final lines = <(String, Color?)>[
      (multiDay ? '${formatDate(t)} ${formatClock(t)}' : formatClock(t), null),
    ];
    final near = const Duration(minutes: 1) * (spanMicros / Duration.microsecondsPerMinute * 0.02).clamp(2, 90).round();

    canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), Paint()..color = textColor.withValues(alpha: 0.6)..strokeWidth = 1);
    for (final s in series) {
      if (t.isBefore(s.start) || t.isAfter(s.end)) continue;
      final v = _valueAt(s, t);
      canvas.drawCircle(Offset(px, y(v)), 4, Paint()..color = s.color);
      final level = yLabel != null ? yLabel!(v) : '${(v * 100).round()}% of a common dose';
      lines.add(('${_shortName(s.label)}: $level', s.color));
      for (final d in s.doses) {
        if (d.difference(t).abs() <= near) lines.add(('  dose at ${formatClock(d)}: ${_doseText(s.label)}', null));
      }
      if (extraInfo == null && s.doses.isNotEmpty) {
        // Where this substance's curve tops out and when it has faded.
        var peak = s.points.first;
        for (final p in s.points) {
          if (p.$2 > peak.$2) peak = p;
        }
        lines.add(('  peaks ${formatClock(peak.$1)}, fades by ${formatClock(s.end)}', null));
      }
    }
    for (final extra in extraInfo?.call(t) ?? const <String>[]) {
      lines.add((extra, null));
    }
    for (final m in markers) {
      if (m.time.difference(t).abs() <= near) {
        lines.add(('${m.isRating ? 'Rating' : 'Note'} ${formatClock(m.time)}: ${m.label}', m.color));
      }
    }
    if (!now.isBefore(start) && now.difference(t).abs() <= near) lines.add(('Now', nowColor));
    if (lines.length == 1) lines.add(('Nothing active', null));

    final painters = [
      for (final (text, color) in lines)
        TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: 12, color: tipText, fontWeight: color == null ? null : FontWeight.w500)),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '...',
        )..layout(maxWidth: min(260, size.width - 16)),
    ];
    final boxW = painters.map((p) => p.width).reduce(max) + 20;
    final boxH = painters.fold<double>(0, (h, p) => h + p.height + 2) + 12;
    var left = px + 12;
    if (left + boxW > size.width - 4) left = px - 12 - boxW;
    left = left.clamp(4, max(4, size.width - boxW - 4));
    final top = plot.top + 4;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, boxW, boxH), const Radius.circular(8));
    canvas.drawRRect(box, Paint()..color = tipBackground.withValues(alpha: 0.94));
    var dy = top + 6;
    for (var i = 0; i < painters.length; i++) {
      final color = lines[i].$2;
      if (color != null) canvas.drawCircle(Offset(left + 8, dy + painters[i].height / 2), 3, Paint()..color = color);
      painters[i].paint(canvas, Offset(left + (color != null ? 15 : 10), dy));
      dy += painters[i].height + 2;
    }
  }

  /// "Alcohol 7.40 g" gives "Alcohol"; "Alcohol 12 g (3 doses)" gives "Alcohol (3 doses)".
  static String _shortName(String label) {
    final doses = RegExp(r'\(\d+ doses\)$').firstMatch(label);
    final name = label.split(RegExp(r'\s\d')).first;
    return doses == null ? name : '$name (${doses.group(0)!.replaceAll(RegExp(r'[()]'), '')})';
  }

  static String _doseText(String label) => label.replaceFirst(label.split(RegExp(r'\s\d')).first, '').trim();

  /// The curve's value at [t], interpolated between its two nearest points.
  static double _valueAt(TimelineSeries s, DateTime t) {
    final pts = s.points;
    if (t.isBefore(pts.first.$1)) return pts.first.$2;
    for (var i = 1; i < pts.length; i++) {
      if (!pts[i].$1.isBefore(t)) {
        final (t0, v0) = pts[i - 1];
        final (t1, v1) = pts[i];
        final span = t1.difference(t0).inMicroseconds;
        if (span == 0) return v1;
        return v0 + (v1 - v0) * (t.difference(t0).inMicroseconds / span);
      }
    }
    return pts.last.$2;
  }

  void _text(Canvas canvas, String text, Offset at, {bool center = false, bool right = false, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 11, color: color ?? textColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : (right ? at.dx - tp.width : at.dx);
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(TimelinePainter old) =>
      old.hover != hover ||
      old.series != series ||
      old.markers != markers ||
      old.now != now ||
      old.textColor != textColor ||
      old.reference != reference ||
      old.yMinimum != yMinimum ||
      old.yBase != yBase;
}
