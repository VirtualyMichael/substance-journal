import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/reference_repository.dart';
import '../design.dart';
import '../dose_text.dart';

/// One curve on the timeline, for one ingestion.
class TimelineSeries {
  const TimelineSeries({
    required this.label,
    required this.color,
    required this.points,
    required this.ingestionId,
    this.doses = const [],
    this.substanceKey,
    this.parts = const [],
  });

  /// The substance this curve belongs to (null for charts that are not per substance).
  final String? substanceKey;
  final String label;
  final Color color;
  final List<(DateTime, double)> points;
  final String ingestionId;

  /// When each dose of this substance was taken, so the chart can mark them on the curve.
  final List<DateTime> doses;

  /// Each dose's own curve and colour, when there is more than one dose (the combined curve is their sum).
  final List<DosePart> parts;

  DateTime get start => points.first.$1;
  DateTime get end => points.last.$1;
  double get peak => points.fold(0.0, (m, p) => p.$2 > m ? p.$2 : m);
}

/// One dose of a substance: when, in what colour, and its curve on its own.
class DosePart {
  const DosePart({required this.time, required this.color, required this.points});
  final DateTime time;
  final Color color;
  final List<(DateTime, double)> points;
}

/// Colours a person can give a dose (the first entry, null, means automatic).
const dosePalette = <Color>[
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF00ACC1),
  Color(0xFF1E88E5),
  Color(0xFF5E35B1),
  Color(0xFFD81B60),
  Color(0xFF6D4C41),
  Color(0xFF757575),
];

/// The colour a dose is drawn in: the one chosen for it, else the compound's colour shifted a little
/// for each extra dose of the same compound so doses can be told apart.
Color doseColor(Ingestion i, int indexAmongSame, Color base) {
  try {
    final c = (jsonDecode(i.detailsJson) as Map<String, dynamic>)['color'];
    if (c is num) return Color(c.toInt());
  } on Object {
    // Details written by another version: fall back to the automatic colour.
  }
  if (indexAmongSame == 0) return base;
  final hsl = HSLColor.fromColor(base);
  final shifted = hsl.withHue((hsl.hue + 34.0 * indexAmongSame) % 360).withLightness((hsl.lightness + (indexAmongSame.isOdd ? 0.08 : -0.06)).clamp(0.3, 0.7));
  return shifted.toColor();
}

/// The colour of every dose in a list, by ingestion id (doses of one compound are told apart in time order).
Map<String, Color> doseColors(Iterable<Ingestion> ingestions) {
  final byKey = <String, List<Ingestion>>{};
  for (final i in ingestions) {
    byKey.putIfAbsent(i.substanceKey, () => []).add(i);
  }
  final out = <String, Color>{};
  byKey.forEach((key, list) {
    list.sort((a, b) => a.time.compareTo(b.time));
    for (var n = 0; n < list.length; n++) {
      out[list[n].id] = doseColor(list[n], n, substanceColor(key));
    }
  });
  return out;
}

/// A note or rating pinned to a moment on the timeline.
class TimelineMarker {
  const TimelineMarker({required this.time, required this.color, required this.label, this.isRating = false});
  final DateTime time;
  final Color color;
  final String label;
  final bool isRating;
}

/// Builds one combined curve per substance, so several doses over a day add up on one line,
/// and records when each dose was taken. Pass the ingestions of ONE person (an experience
/// belongs to exactly one person), so curves can never mix people.
List<TimelineSeries> buildTimelineSeries({
  required List<Ingestion> ingestions,
  required ReferenceRepository reference,
  required DateTime now,
}) {
  final bySubstance = <String, List<Ingestion>>{};
  for (final ingestion in ingestions) {
    bySubstance.putIfAbsent(ingestion.substanceKey, () => []).add(ingestion);
  }
  final result = <TimelineSeries>[];
  for (final entry in bySubstance.entries) {
    final substance = reference.byKey[entry.key];
    if (substance == null) continue;
    final curveIngestions = <CurveIngestion>[];
    final used = <Ingestion>[];
    for (final ingestion in entry.value) {
      // A route the reference data lacks borrows the nearest route's timing rather than drawing nothing.
      final roa = substance.nearestRoute(ingestion.route);
      if (roa == null) continue;
      // Unknown dose: assume the route's common dose so the curve still shows its timing.
      curveIngestions.add(CurveIngestion(
        substanceKey: substance.key,
        roaId: roa.id,
        amount: ingestion.dose ?? roa.doseCommon?.min ?? 1.0,
        occurredAt: ingestion.time,
      ));
      used.add(ingestion);
    }
    if (curveIngestions.isEmpty) continue;
    final points = sessionEffectSeries(curveIngestions, reference.byKey, now: now);
    if (points.isEmpty) continue;
    used.sort((a, b) => a.time.compareTo(b.time));
    final base = substanceColor(substance.key);
    final colors = [for (var n = 0; n < used.length; n++) doseColor(used[n], n, base)];
    final parts = <DosePart>[];
    if (used.length > 1) {
      for (var n = 0; n < used.length; n++) {
        final roa = substance.nearestRoute(used[n].route)!;
        final own = sessionEffectSeries([
          CurveIngestion(
            substanceKey: substance.key,
            roaId: roa.id,
            amount: used[n].dose ?? roa.doseCommon?.min ?? 1.0,
            occurredAt: used[n].time,
          ),
        ], reference.byKey, now: now);
        if (own.isNotEmpty) parts.add(DosePart(time: used[n].time, color: colors[n], points: own));
      }
    }
    result.add(TimelineSeries(
      label: _seriesLabel(substance.name, used),
      color: used.length == 1 ? colors.first : base,
      parts: parts,
      points: points,
      ingestionId: used.first.id,
      doses: [for (final i in used) i.time],
      substanceKey: substance.key,
    ));
  }
  return result;
}

/// "LSD 100 µg" for one dose; "Alcohol 12 g (3 doses)" when several add up on one curve.
String _seriesLabel(String name, List<Ingestion> used) {
  if (used.first.substanceKey == 'alcohol') {
    if (used.length == 1) return '$name ${describeAlcoholDose(used.first)}';
    final grams = used.fold<double>(0, (sum, i) => sum + (i.dose ?? 0));
    final std = grams / 14.0;
    return '$name ${std == std.roundToDouble() ? std.toStringAsFixed(0) : std.toStringAsFixed(1)} standard drinks (${used.length} doses)';
  }
  if (used.length == 1) return '$name ${formatDose(used.first.dose, used.first.unit)}';
  final units = {for (final i in used) i.unit};
  final known = used.every((i) => i.dose != null) && units.length == 1;
  final total = known ? '${formatDose(used.fold<double>(0, (sum, i) => sum + i.dose!), units.single)} ' : '';
  return '$name $total(${used.length} doses)';
}

/// Progress through an experience as a whole-number percent, 0 to 100.
///
/// From the first ingestion to the moment its last curve ends. Used for the calendar's
/// multi-person badge. Before the first dose it is 0, afterwards it is capped at 100.
int experienceProgressPercent({
  required List<TimelineSeries> series,
  required DateTime now,
}) {
  if (series.isEmpty) return 0;
  var start = series.first.start;
  var end = series.first.end;
  for (final s in series) {
    if (s.start.isBefore(start)) start = s.start;
    if (s.end.isAfter(end)) end = s.end;
  }
  final total = end.difference(start).inMicroseconds;
  if (total <= 0) return 100;
  final elapsed = now.difference(start).inMicroseconds;
  if (elapsed <= 0) return 0;
  if (elapsed >= total) return 100;
  return (elapsed * 100 / total).round().clamp(0, 100);
}
