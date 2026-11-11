import 'dart:math';

import 'package:flutter/material.dart';

/// One line on an [InteractiveLineChart].
class ChartSeries {
  const ChartSeries({required this.label, required this.color, required this.points, this.fill = true, this.format});
  final String label;
  final Color color;
  final List<(DateTime, double)> points;
  final bool fill;

  /// How a value reads in the crosshair readout (defaults to two decimals).
  final String Function(double value)? format;

  double valueAt(DateTime t) {
    if (points.isEmpty) return 0;
    if (!t.isAfter(points.first.$1)) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      if (!points[i].$1.isBefore(t)) {
        final (t0, v0) = points[i - 1];
        final (t1, v1) = points[i];
        final span = t1.difference(t0).inMicroseconds;
        return span == 0 ? v1 : v0 + (v1 - v0) * t.difference(t0).inMicroseconds / span;
      }
    }
    return points.last.$2;
  }
}

/// A shaded horizontal band, e.g. "Moderate" tolerance or BAC above 0.08.
class ChartBand {
  const ChartBand(this.from, this.to, this.label, this.color);
  final double from;
  final double to;
  final String label;
  final Color color;
}

/// A vertical line at a moment: now, half, quarter, baseline.
class ChartMarker {
  const ChartMarker(this.at, this.label, {this.color, this.dotted = true});
  final DateTime at;
  final String label;
  final Color? color;
  final bool dotted;
}

/// The time spans offered above a chart.
enum ChartRange {
  week('1W', Duration(days: 7)),
  month('1M', Duration(days: 30)),
  quarter('3M', Duration(days: 91)),
  year('1Y', Duration(days: 365)),
  all('All', null);

  const ChartRange(this.label, this.span);
  final String label;
  final Duration? span;
}

class RangeChips extends StatelessWidget {
  const RangeChips({super.key, required this.value, required this.onChanged, this.keyPrefix = 'range'});
  final ChartRange value;
  final ValueChanged<ChartRange> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        children: [
          for (final r in ChartRange.values)
            ChoiceChip(
              key: ValueKey('$keyPrefix-${r.name}'),
              label: Text(r.label),
              visualDensity: VisualDensity.compact,
              selected: r == value,
              onSelected: (_) => onChanged(r),
            ),
        ],
      );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _pad(int n) => n.toString().padLeft(2, '0');

/// "Thu Nov 13, 14:20".
String chartDateTime(DateTime t) => '${_days[t.weekday - 1]} ${_months[t.month - 1]} ${t.day}, ${_pad(t.hour)}:${_pad(t.minute)}';

/// "Thu Nov 13".
String chartDate(DateTime t) => '${_days[t.weekday - 1]} ${_months[t.month - 1]} ${t.day}';

/// A time chart you can read by touch or mouse: drag a finger or move the pointer and a crosshair
/// follows with the date and every line's value at that moment. Bands shade value ranges and
/// markers show moments (dotted), each with a label.
class InteractiveLineChart extends StatefulWidget {
  const InteractiveLineChart({
    super.key,
    required this.series,
    required this.from,
    required this.to,
    this.bands = const [],
    this.markers = const [],
    this.height = 220,
    this.yMin = 0,
    this.yMax,
    this.yLabel,
    this.extraReadout,
    this.emptyText = 'Nothing to show for this range.',
  });

  final List<ChartSeries> series;
  final DateTime from;
  final DateTime to;
  final List<ChartBand> bands;
  final List<ChartMarker> markers;
  final double height;
  final double yMin;
  final double? yMax;
  final String Function(double value)? yLabel;

  /// More readout lines for the moment under the crosshair (e.g. when tolerance halves from there).
  final List<String> Function(DateTime at)? extraReadout;
  final String emptyText;

