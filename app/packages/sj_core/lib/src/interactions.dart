import 'dart:convert';

import 'reference.dart';

/// How worrying a combination is. Ordered from least to most severe.
enum InteractionSeverity { lowRisk, caution, unsafe, dangerous }

/// One row of the TripSit combination chart (data/interactions.json).
class TripSitPair {
  const TripSitPair({required this.a, required this.b, required this.riskLevel, this.note});
  final String a;
  final String b;
  final String riskLevel;
  final String? note;

  bool involves(String x, String y) => (a == x && b == y) || (a == y && b == x);
}

List<TripSitPair> parseInteractions(String jsonText) => [
      for (final j in (jsonDecode(jsonText) as List).cast<Map<String, dynamic>>())
        TripSitPair(
          a: j['substance_a'] as String,
          b: j['substance_b'] as String,
          riskLevel: j['risk_level'] as String? ?? '',
          note: j['note'] as String?,
        ),
    ];

InteractionSeverity? _severityFromTripSit(String level) {
  final l = level.toLowerCase();
  if (l.startsWith('dangerous')) return InteractionSeverity.dangerous;
  if (l.startsWith('unsafe')) return InteractionSeverity.unsafe;
  if (l.startsWith('caution')) return InteractionSeverity.caution;
  if (l.startsWith('low risk')) return InteractionSeverity.lowRisk;
  return null;
}

/// PsychonautWiki lists mix substance names with class names ("Depressants", "Stimulants",
/// "Serotonin releasers"). This maps each of our substances to every name a list might use.
const Map<String, List<String>> interactionAliases = {
  'alcohol': ['Alcohol', 'Depressants'],
  'nicotine': ['Nicotine', 'Stimulants'],
  'cannabis': ['Cannabis'],
  'psilocybin_mushrooms': ['Mushrooms', 'Psilocybin mushrooms'],
  'lsd': ['LSD'],
  'dmt': ['DMT'],
  'mdma': ['MDMA', 'Stimulants', 'Serotonin releasers'],
  '2c-b': ['2C-B', '2C-x'],
  'ketamine': ['Ketamine', 'Dissociatives'],
};

Set<String> interactionNames(Substance s) =>
    {...(interactionAliases[s.key] ?? [s.name]), s.name}.map((n) => n.toLowerCase()).toSet();

class InteractionWarning {
  const InteractionWarning({
    required this.severity,
    required this.incoming,
    required this.other,
    required this.reasons,
  });

  final InteractionSeverity severity;
  final Substance incoming;
  final Substance other;

  /// Human-readable lines explaining where the warning comes from.
  final List<String> reasons;
}

/// Checks a substance about to be logged against what is already active.
///
/// Pass only ONE person's active substances: another person's use is never a reason to
/// warn. Returns at most one warning per other substance (its most severe finding),
/// worst first, and omits pairs that are only "low risk".
List<InteractionWarning> checkInteractions({
  required Substance incoming,
  required Iterable<Substance> active,
  required List<TripSitPair> pairs,
}) {
  final results = <InteractionWarning>[];
  final seen = <String>{};
  for (final other in active) {
    if (other.key == incoming.key || !seen.add(other.key)) continue;

    var severity = InteractionSeverity.lowRisk;
    final reasons = <String>[];

    void raise(InteractionSeverity s, String reason) {
      if (s.index > severity.index) severity = s;
      reasons.add(reason);
    }

    final tripsit = pairs.where((p) => p.involves(incoming.key, other.key)).firstOrNull;
    if (tripsit != null) {
      final s = _severityFromTripSit(tripsit.riskLevel);
      if (s != null && s.index > InteractionSeverity.lowRisk.index) {
        raise(s, 'TripSit: ${tripsit.riskLevel}${tripsit.note == null ? '' : '. ${tripsit.note}'}');
      }
    }

    // What each substance's own PsychonautWiki lists say about the other.
    InteractionSeverity? listTier(Substance owner, Substance target) {
      final targetNames = interactionNames(target);
      bool hit(List<String> list) => list.any((n) => targetNames.contains(n.toLowerCase()));
      if (hit(owner.dangerous)) return InteractionSeverity.dangerous;
      if (hit(owner.unsafe)) return InteractionSeverity.unsafe;
      if (hit(owner.uncertain)) return InteractionSeverity.caution;
      return null;
    }

    String tierWord(InteractionSeverity s) => switch (s) {
          InteractionSeverity.dangerous => 'dangerous',
          InteractionSeverity.unsafe => 'unsafe',
          _ => 'uncertain',
        };

    final fromIncoming = listTier(incoming, other);
    final fromOther = listTier(other, incoming);
    if (fromIncoming != null && fromIncoming == fromOther) {
      raise(fromIncoming, 'PsychonautWiki lists this combination as ${tierWord(fromIncoming)}.');
    } else {
      if (fromIncoming != null) {
        raise(fromIncoming, 'PsychonautWiki lists ${other.name} as ${tierWord(fromIncoming)} with ${incoming.name}.');
      }
      if (fromOther != null) {
        raise(fromOther, 'PsychonautWiki lists ${incoming.name} as ${tierWord(fromOther)} with ${other.name}.');
      }
    }

    if (severity.index > InteractionSeverity.lowRisk.index) {
      results.add(InteractionWarning(severity: severity, incoming: incoming, other: other, reasons: reasons));
    }
  }
  results.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return results;
}
