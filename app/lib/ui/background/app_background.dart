import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/background_config.dart';
import '../../providers.dart';

final backgroundProvider = StreamProvider<BackgroundConfig>((ref) => ref.watch(databaseProvider).watchBackground());

/// Two looks for the same flow.
///
/// - [noise]: marbled, domain-warped noise. Rich, and what computers use.
/// - [silk]: layered sine bends. Phones run shaders at half precision, which turns noise hashing
///   into hard-edged polygons, so they use this one, which has no hash and stays smooth.
enum FlowStyle {
  noise('shaders/amethyst_flow.frag'),
  silk('shaders/silk_flow.frag');

  const FlowStyle(this.asset);
  final String asset;
}

FlowStyle flowStyleForPlatform() => (Platform.isAndroid || Platform.isIOS) ? FlowStyle.silk : FlowStyle.noise;

/// Loaded once per style; null when the shader cannot run on this device (a gradient takes over).
final Map<FlowStyle, Future<ui.FragmentProgram?>> _programs = {};

Future<ui.FragmentProgram?> _loadProgram(FlowStyle style) => _programs[style] ??= () async {
      try {
        return await ui.FragmentProgram.fromAsset(style.asset);
      } on Object {
        return null;
      }
    }();

/// Forgets the loaded shaders so the next screen loads them again (each widget test has its own clock).
@visibleForTesting
void resetFlowShader() => _programs.clear();

/// Whether a flow shader compiled and loaded on this device (a test checks both, so a shader
/// mistake cannot hide behind the gradient fallback).
Future<bool> flowShaderAvailable([FlowStyle? style]) async => (await _loadProgram(style ?? flowStyleForPlatform())) != null;

/// The picture behind every screen. It sits under the whole app and repaints on its own layer, so
/// the screens above it never redraw because of it.
class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, this.style});

  /// Which look to draw; the platform's own when null.
  final FlowStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(backgroundProvider).value;
    if (config == null || !config.active) return const SizedBox.shrink();
    final light = Theme.of(context).brightness == Brightness.light;
    final scrim = (light ? Colors.white : Colors.black).withValues(alpha: config.dim);
    final look = style ?? flowStyleForPlatform();
    Widget flow(bool animate) => _FlowLayer(style: look, palette: paletteById(config.palette), light: light, animate: animate, quality: config.quality);
    final Widget art;
    switch (config.mode) {
      case BackgroundMode.image:
        final path = config.imagePath;
        art = path != null && File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 2200, errorBuilder: (_, _, _) => flow(false))
            : flow(false);
      case BackgroundMode.flow:
      case BackgroundMode.still:
      case BackgroundMode.off:
        art = flow(config.mode == BackgroundMode.flow);
    }
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [art, ColoredBox(color: scrim)]),
      ),
    );
  }
}

class _FlowLayer extends StatefulWidget {
  const _FlowLayer({required this.style, required this.palette, required this.light, required this.animate, required this.quality});

  final FlowStyle style;
  final FlowPalette palette;
  final bool light;
  final bool animate;
  final BackgroundQuality quality;

  @override
  State<_FlowLayer> createState() => _FlowLayerState();
}

class _FlowLayerState extends State<_FlowLayer> with SingleTickerProviderStateMixin {
  // A frame in the middle of the flow that looks good as a still.
  static const _stillTime = 41.0;

  final _time = ValueNotifier<double>(_stillTime);
  late final Ticker _ticker;
  ui.FragmentProgram? _shader;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // A slow flow needs far fewer frames than the screen can draw; the level sets how many.
      if (elapsed < _last) _last = Duration.zero; // the ticker started over
      if (elapsed - _last < Duration(microseconds: 1000000 ~/ widget.quality.fps - 1500)) return;
      _last = elapsed;
      _time.value = _stillTime + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _loadProgram(widget.style).then((p) {
      if (mounted) setState(() => _shader = p);
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(_FlowLayer old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.animate && !_ticker.isActive) {
      // A restarted ticker counts from zero again, so forget how far the last run got.
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.animate && _ticker.isActive) {
      _ticker.stop();
      _time.value = _stillTime;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final shader = _shader;
    if (shader == null) {
      // No shader on this device (or it is still loading): a soft gradient in the same colours.
      return DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.deep, p.mid, p.bright.withValues(alpha: 0.8)])),
      );
    }
    return CustomPaint(
      painter: _FlowPainter(shader, widget.style, _time, p, widget.light, widget.quality.octaves, MediaQuery.devicePixelRatioOf(context)),
      size: Size.infinite,
      isComplex: true,
      willChange: widget.animate,
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.program, this.style, this.time, this.palette, this.light, this.octaves, this.pixelRatio) : super(repaint: time);

  final ui.FragmentProgram program;
  final FlowStyle style;
  final ValueNotifier<double> time;
  final FlowPalette palette;
  final bool light;
  final int octaves;
  final double pixelRatio;

  /// How long the silk flow takes to come round again. Shorter is livelier.
  static const _silkLoopSeconds = 150.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = program.fragmentShader();
    var i = 0;
    void colours() {
      for (final c in [palette.deep, palette.mid, palette.bright, palette.glow]) {
        s.setFloat(i++, c.r);
        s.setFloat(i++, c.g);
        s.setFloat(i++, c.b);
      }
    }

    switch (style) {
      case FlowStyle.noise:
        // Exactly as the computer version has always drawn it.
        s.setFloat(i++, size.width);
        s.setFloat(i++, size.height);
        s.setFloat(i++, time.value);
        s.setFloat(i++, light ? 1 : 0);
        colours();
        s.setFloat(i++, octaves.toDouble());
      case FlowStyle.silk:
        // The silk shader works in device pixels, so it is told the size in device pixels.
        s.setFloat(i++, size.width * pixelRatio);
        s.setFloat(i++, size.height * pixelRatio);
        s.setFloat(i++, light ? 1 : 0);
        colours();
        s.setFloat(i++, octaves.toDouble());
        // Time goes in as four phases already wrapped to one turn, worked out here in full
        // precision: a growing number would lose its fine steps on a phone and make the motion jerk.
        final turn = (time.value / _silkLoopSeconds) % 1.0 * 2 * pi;
        for (final m in const [1.0, -2.0, 3.0, -1.0]) {
          final x = (turn * m) % (2 * pi);
          s.setFloat(i++, x < 0 ? x + 2 * pi : x);
        }
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    s.dispose();
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.palette != palette || old.light != light || old.program != program || old.octaves != octaves || old.pixelRatio != pixelRatio || old.style != style;
}
