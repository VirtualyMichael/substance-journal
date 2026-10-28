import 'dart:math';

import 'package:flutter/material.dart';

import '../calendar/calendar_data.dart';
import '../design.dart';

const _barColor = Color(0xFFE0A100);

/// One bar per day. Wider than the screen? It scrolls, starting at the most recent day.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({super.key, required this.days, required this.today, this.height = 200, this.color = _barColor, this.noun = 'Standard drinks'});

  final Color color;

  /// What the bars count, for the screen-reader label.
  final String noun;

  /// Oldest first, one entry per calendar day (gaps already filled with zero).
  final List<(DateTime, double)> days;
  final DateTime today;
  final double height;

  static const double slot = 11.0;
  static const double leftAxis = 34.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = days.fold<double>(0, (s, d) => s + d.$2);
    return Semantics(
      label: '$noun per day, ${days.length} days, ${total.toStringAsFixed(1)} in total',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needed = days.length * slot + leftAxis + 8;
          final width = max(constraints.maxWidth, needed);
          final chart = SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _BarsPainter(
                days: days,
                today: today,
                barColor: color,
                axisColor: scheme.outline,
                gridColor: scheme.outlineVariant,
                textColor: scheme.onSurfaceVariant,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                todayColor: scheme.primary,
                fixedSlot: width > constraints.maxWidth ? slot : (width - leftAxis - 8) / max(days.length, 1),
              ),
            ),
          );
          if (width <= constraints.maxWidth) return chart;
          return SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: chart);
        },
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.days,
    required this.today,
    required this.barColor,
    required this.axisColor,
    required this.gridColor,
    required this.textColor,
    this.fontFamily,
    required this.todayColor,
    required this.fixedSlot,
  });

  final List<(DateTime, double)> days;
  final DateTime today;
  final Color barColor;
  final Color axisColor;
  final Color gridColor;
  final Color textColor;

  /// The app's text font, so chart labels match the rest of the screen.
  final String? fontFamily;
  final Color todayColor;
  final double fixedSlot;

  void _text(Canvas canvas, String s, Offset at, {bool right = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontFamily: fontFamily, fontSize: 10, color: textColor)), textDirection: TextDirection.ltr)..layout();
    canvas.drawRect(Rect.zero, Paint());
    final dx = right ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx);
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    const bottom = 22.0;
    final plot = Rect.fromLTRB(DailyBarsChart.leftAxis, top, size.width - 8, size.height - bottom);
    var maxValue = 4.0;
    for (final d in days) {
      if (d.$2 > maxValue) maxValue = d.$2;
    }
    maxValue = (maxValue / 2).ceil() * 2.0;
    double y(double v) => plot.bottom - plot.height * (v / maxValue);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final v = maxValue * i / 2;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1), Offset(plot.left - 4, y(v) - 6), right: true);
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, Paint()..color = axisColor);

    for (var i = 0; i < days.length; i++) {
      final (day, value) = days[i];
      final x = plot.left + i * fixedSlot;
      final barWidth = max(2.0, fixedSlot - 3);
      if (value > 0) {
        final rect = Rect.fromLTRB(x + 1, y(value), x + 1 + barWidth, plot.bottom);
        canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(2), topRight: const Radius.circular(2)), Paint()..color = barColor);
      }
      if (day == today) {
        canvas.drawRect(Rect.fromLTRB(x, plot.top, x + fixedSlot - 1, plot.bottom), Paint()
          ..color = todayColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke);
      }
      if (day.day == 1 || (i == 0)) {
        _text(canvas, '${day.month}/${day.day}', Offset(x, plot.bottom + 4));
      } else if (fixedSlot >= 9 && day.weekday == DateTime.monday && days.length <= 45) {
        _text(canvas, '${day.day}', Offset(x, plot.bottom + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.days != days || old.today != today || old.fixedSlot != fixedSlot || old.textColor != textColor;
}

/// A month grid coloured by standard drinks per day.
class MonthHeatmap extends StatelessWidget {
  const MonthHeatmap({super.key, required this.month, required this.totals, required this.today, required this.onShift});

  final DateTime month;
  final Map<DateTime, double> totals;
  final DateTime today;
  final void Function(int months) onShift;

  static const _names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grid = monthGrid(month);
    var peak = 4.0;
    for (final d in grid) {
      final v = totals[d] ?? 0;
      if (v > peak) peak = v;
    }
    return Column(
      children: [
        Row(
          children: [
            IconButton(key: const ValueKey('heat-prev'), tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => onShift(-1)),
            Expanded(
              child: Text(
                '${_names[month.month - 1]} ${month.year}',
                key: const ValueKey('heat-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(key: const ValueKey('heat-next'), tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: () => onShift(1)),
          ],
        ),
        Row(children: [for (final w in _weekdays) Expanded(child: Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall)))]),
        const SizedBox(height: 4),
        for (var row = 0; row < grid.length ~/ 7; row++)
          SizedBox(
            height: 40,
            child: Row(
              children: [
                for (final day in grid.sublist(row * 7, row * 7 + 7))
                  Expanded(
                    child: Builder(builder: (context) {
                      final value = totals[day] ?? 0;
                      final inMonth = day.month == month.month;
                      final intensity = value <= 0 ? 0.0 : (0.25 + 0.75 * (value / peak)).clamp(0.0, 1.0);
                      return Semantics(
                        label: '${_names[day.month - 1]} ${day.day}, ${value.toStringAsFixed(1)} standard drinks',
                        child: Container(
                          key: ValueKey('heat-${day.year}-${day.month}-${day.day}'),
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: value > 0 ? _barColor.withValues(alpha: intensity) : scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                            border: day == today ? Border.all(color: scheme.primary, width: 2) : null,
                          ),
                          child: Center(
                            child: Opacity(
                              opacity: inMonth ? 1 : 0.35,
                              child: Text(
                                value > 0 ? value.toStringAsFixed(value >= 10 ? 0 : 1) : '${day.day}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: value > 0 ? FontWeight.w700 : FontWeight.normal,
                                  color: value > 0 ? (intensity > 0.6 ? Colors.black : scheme.onSurface) : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Gap.xs),
        Text('Numbers are standard drinks; days without a drink show the date.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
