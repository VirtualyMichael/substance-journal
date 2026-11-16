import 'package:flutter/services.dart' show rootBundle;
import 'package:sj_core/sj_core.dart';

import 'compound_details.dart';
import 'dose_audit.dart';

/// Loads the bundled reference data (assets/data/*.json, copied from /data by
/// scripts/sync_app_assets.py). Reference data is read-only and never synced.
///
/// [substances] is what the picker offers; [byKey] additionally resolves compounds that
/// are no longer offered (deleted custom compounds) so old ingestions keep their names.
class ReferenceRepository {
  ReferenceRepository(
    this.substances, {
    this.interactionPairs = const [],
    List<Substance> archived = const [],
    this.doseAudit = DoseAudit.empty,
    this.details = CompoundDetails.empty,
  }) : byKey = {for (final s in [...substances, ...archived]) s.key: s};

  final List<Substance> substances;
  final Map<String, Substance> byKey;
  final List<TripSitPair> interactionPairs;

  /// The cross-referenced dose bands already applied to [substances], kept for showing their sources.
  final DoseAudit doseAudit;

  /// Plain-language detail (what it is, how it works, effects, timing, harm reduction) for some compounds.
  final CompoundDetails details;

  static Future<ReferenceRepository> load() async {
    final audited = parseSubstances(await rootBundle.loadString('assets/data/substances.json'));
    // The broad PsychonautWiki catalog. The audited nine win if a key ever collides.
    final extra = parseSubstances(await rootBundle.loadString('assets/data/substances_extra.json'));
    final taken = {for (final s in audited) s.key};
    final substances = [...audited, ...extra.where((s) => !taken.contains(s.key))];
    final pairs = parseInteractions(await rootBundle.loadString('assets/data/interactions.json'));
    // The dose audit and the compound details are optional: missing or unreadable, the app shows
    // the catalog as it is.
    final doseAudit = DoseAudit.tryParse(await _optional('assets/data/dose_audit.json'))..applyTo(substances);
    final details = CompoundDetails.tryParse(
      await _optional('assets/data/compound_details.json'),
      effectsText: await _optional('assets/data/effects.json'),
    );
    return ReferenceRepository(substances, interactionPairs: pairs, doseAudit: doseAudit, details: details);
  }

  static Future<String?> _optional(String asset) async {
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      return null;
    }
  }

  /// This reference data plus the user's own compounds.
  ReferenceRepository withCustom({required List<Substance> active, List<Substance> archived = const []}) =>
      ReferenceRepository(
        [...substances, ...active],
        interactionPairs: interactionPairs,
        archived: archived,
        doseAudit: doseAudit,
        details: details,
      );
}
