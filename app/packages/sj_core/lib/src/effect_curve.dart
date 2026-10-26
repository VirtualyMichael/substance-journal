// Dart port of Substance Journal's generic effect timeline (core/effect_curve.py), extended
// so a substance can supply its own route-specific curve (cannabis does; see cannabis.dart).
//
// The generic curve is a trapezoid built from a route's onset, comeup, peak and offset
// durations, scaled by dose. It approximates "how strong do you feel right now" for
// visualisation; it is not a pharmacokinetic model. Port checked against Python goldens
// (scripts/export_effect_golden.py) with route-specific models switched off.
import 'dart:math';

import 'cannabis.dart';
import 'reference.dart';

const double _defaultOnsetMinutes = 15.0;
const double _defaultComeupMinutes = 30.0;
const double _defaultPeakMinutes = 60.0;
const double _defaultOffsetMinutes = 60.0;

/// Caps how much a dose relative to the "common" reference dose can scale peak intensity.
const double maxDoseFactor = 3.0;
const double minDoseFactor = 0.1;

/// One dose reduced to what the curve needs. [amount] is in the route's reference-dose
/// unit; for cannabis it is the effective amount (see [CannabisDoseEstimate.bandAmountCentral]).
class CurveIngestion {
  const CurveIngestion({
    required this.substanceKey,
    required this.roaId,
    required this.amount,
    required this.occurredAt,
  });

  final String substanceKey;
  final String roaId;
  final double amount;
  final DateTime occurredAt;
}

/// How strong one ingestion feels over time.
abstract class IntensityCurve {
  DateTime get occurredAt;

  /// Time after which this ingestion no longer contributes.
  DateTime get endsAt;

  double intensity(DateTime at);
}

double _phaseMinutes(RouteOfAdministration roa, String phase, double fallback) {
  final d = roa.duration(phase);
  if (d == null) return fallback;
  return d.maxMinutes ?? d.minMinutes ?? fallback;
}

/// Peak intensity multiplier for a dose against the route's "common" band.
double doseFactor(double amount, RouteOfAdministration roa) {
  final commonMin = roa.doseCommon?.min;
  if (commonMin == null || commonMin <= 0) return 1.0;
  return max(minDoseFactor, min(amount / commonMin, maxDoseFactor));
}

DateTime _plusMinutes(DateTime t, double minutes) =>
    t.add(Duration(microseconds: (minutes * Duration.microsecondsPerMinute).round()));

double _secondsBetween(DateTime later, DateTime earlier) =>
    later.difference(earlier).inMicroseconds / Duration.microsecondsPerSecond;

class TrapezoidCurve implements IntensityCurve {
  TrapezoidCurve._(this.occurredAt, this.rampEnd, this.peakEnd, this.offsetEnd, this.peakIntensity);

  factory TrapezoidCurve(CurveIngestion ingestion, RouteOfAdministration roa) {
    final onset = _phaseMinutes(roa, 'onset', _defaultOnsetMinutes);
    final comeup = _phaseMinutes(roa, 'comeup', _defaultComeupMinutes);
    final peak = _phaseMinutes(roa, 'peak', _defaultPeakMinutes);
    final offset = _phaseMinutes(roa, 'offset', _defaultOffsetMinutes);

    final rampEnd = _plusMinutes(ingestion.occurredAt, onset + comeup);
    final peakEnd = _plusMinutes(rampEnd, peak);
    final offsetEnd = _plusMinutes(peakEnd, offset);
    return TrapezoidCurve._(ingestion.occurredAt, rampEnd, peakEnd, offsetEnd, doseFactor(ingestion.amount, roa));
  }

  @override
  final DateTime occurredAt;
  final DateTime rampEnd;
  final DateTime peakEnd;
  final DateTime offsetEnd;
  final double peakIntensity;

  @override
  DateTime get endsAt => offsetEnd;

  @override
  double intensity(DateTime at) {
    if (!at.isAfter(occurredAt)) return 0.0;
    if (!at.isAfter(rampEnd)) {
      final span = _secondsBetween(rampEnd, occurredAt);
      if (span <= 0) return peakIntensity;
      return peakIntensity * _secondsBetween(at, occurredAt) / span;
    }
    if (!at.isAfter(peakEnd)) return peakIntensity;
    if (!at.isAfter(offsetEnd)) {
      final span = _secondsBetween(offsetEnd, peakEnd);
      if (span <= 0) return 0.0;
      final remaining = _secondsBetween(offsetEnd, at) / span;
      return peakIntensity * max(remaining, 0.0);
    }
    return 0.0;
  }
}

/// The curve for one ingestion: a route-specific model when [useRouteModels] is on and one
/// exists (cannabis), otherwise the generic trapezoid.
IntensityCurve buildCurve(CurveIngestion ingestion, RouteOfAdministration roa, {bool useRouteModels = true}) {
  if (useRouteModels && ingestion.substanceKey == 'cannabis') {
    return CannabisCurve(ingestion, roa);
  }
  return TrapezoidCurve(ingestion, roa);
}

/// Combined intensity ("roughly how strong do you feel") summed over [ingestions].
///
/// Pass only ONE person's ingestions; curves are never mixed between people. [now] makes
/// the Now-marker range deterministic in tests.
List<(DateTime, double)> sessionEffectSeries(
  List<CurveIngestion> ingestions,
  Map<String, Substance> substancesByKey, {
  int pointsPerHour = 12,
  DateTime? now,
  bool useRouteModels = true,
}) {
  if (ingestions.isEmpty) return const [];

  final curves = <IntensityCurve>[];
  for (final ingestion in ingestions) {
    final substance = substancesByKey[ingestion.substanceKey];
    if (substance == null) continue;
    final roa = substance.roas.where((r) => r.id == ingestion.roaId).firstOrNull;
    if (roa == null) continue;
    curves.add(buildCurve(ingestion, roa, useRouteModels: useRouteModels));
  }
  if (curves.isEmpty) return const [];

  var start = curves.first.occurredAt;
  var naturalEnd = curves.first.endsAt;
  for (final c in curves) {
    if (c.occurredAt.isBefore(start)) start = c.occurredAt;
    if (c.endsAt.isAfter(naturalEnd)) naturalEnd = c.endsAt;
  }
  final current = now ?? DateTime.now();
  // Extend past the natural end so the Now marker is visible while a session winds down,
  // but never stretch an old session out to today.
  final DateTime end;
  if (!start.isAfter(current) && !current.isAfter(naturalEnd.add(const Duration(hours: 6)))) {
    end = current.isAfter(naturalEnd) ? current : naturalEnd;
  } else {
    end = naturalEnd;
  }

  double total(DateTime t) {
    var sum = 0.0;
    for (final c in curves) {
      sum += c.intensity(t);
    }
    return sum;
  }

  final step = Duration(microseconds: (Duration.microsecondsPerHour / pointsPerHour).round());
  final points = <(DateTime, double)>[];
  var t = start;
  while (!t.isAfter(end)) {
    points.add((t, total(t)));
    t = t.add(step);
  }
  points.add((end, total(end)));
  return points;
}
