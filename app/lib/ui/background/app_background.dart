import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/background_config.dart';
import '../../providers.dart';

final backgroundProvider = StreamProvider<BackgroundConfig>((ref) => ref.watch(databaseProvider).watchBackground());

/// Loaded once; null when the shader cannot run on this device (the gradient takes over).
Future<ui.FragmentProgram?>? _program;

Future<ui.FragmentProgram?> _loadProgram() => _program ??= () async {
      try {
        return await ui.FragmentProgram.fromAsset('shaders/amethyst_flow.frag');
      } on Object {
        return null;
      }
    }();

/// The picture behind every screen. It sits under the whole app and repaints on its own layer, so
/// the screens above it never redraw because of it.
class AppBackground extends ConsumerWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(backgroundProvider).value;
    if (config == null || !config.active) return const SizedBox.shrink();
    final light = Theme.of(context).brightness == Brightness.light;
    final scrim = (light ? Colors.white : Colors.black).withValues(alpha: config.dim);
    final Widget art;
    switch (config.mode) {
      case BackgroundMode.image:
        final path = config.imagePath;
        art = path != null && File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _FlowLayer(palette: paletteById(config.palette), light: light, animate: false))
            : _FlowLayer(palette: paletteById(config.palette), light: light, animate: false);
      case BackgroundMode.flow:
      case BackgroundMode.still:
      case BackgroundMode.off:
        art = _FlowLayer(palette: paletteById(config.palette), light: light, animate: config.mode == BackgroundMode.flow);
    }
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [art, ColoredBox(color: scrim)]),
      ),
    );
  }
}

class _FlowLayer extends StatefulWidget {
  const _FlowLayer({required this.palette, required this.light, required this.animate});

  final FlowPalette palette;
  final bool light;
  final bool animate;

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
      // About 30 frames a second is plenty for a slow flow and halves the battery cost.
      if (elapsed - _last < const Duration(milliseconds: 33)) return;
      _last = elapsed;
      _time.value = _stillTime + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _loadProgram().then((p) {
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
    return CustomPaint(painter: _FlowPainter(shader, _time, p, widget.light), size: Size.infinite, isComplex: true, willChange: widget.animate);
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.program, this.time, this.palette, this.light) : super(repaint: time);

  final ui.FragmentProgram program;
  final ValueNotifier<double> time;
  final FlowPalette palette;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final s = program.fragmentShader();
    var i = 0;
    s.setFloat(i++, size.width);
    s.setFloat(i++, size.height);
    s.setFloat(i++, time.value);
    s.setFloat(i++, light ? 1 : 0);
    for (final c in [palette.deep, palette.mid, palette.bright, palette.glow]) {
      s.setFloat(i++, c.r);
      s.setFloat(i++, c.g);
      s.setFloat(i++, c.b);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    s.dispose();
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.palette != palette || old.light != light || old.program != program;
}
