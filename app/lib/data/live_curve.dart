import 'package:sj_core/sj_core.dart';

import '../ui/alcohol/alcohol_view_model.dart';
import '../ui/design.dart';
import '../ui/timeline/timeline_data.dart';
import 'active_now.dart';
import 'database.dart';
import 'reference_repository.dart';

/// Alcohol's line is drawn as BAC divided by this, so it shares a scale with the other lines
/// (0.08% reads as "1.0", like a common dose of anything else).
const bacScale = 0.08;

List<List<num>> _clip(List<(DateTime, double)> points, DateTime from, DateTime to, {int max = 90, double scale = 1}) {
  final inside = [for (final p in points) if (!p.$1.isBefore(from) && !p.$1.isAfter(to)) p];
  final step = (inside.length / max).ceil().clamp(1, 1000);
  final out = <List<num>>[];
  for (var i = 0; i < inside.length; i += step) {
    out.add([inside[i].$1.millisecondsSinceEpoch, double.parse((inside[i].$2 * scale).toStringAsFixed(4))]);
  }
  if (inside.isNotEmpty && (inside.length - 1) % step != 0) {
    out.add([inside.last.$1.millisecondsSinceEpoch, double.parse((inside.last.$2 * scale).toStringAsFixed(4))]);
  }
  return out;
}

/// What the persistent "live curve" notification draws, as plain JSON for the Android side: one line
/// per active substance (name, colour, points, dose times) and, when alcohol is in the body, its BAC
/// curve and the BAC now. Null when nothing is active, which means the notification should go away.
/// Pass ONE person's ingestions. Every number is an estimate.
Map<String, Object?>? buildLiveCurve({
  required List<Ingestion> ingestions,
  required ReferenceRepository reference,
  required EstimateSettings alcoholSettings,
  required DateTime now,
  Duration back = const Duration(hours: 2),
  Duration ahead = const Duration(hours: 6),
}) {
  final live = [for (final i in ingestions) if (!i.deleted) i];
  final from = now.subtract(back);
  final to = now.add(ahead);

  final active = activeNow(ingestions: live, reference: reference, now: now);
  final drinks = [for (final i in live) if (i.substanceKey == 'alcohol') i];
  final alcohol = drinks.isEmpty ? null : summarizeAlcoholDay(allDrinks: drinks, settings: alcoholSettings, now: now);
  final bacNow = alcohol?.bacNow ?? 0;
  final alcoholActive = alcohol != null && ((alcohol.inBodyNow ?? 0) > 0.005 || bacNow > 0.001);
  if (active.isEmpty && !alcoholActive) return null;

  final keys = {for (final a in active) a.substance.key};
  final recent = [for (final i in live) if (keys.contains(i.substanceKey) && now.difference(i.time) < const Duration(hours: 36)) i];
  final built = buildTimelineSeries(ingestions: recent, reference: reference, now: now);

  final lines = <Map<String, Object?>>[];
  for (final s in built) {
    final key = s.substanceKey;
    if (key == null || !keys.contains(key)) continue;
    lines.add({
      'name': reference.byKey[key]?.name ?? key,
      'color': substanceColor(key).toARGB32(),
      'pts': _clip(s.points, from, to),
      'doses': [for (final d in s.doses) if (!d.isBefore(from) && !d.isAfter(to)) d.millisecondsSinceEpoch],
    });
  }

  Map<String, Object?>? bac;
  if (alcoholActive) {
    lines.add({
      'name': 'Alcohol',
      'color': substanceColor('alcohol').toARGB32(),
      'pts': _clip([for (final p in alcohol.bacSeries) (p.$1, p.$2)], from, to, scale: 1 / bacScale),
      'doses': [for (final d in drinks) if (!d.time.isBefore(from) && !d.time.isAfter(to)) d.time.millisecondsSinceEpoch],
    });
    bac = {
      'now': double.parse(bacNow.toStringAsFixed(4)),
      'pts': _clip([for (final p in alcohol.bacSeries) (p.$1, p.$2)], from, to),
    };
  }

  final ends = <DateTime>[
    for (final a in active) a.latest.lingerEndsAt,
    if (alcoholActive) alcohol.clearTime ?? to,
  ];
  final endsAt = ends.reduce((a, b) => a.isAfter(b) ? a : b);
  return {
    'now': now.millisecondsSinceEpoch,
    'from': from.millisecondsSinceEpoch,
    'to': to.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'lines': lines,
    'bac': bac,
  };
}
