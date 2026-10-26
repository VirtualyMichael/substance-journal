import 'package:flutter/material.dart';

/// Spacing scale (logical pixels).
class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

const double wideBreakpoint = 840;

/// Maximum width of reading-oriented content on large screens.
const double contentMaxWidth = 960;

ThemeData buildTheme(Brightness brightness, {Color seed = const Color(0xFF4F7CAC)}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

/// A stable colour for each substance, used on timelines and chips.
const List<Color> _substancePalette = [
  Color(0xFF4F7CAC), // blue
  Color(0xFFE07A5F), // terracotta
  Color(0xFF3D9970), // green
  Color(0xFFB565A7), // orchid
  Color(0xFFE0A100), // amber
  Color(0xFF2EB5C4), // teal
  Color(0xFFD1495B), // rose
  Color(0xFF7A6FF0), // violet
  Color(0xFF8D9B3A), // olive
];

const Map<String, int> _paletteIndexByKey = {
  'alcohol': 4,
  'nicotine': 8,
  'cannabis': 2,
  'psilocybin_mushrooms': 3,
  'lsd': 7,
  'dmt': 6,
  'mdma': 1,
  '2c-b': 5,
  'ketamine': 0,
};

Color substanceColor(String key) {
  final index = _paletteIndexByKey[key] ?? (key.hashCode.abs() % _substancePalette.length);
  return _substancePalette[index];
}

/// "5 min ago", "2 h ago", "3 days ago", used in usage subtitles.
String relativeTime(DateTime when, DateTime now) {
  final diff = now.difference(when);
  if (diff.isNegative) return 'in the future';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 60) return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  return '${(diff.inDays / 30).floor()} months ago';
}

String formatDose(double? dose, String? unit) {
  if (dose == null) return 'dose unknown';
  final text = dose == dose.roundToDouble() ? dose.toStringAsFixed(0) : dose.toStringAsFixed(dose < 10 ? 2 : 1);
  return '$text${unit == null || unit.isEmpty ? '' : ' $unit'}';
}

String two(int n) => n.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String formatDate(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}

String formatDateTime(DateTime t) => '${formatDate(t)} ${formatClock(t)}';

String titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
