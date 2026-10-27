import 'package:sj_core/sj_core.dart';

import 'database.dart';
import 'reference_repository.dart';

enum DosePhase {
  onset('Kicking in'),
  comeup('Coming up'),
  peak('At its strongest'),
  comedown('Coming down'),
  lingering('Lingering after-effects');

  const DosePhase(this.label);
  final String label;
}

/// One dose still working, with the clock times from its route's published timings. Times use the
/// longest published durations, which is the cautious reading for "has it fully arrived yet".
class ActiveDose {
  const ActiveDose({
    required this.ingestion,
    required this.substance,
    required this.phase,
    required this.fullEffectAt,
    required this.peakEndsAt,
    required this.mainEffectsEndAt,
    required this.lingerEndsAt,
  });

  final Ingestion ingestion;
  final Substance substance;
  final DosePhase phase;

  /// When onset and come-up are over, so the dose is as strong as it will get.
  final DateTime fullEffectAt;

  /// When the peak plateau ends and it starts to come down.
  final DateTime peakEndsAt;

  /// When the main effects are over.
  final DateTime mainEffectsEndAt;

  /// When the lighter after-effects end (the same as [mainEffectsEndAt] if the route lists none).
  final DateTime lingerEndsAt;

  bool get fullEffectReached => phase.index >= DosePhase.peak.index;
}

/// All of one substance's doses that are still working: the latest one drives the times, and a
/// repeat dose shows its own part.
class ActiveSubstance {
  const ActiveSubstance(this.substance, this.doses);
  final Substance substance;
  final List<ActiveDose> doses; // oldest first

  ActiveDose get latest => doses.last;
}

double _max(RouteOfAdministration roa, String phase) {
  final d = roa.duration(phase);
  return d?.maxMinutes ?? d?.minMinutes ?? 0;
}

DateTime _plus(DateTime t, double minutes) => t.add(Duration(microseconds: (minutes * Duration.microsecondsPerMinute).round()));

/// Longest the lingering tail is followed: a 24-hour after-effect window would keep a card up all day.
const maxLingerMinutes = 8 * 60;

/// Doses by one person that are still working at [now], grouped by substance and ordered by which
/// has the most time left. Alcohol is left to its own estimates. Pass only ONE person's ingestions.
List<ActiveSubstance> activeNow({
  required Iterable<Ingestion> ingestions,
  required ReferenceRepository reference,
  required DateTime now,
}) {
  final byKey = <String, List<ActiveDose>>{};
  for (final i in ingestions) {
    if (i.deleted || i.substanceKey == 'alcohol' || i.time.isAfter(now)) continue;
    final substance = reference.byKey[i.substanceKey];
    final roa = substance?.nearestRoute(i.route);
    if (substance == null || roa == null) continue;
    final onset = _max(roa, 'onset');
    final comeup = _max(roa, 'comeup');
    final peak = _max(roa, 'peak');
    final offset = _max(roa, 'offset');
    final core = onset + comeup + peak + offset;
    if (core <= 0) continue;
    final linger = _max(roa, 'afterglow').clamp(0.0, maxLingerMinutes.toDouble()).toDouble();

    final elapsed = now.difference(i.time).inMicroseconds / Duration.microsecondsPerMinute;
    if (elapsed >= core + linger) continue;
    final phase = elapsed < onset
        ? DosePhase.onset
        : elapsed < onset + comeup
            ? DosePhase.comeup
            : elapsed < onset + comeup + peak
                ? DosePhase.peak
                : elapsed < core
                    ? DosePhase.comedown
                    : DosePhase.lingering;
    byKey.putIfAbsent(i.substanceKey, () => []).add(ActiveDose(
      ingestion: i,
      substance: substance,
      phase: phase,
      fullEffectAt: _plus(i.time, onset + comeup),
      peakEndsAt: _plus(i.time, onset + comeup + peak),
      mainEffectsEndAt: _plus(i.time, core),
      lingerEndsAt: _plus(i.time, core + linger),
    ));
  }
  final result = [
    for (final e in byKey.entries)
      ActiveSubstance(e.value.first.substance, [...e.value]..sort((a, b) => a.ingestion.time.compareTo(b.ingestion.time))),
  ]..sort((a, b) => b.latest.lingerEndsAt.compareTo(a.latest.lingerEndsAt));
  return result;
}
