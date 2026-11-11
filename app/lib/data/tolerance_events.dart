import 'package:sj_core/sj_core.dart';

import 'database.dart';

/// How big a dose was against a common dose for its route, for the tolerance model: 1.0 is a
/// common dose, clamped to 0.25-2.0 so one odd entry cannot dominate. 1.0 when the dose, its unit
/// or the reference range is missing.
double doseWeight(Ingestion i, Map<String, Substance> byKey) {
  final dose = i.dose;
  final roa = byKey[i.substanceKey]?.nearestRoute(i.route);
  final common = roa?.doseCommon?.min;
  if (dose == null || dose <= 0 || roa == null || common == null || common <= 0) return 1.0;
  if (i.unit != null && i.unit != roa.unit) return 1.0;
  return (dose / common).clamp(0.25, 2.0).toDouble();
}

/// One person's live doses as tolerance-model events, each weighted by its dose.
List<UseEvent> useEventsFor(Iterable<Ingestion> ingestions, Map<String, Substance> byKey) => [
      for (final i in ingestions)
        if (!i.deleted) UseEvent(i.substanceKey, i.time, weight: doseWeight(i, byKey)),
    ];
