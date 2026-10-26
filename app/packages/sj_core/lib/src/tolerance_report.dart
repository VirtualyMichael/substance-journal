import 'reference.dart';
import 'tolerance.dart';

/// Where one person's tolerance stands for one track (a substance, or a group that cross-tolerates
/// such as "psychedelics"), and when it should be back to normal if they stop.
class ToleranceTrack {
  const ToleranceTrack({
    required this.key,
    required this.label,
    required this.level,
    required this.lastUse,
    required this.baselineAt,
    required this.projection,
    required this.substances,
  });

  final String key;
  final String label;

  /// Pooled score: each past use counts 1 and halves every [halfLifeDays] (see tolerance.dart).
  final double level;
  final DateTime lastUse;

  /// When the score drops under [baselineLevel], or null if it already is (or never within a year).
  final DateTime? baselineAt;

  /// The score at the start of each day from [from] for the chart, today onwards assuming no more use.
  final List<(DateTime, double)> projection;

  /// Names of the substances pooled in this track.
  final List<String> substances;

  String get word => toleranceWord(level);
}

/// Below this the effect of tolerance is too small to notice.
const double baselineLevel = 0.1;

String toleranceWord(double level) {
  if (level < baselineLevel) return 'None';
  if (level < 0.5) return 'Low';
  if (level < 1.5) return 'Moderate';
  return 'High';
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// One track per tolerance group or substance this person has used in the last [lookbackDays],
/// strongest first. Pass ONE person's use: tolerance is never pooled between people.
List<ToleranceTrack> toleranceTracks({
  required List<UseEvent> events,
  required Map<String, Substance> byKey,
  required DateTime now,
  int lookbackDays = 120,
  int projectDays = 60,
}) {
  final tracks = <String, List<UseEvent>>{};
  final names = <String, Set<String>>{};
  for (final e in events) {
    final s = byKey[e.substanceKey];
    if (s == null || !s.hasTolerance || e.at.isAfter(now)) continue;
    if (now.difference(e.at) > Duration(days: lookbackDays)) continue;
    final key = toleranceTrackKey(s);
    tracks.putIfAbsent(key, () => []).add(e);
    names.putIfAbsent(key, () => {}).add(s.name);
  }

  final result = <ToleranceTrack>[];
  for (final entry in tracks.entries) {
    final level = currentToleranceLevel(events, byKey, entry.key, now);
    final lastUse = entry.value.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);

    DateTime? baselineAt;
    if (level >= baselineLevel) {
      for (var day = 1; day <= 365; day++) {
        final t = now.add(Duration(days: day));
        if (currentToleranceLevel(events, byKey, entry.key, t) < baselineLevel) {
          baselineAt = t;
          break;
        }
      }
    }
    final start = DateTime(now.year, now.month, now.day);
    final projection = [
      for (var day = -14; day <= projectDays; day++)
        (start.add(Duration(days: day)), currentToleranceLevel(events, byKey, entry.key, start.add(Duration(days: day)))),
    ];

    final group = byKey[entry.value.first.substanceKey]?.toleranceGroup;
    final nameList = names[entry.key]!.toList()..sort();
    result.add(ToleranceTrack(
      key: entry.key,
      label: group != null ? _titleCase(group) : nameList.first,
      level: level,
      lastUse: lastUse,
      baselineAt: baselineAt,
      projection: projection,
      substances: nameList,
    ));
  }
  result.sort((a, b) => b.level.compareTo(a.level));
  return result;
}
