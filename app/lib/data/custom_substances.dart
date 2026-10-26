import 'package:sj_core/sj_core.dart';

import 'database.dart';

/// Key prefix of user-defined compounds, e.g. `custom:3f2a...`.
const String customKeyPrefix = 'custom:';

bool isCustomKey(String key) => key.startsWith(customKeyPrefix);

/// Routes a custom compound can be taken by. There is no reference data for them, so the
/// user's onset and duration are applied to every route.
const List<String> customRoutes = [
  'oral',
  'sublingual',
  'buccal',
  'smoked',
  'insufflated',
  'rectal',
  'intravenous',
  'intramuscular',
  'transdermal',
];

/// Dose units offered when creating a custom compound.
const List<String> customUnitChoices = ['mg', 'µg', 'g', 'ml', 'IU', 'puffs', 'drops'];

/// Turns the user's rough timing into the same phase shape reference data uses: after the
/// onset, the remaining time splits 20% comeup, 30% peak, 50% offset.
List<DurationPhase> customDurationPhases({required int onsetMinutes, required double durationHours}) {
  final total = durationHours * 60.0;
  final onset = onsetMinutes.clamp(0, total.floor()).toDouble();
  final remaining = total - onset;
  return [
    DurationPhase('onset', onset, onset),
    DurationPhase('comeup', remaining * 0.2, remaining * 0.2),
    DurationPhase('peak', remaining * 0.3, remaining * 0.3),
    DurationPhase('offset', remaining * 0.5, remaining * 0.5),
    DurationPhase('total', total, total),
  ];
}

/// A [Substance] for a user-defined compound so every screen can treat it like a
/// reference one. No dose bands, tolerance or interaction data exist for it.
Substance substanceFromCustom(CustomSubstance row) {
  final key = '$customKeyPrefix${row.id}';
  final phases = customDurationPhases(onsetMinutes: row.onsetMinutes, durationHours: row.durationHours);
  return Substance(
    key: key,
    name: row.name,
    category: 'Custom',
    summary: row.description.isEmpty ? 'A compound you added yourself. There is no reference data for it.' : row.description,
    hasTolerance: false,
    roas: [
      for (final route in customRoutes)
        RouteOfAdministration(
          id: '$key:$route',
          substanceKey: key,
          route: route,
          unit: row.units,
          durations: phases,
        ),
    ],
    safetyNotes: const ['Custom compound: no dose bands or interaction data are available. Research it independently.'],
  );
}
