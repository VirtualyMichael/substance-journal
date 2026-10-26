import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/reference_repository.dart';
import '../design.dart';

/// One curve on the timeline, for one ingestion.
class TimelineSeries {
  const TimelineSeries({required this.label, required this.color, required this.points, required this.ingestionId});
  final String label;
  final Color color;
  final List<(DateTime, double)> points;
  final String ingestionId;

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

/// Builds one curve per ingestion. Pass the ingestions of ONE person (an experience
/// belongs to exactly one person), so curves can never mix people.
List<TimelineSeries> buildTimelineSeries({
  required List<Ingestion> ingestions,
  required ReferenceRepository reference,
  required DateTime now,
}) {
  final result = <TimelineSeries>[];
  for (final ingestion in ingestions) {
    final substance = reference.byKey[ingestion.substanceKey];
    final roa = substance?.route(ingestion.route);
    if (substance == null || roa == null) continue;

    // Unknown dose: assume the route's common dose so the curve still shows its timing.
    final amount = ingestion.dose ?? roa.doseCommon?.min ?? 1.0;
    final points = sessionEffectSeries(
      [
        CurveIngestion(
          substanceKey: substance.key,
          roaId: roa.id,
          amount: amount,
          occurredAt: ingestion.time,
        ),
      ],
      reference.byKey,
      now: now,
    );
    if (points.isEmpty) continue;
    result.add(TimelineSeries(
      label: '${substance.name} ${formatDose(ingestion.dose, ingestion.unit)}',
      color: substanceColor(substance.key),
      points: points,
      ingestionId: ingestion.id,
    ));
  }
  return result;
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
