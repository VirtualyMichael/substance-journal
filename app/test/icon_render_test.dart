// Draws the app icon (a dose-and-effect curve) to PNG files at every size the platforms need.
//
// Skipped unless SJ_ICON_DIR is set:
//   SJ_ICON_DIR=../docs/icon flutter test test/icon_render_test.dart
// Then `python scripts/install_icons.py` copies them into the Android, iOS and Windows projects.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _outDir = Platform.environment['SJ_ICON_DIR'];

/// The logo on a 1024 square: a dark rounded tile, a baseline, and the curve of one dose
/// (rising, a plateau, falling away) with a dot where it was taken.
void paintLogo(Canvas c, double size, {required bool rounded}) {
  c.save();
  c.scale(size / 1024);
  const full = Rect.fromLTWH(0, 0, 1024, 1024);
  final tile = Paint()
    ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(1024, 1024), const [Color(0xFF1C3046), Color(0xFF0D1722)]);
  if (rounded) {
    c.drawRRect(RRect.fromRectAndRadius(full, const Radius.circular(224)), tile);
  } else {
    c.drawRect(full, tile);
  }

  final baseline = Paint()
    ..color = const Color(0x40FFFFFF)
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(150, 730), const Offset(874, 730), baseline);

  final curve = Path()
    ..moveTo(190, 730)
    ..cubicTo(330, 730, 360, 320, 520, 320)
    ..cubicTo(680, 320, 700, 730, 860, 730);
  final glow = const [Color(0xFF4FC3F7), Color(0xFF7BE3B8)];
  final fill = Path.from(curve)
    ..lineTo(190, 730)
    ..close();
  c.drawPath(
    fill,
    Paint()..shader = ui.Gradient.linear(const Offset(0, 320), const Offset(0, 730), [glow[0].withValues(alpha: 0.34), glow[1].withValues(alpha: 0.02)]),
  );
  c.drawPath(
    curve,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 58
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(const Offset(190, 0), const Offset(860, 0), glow),
  );
  c.drawCircle(const Offset(190, 730), 46, Paint()..color = const Color(0xFFFFFFFF));
  c.drawCircle(const Offset(190, 730), 20, Paint()..color = const Color(0xFF1C3046));
  c.restore();
}

Future<void> _write(WidgetTester tester, String name, int size, {required bool rounded}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    paintLogo(Canvas(recorder), size.toDouble(), rounded: rounded);
    final image = await recorder.endRecording().toImage(size, size);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$_outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final skip = _outDir == null ? 'set SJ_ICON_DIR to render the app icon' : null;

  testWidgets('render the app icon', skip: skip != null, (tester) async {
    // Rounded tile: the README, Windows and Android (older launchers show the file as it is).
    for (final s in [16, 24, 32, 48, 64, 72, 96, 128, 144, 192, 256, 512, 1024]) {
      await _write(tester, 'rounded_$s', s, rounded: true);
    }
    // Full square: iOS rounds the corners itself and rejects transparent pixels.
    for (final s in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]) {
      await _write(tester, 'square_$s', s, rounded: false);
    }
  });
}
