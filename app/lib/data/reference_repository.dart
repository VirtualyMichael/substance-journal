import 'package:flutter/services.dart' show rootBundle;
import 'package:sj_core/sj_core.dart';

/// Loads the bundled reference data (assets/data/*.json, copied from /data by
/// scripts/sync_app_assets.py). Reference data is read-only and never synced.
class ReferenceRepository {
  ReferenceRepository(this.substances) : byKey = {for (final s in substances) s.key: s};

  final List<Substance> substances;
  final Map<String, Substance> byKey;

  static Future<ReferenceRepository> load() async {
    final text = await rootBundle.loadString('assets/data/substances.json');
    return ReferenceRepository(parseSubstances(text));
  }
}
