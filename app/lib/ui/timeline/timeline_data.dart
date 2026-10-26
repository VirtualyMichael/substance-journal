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
  });
  final String label;
  final Color color;
  final List<(DateTime, double)> points;
  final String ingestionId;

  /// When each dose of this substance was taken, so the chart can mark them on the curve.
  final List<DateTime> doses;

  DateTime get start => points.first.$1;
  DateTime get end => points.last.$1;
  double get peak => points.fold(0.0, (m, p) => p.$2 > m ? p.$2 : m);
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
    result.add(TimelineSeries(
      label: _seriesLabel(substance.name, used),
      color: substanceColor(substance.key),
      points: points,
      ingestionId: used.first.id,
      doses: [for (final i in used) i.time],
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
