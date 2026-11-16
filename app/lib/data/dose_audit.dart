import 'dart:convert';

import 'package:sj_core/sj_core.dart';

/// The cross-referenced dose audit (`assets/data/dose_audit.json`): for some compounds and
/// routes, dose bands checked against several published sources, with those sources, how far
/// they agree and how sure the audit is. It is an overlay: where an entry exists its bands
/// replace the catalog's, and everything else about the compound stays as it was.

class AuditSource {
  const AuditSource({required this.name, required this.url, required this.bandsAsPublished, this.retrieved});
  final String name;
  final String url;

  /// The source's own figures, as it publishes them (its wording and units).
  final String bandsAsPublished;
  final String? retrieved;
}

enum AuditAgreement { agree, minorDifferences, disagree }

enum AuditConfidence { high, medium, low }

class AuditedRoute {
  const AuditedRoute({
    required this.unit,
    required this.sources,
    required this.agreement,
    required this.confidence,
    this.threshold,
    this.low,
    this.common,
    this.high,
    this.heavy,
    this.note = '',
  });

  final String unit;
  final double? threshold;
  final DoseRange? low;
  final DoseRange? common;
  final DoseRange? high;
  final double? heavy;
  final List<AuditSource> sources;
  final AuditAgreement agreement;
  final AuditConfidence confidence;
  final String note;

  /// The route with these bands in place of its own; timings and identity are kept.
  RouteOfAdministration applyTo(RouteOfAdministration roa) => RouteOfAdministration(
        id: roa.id,
        substanceKey: roa.substanceKey,
        route: roa.route,
        unit: roa.unit,
        doseThreshold: threshold,
        doseLight: low,
        doseCommon: common,
        doseStrong: high,
        doseHeavy: heavy,
        durations: roa.durations,
      );
}

class DoseAudit {
  const DoseAudit(this.routes);

  /// Substance key -> route -> audited bands.
  final Map<String, Map<String, AuditedRoute>> routes;

  static const empty = DoseAudit({});

  bool get isEmpty => routes.isEmpty;

  AuditedRoute? route(String substanceKey, String route) => routes[substanceKey]?[route];

  /// The audit behind [roa]'s bands, or null when there is none or its unit differs (then the
  /// catalog's own bands were kept).
  AuditedRoute? behind(RouteOfAdministration roa) {
    final a = route(roa.substanceKey, roa.route);
    return a != null && _unit(a.unit) == _unit(roa.unit) ? a : null;
  }

  /// Parses the audit file. A missing, empty or malformed file gives [empty]; a malformed
  /// entry is skipped on its own, so one bad record never hides the rest.
  static DoseAudit tryParse(String? text) {
    if (text == null || text.trim().isEmpty) return empty;
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return empty;
    }
    final substances = json is Map<String, dynamic> ? json['substances'] : null;
    if (substances is! Map<String, dynamic>) return empty;
    final out = <String, Map<String, AuditedRoute>>{};
    for (final MapEntry(key: key, value: byRoute) in substances.entries) {
      if (byRoute is! Map<String, dynamic>) continue;
      for (final MapEntry(key: route, value: entry) in byRoute.entries) {
        final parsed = _parseRoute(entry);
        if (parsed != null) (out[key] ??= {})[route] = parsed;
      }
    }
    return DoseAudit(out);
  }

  /// Puts the audited bands into [substances] in place, for routes whose unit matches the
  /// audit's. The route list is edited rather than the substance rebuilt, so fields added to
  /// [Substance] later are never dropped. Returns how many routes were replaced.
  int applyTo(List<Substance> substances) {
    var applied = 0;
    for (final s in substances) {
      final byRoute = routes[s.key];
      if (byRoute == null) continue;
      for (var i = 0; i < s.roas.length; i++) {
        final roa = s.roas[i];
        final audited = byRoute[roa.route];
        if (audited == null || _unit(audited.unit) != _unit(roa.unit)) continue;
        try {
          s.roas[i] = audited.applyTo(roa);
          applied++;
        } on UnsupportedError {
          break; // a constant route list (never the bundled catalog); leave it as published
        }
      }
    }
    return applied;
  }
}

String _unit(String u) => u.trim().replaceAll('μ', 'µ').replaceAll('ug', 'µg').replaceAll('mcg', 'µg');

/// Null when absent; a wrong type or a negative number makes the whole entry invalid.
double? _num(Object? v) {
  if (v == null) return null;
  if (v is num && v.isFinite && v >= 0) return v.toDouble();
  throw FormatException('not a dose: $v');
}

DoseRange? _range(Object? v) {
  if (v is! Map<String, dynamic>) return null;
  final lo = _num(v['min']);
  final hi = _num(v['max']);
  if (lo == null && hi == null) return null;
  if (lo != null && hi != null && hi < lo) throw const FormatException('range runs backwards');
  return DoseRange(lo, hi);
}

AuditedRoute? _parseRoute(Object? j) {
  if (j is! Map<String, dynamic>) return null;
  try {
    final unit = j['unit'];
    if (unit is! String || unit.isEmpty) return null;
    final threshold = _num(j['threshold']);
    final low = _range(j['low']);
    final common = _range(j['common']);
    final high = _range(j['high']);
    final heavy = _num(j['heavy']);
    // The ladder has to rise, or the bands would classify doses nonsensically.
    final edges = [threshold, low?.min, common?.min, high?.min, heavy].whereType<double>().toList();
    if (edges.isEmpty) return null;
    for (var i = 1; i < edges.length; i++) {
      if (edges[i] < edges[i - 1]) return null;
    }
    final sources = <AuditSource>[
      for (final s in (j['sources'] as List? ?? const []))
        if (s is Map<String, dynamic> && s['name'] is String && s['url'] is String)
          AuditSource(
            name: s['name'] as String,
            url: s['url'] as String,
            bandsAsPublished: s['bands_as_published'] as String? ?? '',
            retrieved: s['retrieved'] as String?,
          ),
    ];
    if (sources.isEmpty) return null;
    return AuditedRoute(
      unit: unit,
      threshold: threshold,
      low: low,
      common: common,
      high: high,
      heavy: heavy,
      sources: sources,
      agreement: switch (j['agreement']) {
        'agree' => AuditAgreement.agree,
        'minor differences' => AuditAgreement.minorDifferences,
        _ => AuditAgreement.disagree,
      },
      confidence: switch (j['confidence']) {
        'high' => AuditConfidence.high,
        'medium' => AuditConfidence.medium,
        _ => AuditConfidence.low,
      },
      note: j['note'] as String? ?? '',
    );
  } on Object {
    return null; // a wrong type anywhere in the entry: skip just this entry
  }
}
