import 'package:flutter/services.dart' show rootBundle;
import 'package:sj_core/sj_core.dart';

/// Loads the bundled reference data (assets/data/*.json, copied from /data by
/// scripts/sync_app_assets.py). Reference data is read-only and never synced.
///
/// [substances] is what the picker offers; [byKey] additionally resolves compounds that
/// are no longer offered (deleted custom compounds) so old ingestions keep their names.
class ReferenceRepository {
  ReferenceRepository(this.substances, {this.interactionPairs = const [], List<Substance> archived = const []})
      : byKey = {for (final s in [...substances, ...archived]) s.key: s};

  final List<Substance> substances;
  final Map<String, Substance> byKey;
  final List<TripSitPair> interactionPairs;

  static Future<ReferenceRepository> load() async {
    final substances = parseSubstances(await rootBundle.loadString('assets/data/substances.json'));
    final pairs = parseInteractions(await rootBundle.loadString('assets/data/interactions.json'));
    return ReferenceRepository(substances, interactionPairs: pairs);
  }

  /// This reference data plus the user's own compounds.
  ReferenceRepository withCustom({required List<Substance> active, List<Substance> archived = const []}) =>
      ReferenceRepository(
        [...substances, ...active],
        interactionPairs: interactionPairs,
        archived: archived,
      );
}
