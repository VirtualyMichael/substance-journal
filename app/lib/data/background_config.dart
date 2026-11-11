import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';

import 'database.dart';

/// What sits behind the app: nothing, the animated flow, one still frame of it, or a photo/GIF.
enum BackgroundMode { off, flow, still, image }

/// How much work the flow does. Higher is smoother and finer and uses more battery.
enum BackgroundQuality {
  low('Low', 3, 15),
  balanced('Balanced', 4, 30),
  high('High', 6, 60);

  const BackgroundQuality(this.label, this.octaves, this.fps);
  final String label;

  /// Layers of detail in the flow.
  final int octaves;
  final int fps;
}

class FlowPalette {
  const FlowPalette(this.id, this.name, this.deep, this.mid, this.bright, this.glow);
  final String id;
  final String name;
  final Color deep;
  final Color mid;
  final Color bright;
  final Color glow;
}

const List<FlowPalette> flowPalettes = [
  FlowPalette('amethyst', 'Amethyst', Color(0xFF1A0B2E), Color(0xFF5B2A8C), Color(0xFFB784E8), Color(0xFFE9D5FF)),
  FlowPalette('gold', 'Gold', Color(0xFF2A2208), Color(0xFF7A6616), Color(0xFFD9C24A), Color(0xFFFFF3A0)),
  FlowPalette('aurora', 'Aurora', Color(0xFF04201F), Color(0xFF0F6B66), Color(0xFF5EE0C0), Color(0xFFC8FFE9)),
  FlowPalette('ember', 'Ember', Color(0xFF2A0A0A), Color(0xFF8A2A1A), Color(0xFFF08A4A), Color(0xFFFFD9A8)),
  FlowPalette('ocean', 'Ocean', Color(0xFF061A33), Color(0xFF1456A0), Color(0xFF5AB0F0), Color(0xFFCFEAFF)),
];

FlowPalette paletteById(String id) => flowPalettes.firstWhere((p) => p.id == id, orElse: () => flowPalettes.first);

/// The look behind the app. Stored on this device only.
class BackgroundConfig {
  const BackgroundConfig({this.mode = BackgroundMode.flow, this.palette = 'amethyst', this.dim = 0.35, this.imagePath, this.quality = BackgroundQuality.balanced});

  final BackgroundMode mode;
  final String palette;

  /// How much the background is veiled so text stays easy to read (0 to 0.8).
  final double dim;
  final String? imagePath;
  final BackgroundQuality quality;

  bool get active => mode != BackgroundMode.off;

  BackgroundConfig copyWith({BackgroundMode? mode, String? palette, double? dim, String? imagePath, BackgroundQuality? quality}) => BackgroundConfig(
        mode: mode ?? this.mode,
        palette: palette ?? this.palette,
        dim: dim ?? this.dim,
        imagePath: imagePath ?? this.imagePath,
        quality: quality ?? this.quality,
      );

  String encode() => jsonEncode({'mode': mode.name, 'palette': palette, 'dim': dim, 'image': imagePath, 'quality': quality.name});

  /// [defaultMode] is used when nothing has been chosen yet.
  static BackgroundConfig decode(String? raw, {BackgroundMode defaultMode = BackgroundMode.flow}) {
    if (raw == null) return BackgroundConfig(mode: defaultMode);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final dim = j['dim'];
      return BackgroundConfig(
        mode: BackgroundMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => defaultMode),
        palette: j['palette'] is String ? j['palette'] as String : 'amethyst',
        dim: dim is num ? dim.toDouble().clamp(0.0, 0.8) : 0.35,
        imagePath: j['image'] as String?,
        quality: BackgroundQuality.values.firstWhere((q) => q.name == j['quality'], orElse: () => BackgroundQuality.balanced),
      );
    } on Object {
      return BackgroundConfig(mode: defaultMode);
    }
  }
}

extension BackgroundSettings on AppDatabase {
  Stream<BackgroundConfig> watchBackground() {
    // Tests run without a background unless one is chosen: an endless animation never settles.
    final fallback = Platform.environment.containsKey('FLUTTER_TEST') ? BackgroundMode.off : BackgroundMode.flow;
    return watchSetting('background').map((v) => BackgroundConfig.decode(v, defaultMode: fallback));
  }

  Future<void> saveBackground(BackgroundConfig c) => setSetting('background', c.encode());
}
