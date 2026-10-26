import 'dart:convert';

/// Reference data models, parsed from the bundled `data/substances.json`
/// (produced by scripts/sync_substance_data.py plus the audited overrides).

class DoseRange {
  const DoseRange(this.min, this.max);
  final double? min;
  final double? max;

  static DoseRange? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return DoseRange((json['min'] as num?)?.toDouble(), (json['max'] as num?)?.toDouble());
  }
}

class DurationPhase {
  const DurationPhase(this.phase, this.minMinutes, this.maxMinutes);
  final String phase;
  final double? minMinutes;
  final double? maxMinutes;
}

class RouteOfAdministration {
  const RouteOfAdministration({
    required this.id,
    required this.substanceKey,
    required this.route,
    required this.unit,
    this.doseThreshold,
    this.doseLight,
    this.doseCommon,
    this.doseStrong,
    this.doseHeavy,
    this.durations = const [],
  });

  /// Stable `substance:route` key, e.g. `cannabis:smoked`.
  final String id;
  final String substanceKey;
  final String route;
  final String unit;
  final double? doseThreshold;
  final DoseRange? doseLight;
  final DoseRange? doseCommon;
  final DoseRange? doseStrong;
  final double? doseHeavy;
  final List<DurationPhase> durations;

  DurationPhase? duration(String phase) {
    for (final d in durations) {
      if (d.phase == phase) return d;
    }
    return null;
  }
}

/// Where a dose falls against a route's reference bands.
enum DoseClass { belowThreshold, threshold, light, common, strong, heavy }

/// Classifies [dose] (in the route's unit) against its bands, using [min, max) boundaries.
/// Returns null when the route publishes no dose bands at all.
DoseClass? classifyDose(RouteOfAdministration roa, double dose) {
  final hasBands = roa.doseThreshold != null ||
      roa.doseLight?.min != null ||
      roa.doseCommon?.min != null ||
      roa.doseStrong?.min != null ||
      roa.doseHeavy != null;
  if (!hasBands) return null;

  final heavy = roa.doseHeavy;
  if (heavy != null && dose >= heavy) return DoseClass.heavy;
  final strong = roa.doseStrong?.min;
  if (strong != null && dose >= strong) return DoseClass.strong;
  final common = roa.doseCommon?.min;
  if (common != null && dose >= common) return DoseClass.common;
  final light = roa.doseLight?.min;
  if (light != null && dose >= light) return DoseClass.light;
  final threshold = roa.doseThreshold;
  if (threshold != null && dose >= threshold) return DoseClass.threshold;
  return DoseClass.belowThreshold;
}

class Substance {
  const Substance({
    required this.key,
    required this.name,
    required this.category,
    required this.summary,
    required this.hasTolerance,
    this.toleranceGroup,
    this.toleranceZeroDays,
    this.toleranceHalfDays,
    this.roas = const [],
    this.commonNames = const [],
    this.sources = const [],
    this.safetyNotes = const [],
    this.dangerous = const [],
    this.unsafe = const [],
    this.uncertain = const [],
    this.audited = true,
    this.chemicalClass = '',
    this.license,
    this.wikiUrl,
  });

  final String key;
  final String name;
  final String category;
  final String summary;
  final bool hasTolerance;
  final String? toleranceGroup;
  final double? toleranceZeroDays;
  final double? toleranceHalfDays;
  final List<RouteOfAdministration> roas;
  final List<String> commonNames;
  final List<String> sources;
  final List<String> safetyNotes;
  final List<String> dangerous;
  final List<String> unsafe;
  final List<String> uncertain;

  /// False for the broad PsychonautWiki catalog, which is copied as published and has not been
  /// cross-checked the way the nine audited substances were.
  final bool audited;
  final String chemicalClass;
  final String? license;
  final String? wikiUrl;

  RouteOfAdministration? route(String route) {
    for (final r in roas) {
      if (r.route == route) return r;
    }
    return null;
  }

