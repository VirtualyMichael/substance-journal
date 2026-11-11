import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/background_config.dart';
import 'package:substance_journal_app/ui/background/app_background.dart';

// Renders each palette to a PNG when SJ_SHOT_DIR is set (to look at the flow without running the
// app), and always checks the shader compiles and paints something other than a flat colour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the flow shader compiles and loads', (tester) async {
    expect(await tester.runAsync(flowShaderAvailable), isTrue);
  });

  for (final palette in flowPalettes) {
    testWidgets('the ${palette.name} flow paints a varied picture', (tester) async {
      resetFlowShader();
      final key = GlobalKey();
      final dpr = double.tryParse(Platform.environment['SJ_DPR'] ?? '') ?? 1;
      tester.view.physicalSize = Size(900 * dpr / (dpr > 1 ? 2 : 1), 600 * dpr / (dpr > 1 ? 2 : 1));
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [backgroundProvider.overrideWith((ref) => Stream.value(BackgroundConfig(mode: BackgroundMode.still, palette: palette.id, dim: 0.1)))],
        child: MaterialApp(theme: ThemeData.dark(), home: RepaintBoundary(key: key, child: const AppBackground())),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // the shader loads
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      final px = bytes.buffer.asUint8List();
      final seen = <int>{};
      for (var i = 0; i < px.length; i += 4 * 977) {
        seen.add((px[i] >> 4) << 8 | (px[i + 1] >> 4) << 4 | (px[i + 2] >> 4));
      }
      expect(seen.length, greaterThan(8), reason: 'a flat colour means the shader did not run');
      expect(find.byType(CustomPaint), findsWidgets, reason: 'the shader, not the gradient fallback, is on screen');

      final dir = Platform.environment['SJ_SHOT_DIR'];
      if (dir != null) {
        final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
        File('$dir/flow-${palette.id}.png').writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  }
}
