import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../design.dart';

String _minutes(double m) {
  if (m < 1) return '${(m * 60).round()}s';
  if (m < 90) return '${m.round()}m';
  final h = m / 60;
  return h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

/// A mock graph of how one route typically feels over time: when it kicks in, when it peaks, when
/// it starts to drop off and how long the after-effects linger. Built from the published timings and
/// labelled as illustrative: real timings vary person to person, dose to dose and with food.
class RouteTimelineChart extends StatelessWidget {
  const RouteTimelineChart({super.key, required this.roa});

  final RouteOfAdministration roa;

  @override
  Widget build(BuildContext context) {
    final profile = routeProfile(roa);
    if (profile == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget key(Color color, String label, {bool dashed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 16, height: dashed ? 2 : 4, color: color),
            const SizedBox(width: 4),
            Text(label, style: text.bodySmall),
          ],
        );

    return Column(
      key: ValueKey('timeline-${roa.route}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ProfilePainter(profile, scheme, text.labelSmall ?? const TextStyle(fontSize: 10)),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.md,
          runSpacing: 4,
          children: [
            key(scheme.primary, 'Common dose'),
            if (profile.light != null) key(scheme.primary.withValues(alpha: 0.45), 'Lighter dose', dashed: true),
            if (profile.strong != null) key(scheme.error.withValues(alpha: 0.7), 'Stronger dose', dashed: true),
            key(scheme.primary.withValues(alpha: 0.18), 'Range of timings'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Illustrative shape from published timings, not a measurement. Height is relative strength; '
          'it varies with the person, the dose, food and how it was taken.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.p, this.scheme, this.labelStyle);

  final RouteProfile p;
  final ColorScheme scheme;
  final TextStyle labelStyle;

  static const _left = 6.0, _right = 6.0, _top = 18.0, _bottom = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _left - _right;
    final h = size.height - _top - _bottom;
    double x(double minutes) => _left + w * (minutes / p.end);
    double y(double v) => _top + h * (1 - v);

    void label(String s, Offset at, {Color? color, TextAlign align = TextAlign.center}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: labelStyle.copyWith(color: color ?? scheme.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.center ? at.dx - tp.width / 2 : at.dx;
      tp.paint(canvas, Offset(dx.clamp(0.0, max(0.0, size.width - tp.width)), at.dy));
    }

    // Phase bands, with a label where there is room.
    final phases = [
      ('Onset', 0.0, p.onsetEnd, scheme.outline.withValues(alpha: 0.10)),
      ('Come-up', p.onsetEnd, p.comeupEnd, scheme.tertiary.withValues(alpha: 0.12)),
      ('Peak', p.comeupEnd, p.peakEnd, scheme.primary.withValues(alpha: 0.14)),
      ('Come-down', p.peakEnd, p.offsetEnd, scheme.secondary.withValues(alpha: 0.12)),
      ('After', p.offsetEnd, p.end, scheme.outline.withValues(alpha: 0.08)),
    ];
    for (final (name, from, to, color) in phases) {
      if (to <= from) continue;
      canvas.drawRect(Rect.fromLTRB(x(from), _top, x(to), _top + h), Paint()..color = color);
      if (x(to) - x(from) > 38) label(name, Offset((x(from) + x(to)) / 2, 2));
    }

    // Baseline and time ticks.
    final axis = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_left, _top + h), Offset(size.width - _right, _top + h), axis);
    const steps = [5.0, 10, 15, 30, 60, 120, 180, 240, 360, 720, 1440, 2880];
    final tick = steps.firstWhere((s) => p.end / s <= 7, orElse: () => steps.last);
    for (var m = 0.0; m <= p.end + 1e-6; m += tick) {
      canvas.drawLine(Offset(x(m), _top + h), Offset(x(m), _top + h + 4), axis);
      label(m == 0 ? 'dose' : _minutes(m), Offset(x(m), _top + h + 6));
    }

    Path line(List<double> values) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final px = x(i * p.step);
        final py = y(values[i]);
        i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      return path;
    }

    // Range of timings: between the fastest and slowest published timings.
    final band = Path();
    for (var i = 0; i < p.length; i++) {
      final v = max(p.fastest[i], p.slowest[i]);
      final px = x(i * p.step);
      i == 0 ? band.moveTo(px, y(v)) : band.lineTo(px, y(v));
    }
    for (var i = p.length - 1; i >= 0; i--) {
      band.lineTo(x(i * p.step), y(min(p.fastest[i], p.slowest[i])));
    }
    band.close();
    canvas.drawPath(band, Paint()..color = scheme.primary.withValues(alpha: 0.18));

    Paint stroke(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;
    if (p.strong != null) canvas.drawPath(line(p.strong!), stroke(scheme.error.withValues(alpha: 0.7), 1.5));
    if (p.light != null) canvas.drawPath(line(p.light!), stroke(scheme.primary.withValues(alpha: 0.45), 1.5));
    canvas.drawPath(line(p.common), stroke(scheme.primary, 3));
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.p != p || old.scheme != scheme;
}