  /// The route whose timing best stands in for [route] when the reference data does not list
  /// it (for example an imported LSD dose taken "oral" when only "sublingual" is published).
  /// Null only if the compound has no routes at all.
  RouteOfAdministration? nearestRoute(String route) {
    final exact = this.route(route);
    if (exact != null) return exact;
    for (final candidate in _routeFamily[route] ?? const <String>[]) {
      final r = this.route(candidate);
      if (r != null) return r;
    }
    return roas.firstOrNull;
  }
}

/// Routes that behave alike, most similar first, for borrowing timing when one is missing.
const Map<String, List<String>> _routeFamily = {
  'oral': ['sublingual', 'buccal', 'rectal'],
  'sublingual': ['buccal', 'oral'],
  'buccal': ['sublingual', 'oral'],
  'rectal': ['oral', 'sublingual'],
  'smoked': ['inhaled', 'vaporized', 'insufflated'],
  'inhaled': ['smoked', 'vaporized', 'insufflated'],
  'vaporized': ['smoked', 'inhaled', 'insufflated'],
  'insufflated': ['inhaled', 'smoked', 'sublingual', 'intravenous'],
  'intravenous': ['intramuscular', 'subcutaneous', 'insufflated', 'smoked', 'inhaled'],
  'intramuscular': ['intravenous', 'subcutaneous', 'insufflated'],
  'subcutaneous': ['intramuscular', 'intravenous', 'insufflated'],
  'transdermal': ['oral', 'sublingual'],
};

const _unitMinutes = {'seconds': 1 / 60, 'minutes': 1.0, 'hours': 60.0, 'days': 1440.0};

List<String> _strings(Object? json) => (json as List?)?.map((e) => e as String).toList() ?? const [];

Substance _parseSubstance(Map<String, dynamic> j) {
  final key = j['key'] as String;
  final roas = <RouteOfAdministration>[];
  for (final r in (j['roas'] as List).cast<Map<String, dynamic>>()) {
    final durations = <DurationPhase>[];
    final dur = (r['duration'] as Map<String, dynamic>?) ?? const {};
    for (final phase in const ['onset', 'comeup', 'peak', 'offset', 'total', 'afterglow']) {
      final span = dur[phase];
      if (span is! Map<String, dynamic>) continue;
      final factor = _unitMinutes[(span['units'] as String?)?.toLowerCase()] ?? 1.0;
      final lo = (span['min'] as num?)?.toDouble();
      final hi = (span['max'] as num?)?.toDouble();
      if (lo == null && hi == null) continue;
      durations.add(DurationPhase(phase, lo == null ? null : lo * factor, hi == null ? null : hi * factor));
    }
    roas.add(RouteOfAdministration(
      id: '$key:${r['route']}',
      substanceKey: key,
      route: r['route'] as String,
      unit: r['unit'] as String,
      doseThreshold: (r['dose_threshold'] as num?)?.toDouble(),
      doseLight: DoseRange.fromJson(r['dose_light']),
      doseCommon: DoseRange.fromJson(r['dose_common']),
      doseStrong: DoseRange.fromJson(r['dose_strong']),
      doseHeavy: (r['dose_heavy'] as num?)?.toDouble(),
      durations: durations,
    ));
  }
  return Substance(
    key: key,
    name: j['name'] as String,
    category: j['category'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    hasTolerance: j['has_tolerance'] as bool,
    toleranceGroup: j['tolerance_group'] as String?,
    toleranceZeroDays: (j['tolerance_zero_days'] as num?)?.toDouble(),
    toleranceHalfDays: (j['tolerance_half_days'] as num?)?.toDouble(),
    roas: roas,
    commonNames: _strings(j['common_names']),
    sources: _strings(j['sources']),
    safetyNotes: _strings(j['safety_notes']),
    dangerous: _strings(j['dangerous_interactions']),
    unsafe: _strings(j['unsafe_interactions']),
    uncertain: _strings(j['uncertain_interactions']),
    audited: j['audited'] as bool? ?? true,
    chemicalClass: j['chemical_class'] as String? ?? '',
    license: j['license'] as String?,
    wikiUrl: j['wiki_url'] as String?,
  );
}

/// Parses the text of `substances.json` or `substances_extra.json`.
List<Substance> parseSubstances(String jsonText) =>
    (jsonDecode(jsonText) as List).cast<Map<String, dynamic>>().map(_parseSubstance).toList();