  @override
  State<InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<InteractiveLineChart> {
  double? _x;
  static const _left = 40.0;
  static const _right = 10.0;
  static const _top = 10.0;
  static const _bottom = 24.0;

  DateTime _timeAt(double x, double width) {
    final f = ((x - _left) / max(1, width - _left - _right)).clamp(0.0, 1.0);
    return widget.from.add(Duration(microseconds: (widget.to.difference(widget.from).inMicroseconds * f).round()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasData = widget.series.any((s) => s.points.any((p) => !p.$1.isBefore(widget.from) && !p.$1.isAfter(widget.to)));
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final at = _x == null ? null : _timeAt(_x!, width);
      void move(Offset p) => setState(() => _x = p.dx.clamp(_left, width - _right));
      return Semantics(
        label: 'Chart from ${chartDate(widget.from)} to ${chartDate(widget.to)}: ${widget.series.map((s) => s.label).join(', ')}',
        child: SizedBox(
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: MouseRegion(
                  onHover: (e) => move(e.localPosition),
                  onExit: (_) => setState(() => _x = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => move(d.localPosition),
                    onHorizontalDragStart: (d) => move(d.localPosition),
                    onHorizontalDragUpdate: (d) => move(d.localPosition),
                    child: CustomPaint(
                      painter: _ChartPainter(
                        widget: widget,
                        crosshair: at,
                        axis: scheme.outlineVariant,
                        label: scheme.onSurfaceVariant,
                        nowColor: scheme.error,
                        fontFamily: text.bodySmall?.fontFamily,
                        insets: const EdgeInsets.fromLTRB(_left, _top, _right, _bottom),
                      ),
                    ),
                  ),
                ),
              ),
              if (!hasData) Center(child: Text(widget.emptyText, style: text.bodySmall)),
              if (at != null && hasData)
                Positioned(
                  top: 0,
                  left: (_x! + 12 + 210 > width) ? max(0, _x! - 222) : _x! + 12,
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('chart-readout'),
                      constraints: const BoxConstraints(maxWidth: 210),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(8)),
                      child: DefaultTextStyle(
                        style: text.bodySmall!.copyWith(color: scheme.onInverseSurface),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chartDateTime(at), style: const TextStyle(fontWeight: FontWeight.w600)),
                            for (final s in widget.series)
                              if (s.points.isNotEmpty)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text('${s.label}: ${(s.format ?? (v) => v.toStringAsFixed(2))(s.valueAt(at))}')),
                                ]),
                            ...?widget.extraReadout?.call(at).map(Text.new),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.widget, required this.crosshair, required this.axis, required this.label, required this.nowColor, required this.fontFamily, required this.insets});
  final InteractiveLineChart widget;
  final DateTime? crosshair;
  final Color axis;
  final Color label;
  final Color nowColor;
  final String? fontFamily;
  final EdgeInsets insets;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(insets.left, insets.top, size.width - insets.right, size.height - insets.bottom);
    if (plot.width <= 0 || plot.height <= 0) return;
    final from = widget.from;
    final span = max(1, widget.to.difference(from).inMicroseconds);
    var top = widget.yMax ?? 0;
    if (widget.yMax == null) {
      for (final s in widget.series) {
        for (final p in s.points) {
          if (!p.$1.isBefore(from) && !p.$1.isAfter(widget.to) && p.$2 > top) top = p.$2;
        }
      }
      for (final b in widget.bands) {
        if (b.from < top * 1.6 && b.to.isFinite) top = max(top, min(b.to, top * 1.6));
      }
      top = top <= widget.yMin ? widget.yMin + 1 : top * 1.1;
    }
    final bottomV = widget.yMin;
    double x(DateTime t) => plot.left + t.difference(from).inMicroseconds / span * plot.width;
    double y(double v) => plot.bottom - ((v - bottomV) / (top - bottomV)).clamp(0.0, 1.0) * plot.height;

    // Bands, with their label at the right edge.
    for (final b in widget.bands) {
      final y1 = y(min(b.to, top));
      final y2 = y(max(b.from, bottomV));
      if (y2 - y1 < 1) continue;
      canvas.drawRect(Rect.fromLTRB(plot.left, y1, plot.right, y2), Paint()..color = b.color);
      _text(canvas, b.label, Offset(plot.right - 4, y1 + 2), alignRight: true, size: 10);
    }

    // Value grid.
    final grid = Paint()
      ..color = axis
      ..strokeWidth = 1;
    for (var n = 0; n <= 3; n++) {
      final v = bottomV + (top - bottomV) * n / 3;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid..color = axis.withValues(alpha: n == 0 ? 1 : 0.4));
      _text(canvas, (widget.yLabel ?? (v) => v.toStringAsFixed(v < 10 ? 1 : 0))(v), Offset(plot.left - 4, y(v) - 6), alignRight: true, size: 10);
    }

    // Time labels.
    final days = widget.to.difference(from).inHours / 24;
    final ticks = 4;
    for (var n = 0; n <= ticks; n++) {
      final t = from.add(Duration(microseconds: (span * n / ticks).round()));
      final s = days <= 2
          ? '${_pad(t.hour)}:${_pad(t.minute)}'
          : days <= 120
              ? '${_months[t.month - 1]} ${t.day}'
              : "${_months[t.month - 1]} '${(t.year % 100).toString().padLeft(2, '0')}";
      _text(canvas, s, Offset(x(t), plot.bottom + 5), center: true, size: 10);
    }

    // Lines.
    canvas.save();
    canvas.clipRect(plot.inflate(1));
    for (final s in widget.series) {
      if (s.points.length < 2) continue;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final o = Offset(x(s.points[i].$1), y(s.points[i].$2));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      if (s.fill) {
        final area = Path.from(path)
          ..lineTo(x(s.points.last.$1), plot.bottom)
          ..lineTo(x(s.points.first.$1), plot.bottom)
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: 0.12));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    // Markers.
    for (final m in widget.markers) {
      if (m.at.isBefore(from) || m.at.isAfter(widget.to)) continue;
      final mx = x(m.at);
      final paint = Paint()
        ..color = (m.color ?? label).withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      if (m.dotted) {
        for (var yy = plot.top; yy < plot.bottom; yy += 6) {
          canvas.drawLine(Offset(mx, yy), Offset(mx, min(yy + 3, plot.bottom)), paint);
        }
      } else {
        canvas.drawLine(Offset(mx, plot.top), Offset(mx, plot.bottom), paint);
      }
      _text(canvas, m.label, Offset(mx + 3, plot.top), size: 10, color: m.color ?? label);
    }

    // Crosshair and the values on each line.
    final c = crosshair;
    if (c != null) {
      final cx = x(c);
      canvas.drawLine(Offset(cx, plot.top), Offset(cx, plot.bottom), Paint()
        ..color = label
        ..strokeWidth = 1);
      for (final s in widget.series) {
        if (s.points.isEmpty) continue;
        canvas.drawCircle(Offset(cx, y(s.valueAt(c))), 4, Paint()..color = s.color);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, {bool center = false, bool alignRight = false, double size = 11, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: fontFamily, fontSize: size, color: color ?? label)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : (alignRight ? at.dx - tp.width : at.dx);
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.widget != widget || old.crosshair != crosshair || old.axis != axis || old.label != label;
}
