import 'dart:convert';

/// Plain-language detail for a compound page (`assets/data/compound_details.json`): what it is, how
/// it works, typical effects, timing and harm-reduction notes, each entry with the sources it was
/// written from. Compounds without an entry show what they always showed.

class DetailSource {
  const DetailSource({required this.name, required this.url, this.usedFor = '', this.retrieved});
  final String name;
  final String url;
  final String usedFor;
  final String? retrieved;
}

class CompoundDetail {
  const CompoundDetail({
    required this.whatItIs,
    required this.howItWorks,
    required this.effects,
    required this.timing,
    required this.harmReduction,
    required this.sources,
  });

  final String whatItIs;
  final String howItWorks;
  final List<String> effects;
  final String timing;
  final List<String> harmReduction;
  final List<DetailSource> sources;
}

/// One effect from PsychonautWiki's effect index (`assets/data/effects.json`).
class EffectInfo {
  const EffectInfo({required this.name, required this.description, required this.url});
  final String name;
  final String description;
  final String url;
}

class CompoundDetails {
  const CompoundDetails(this.byKey, {this.effects = const {}});

  final Map<String, CompoundDetail> byKey;

  /// Lower-cased effect name -> its definition.
  final Map<String, EffectInfo> effects;

  static const empty = CompoundDetails({});

  CompoundDetail? operator [](String key) => byKey[key];

  EffectInfo? effect(String name) => effects[name.toLowerCase()];

  /// Parses the details file and (optionally) the effect index. Missing or malformed input gives
  /// [empty]; a malformed entry is skipped on its own.
  static CompoundDetails tryParse(String? detailsText, {String? effectsText}) {
    final effects = <String, EffectInfo>{};
    try {
      final list = effectsText == null ? null : jsonDecode(effectsText);
      if (list is List) {
        for (final e in list) {
          if (e is Map<String, dynamic> && e['name'] is String && e['wiki_url'] is String) {
            effects[(e['name'] as String).toLowerCase()] =
                EffectInfo(name: e['name'] as String, description: e['description'] as String? ?? '', url: e['wiki_url'] as String);
          }
        }
      }
    } on FormatException {
      // no effect definitions; names still show
    }
    if (detailsText == null || detailsText.trim().isEmpty) return CompoundDetails(const {}, effects: effects);
    Object? json;
    try {
      json = jsonDecode(detailsText);
    } on FormatException {
      return CompoundDetails(const {}, effects: effects);
    }
    final compounds = json is Map<String, dynamic> ? json['compounds'] : null;
    if (compounds is! Map<String, dynamic>) return CompoundDetails(const {}, effects: effects);
    final out = <String, CompoundDetail>{};
    for (final MapEntry(:key, :value) in compounds.entries) {
      final d = _parse(value);
      if (d != null) out[key] = d;
    }
    return CompoundDetails(out, effects: effects);
  }
}

List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

CompoundDetail? _parse(Object? j) {
  if (j is! Map<String, dynamic>) return null;
  final what = j['what_it_is'];
  final how = j['how_it_works'];
  if (what is! String || how is! String) return null;
  final sources = [
    for (final s in (j['sources'] is List ? j['sources'] as List : const []))
      if (s is Map<String, dynamic> && s['name'] is String && s['url'] is String)
        DetailSource(name: s['name'] as String, url: s['url'] as String, usedFor: s['used_for'] as String? ?? '', retrieved: s['retrieved'] as String?),
  ];
  if (sources.isEmpty) return null; // nothing unsourced is shown
  return CompoundDetail(
    whatItIs: what,
    howItWorks: how,
    effects: _strings(j['effects']),
    timing: j['timing'] as String? ?? '',
    harmReduction: _strings(j['harm_reduction']),
    sources: sources,
  );
}
