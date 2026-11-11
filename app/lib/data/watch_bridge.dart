import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:sj_core/sj_core.dart';

import '../ui/design.dart';
import '../ui/dose_text.dart';
import '../ui/quicklog/quick_log_page.dart';
import 'custom_substances.dart';
import 'database.dart';
import 'live_curve.dart';
import 'reference_repository.dart';

/// What the person allowed the watch to do. Stored on this phone only.
class WatchPrefs {
  const WatchPrefs({this.enabled = false, this.allowLog = false});

  /// Send the curve and recent doses to the watch.
  final bool enabled;

  /// Let the watch log "Same as last time" on its own, without opening the phone (so without the
  /// app's PIN). Off until the person turns it on.
  final bool allowLog;

  WatchPrefs copyWith({bool? enabled, bool? allowLog}) => WatchPrefs(enabled: enabled ?? this.enabled, allowLog: allowLog ?? this.allowLog);

  String encode() => jsonEncode({'enabled': enabled, 'allowLog': allowLog});

  static WatchPrefs decode(String? raw) {
    if (raw == null) return const WatchPrefs();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return WatchPrefs(enabled: j['enabled'] == true, allowLog: j['allowLog'] == true);
    } on Object {
      return const WatchPrefs();
    }
  }
}

extension WatchSettings on AppDatabase {
  Stream<WatchPrefs> watchWatchPrefs() => watchSetting('watch').map(WatchPrefs.decode);
  Future<WatchPrefs> getWatchPrefs() async => WatchPrefs.decode(await getSetting('watch'));
  Future<void> saveWatchPrefs(WatchPrefs p) => setSetting('watch', p.encode());
}

/// The dose "Same as last time" would log, as one line for the watch's button, or null when there
/// is nothing to repeat.
QuickItem? sameAsLastItem(List<Ingestion> ingestions, ReferenceRepository reference) =>
    recentItems(ingestions, reference, limit: 1, includeAlcohol: true).firstOrNull;

/// Everything the watch shows, as plain JSON: the live curve (null when nothing is active), the
/// last few doses, and the label of the Same-as-last-time button. Pass ONE person's ingestions.
Map<String, Object?> buildWatchSnapshot({
  required List<Ingestion> ingestions,
  required ReferenceRepository reference,
  required EstimateSettings alcoholSettings,
  required DateTime now,
  required WatchPrefs prefs,
  int recentCount = 8,
}) {
  final live = [for (final i in ingestions) if (!i.deleted) i]..sort((a, b) => b.time.compareTo(a.time));
  final same = sameAsLastItem(live, reference);
  return {
    'v': 1,
    'now': now.millisecondsSinceEpoch,
    'curve': buildLiveCurve(ingestions: live, reference: reference, alcoholSettings: alcoholSettings, now: now),
    'recent': [
      for (final i in live.take(recentCount))
        {
          'name': reference.byKey[i.substanceKey]?.name ?? i.substanceKey,
          'color': substanceColor(i.substanceKey).toARGB32(),
          'dose': describeIngestionDose(i),
          'at': i.time.millisecondsSinceEpoch,
        },
    ],
    'same': same?.title,
    'canLog': prefs.allowLog && same != null,
  };
}

/// What logging for the watch did.
class WatchLogResult {
  const WatchLogResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Logs the last dose again, for the watch. Only when the person allowed it, and never an
/// "undo" the watch cannot do, so it says exactly what was logged. [personId] is who is showing.
Future<WatchLogResult> logSameForWatch({
  required AppDatabase db,
  required ReferenceRepository reference,
  required String personId,
  required DateTime now,
}) async {
  final prefs = await db.getWatchPrefs();
  if (!prefs.allowLog) return const WatchLogResult(false, 'Logging from the watch is off. Turn it on in the app.');
  final ingestions = await db.ingestionsForPerson(personId);
  final item = sameAsLastItem(ingestions, reference);
  if (item == null) return const WatchLogResult(false, 'Nothing to repeat yet.');
  if (item.drink != null) {
    final d = item.drink!;
    final abv = ((jsonDecode(d.detailsJson) as Map<String, dynamic>)['abv'] as num?)?.toDouble() ?? 0;
    await db.logDrink(personId: personId, at: now, volume: d.amount, volumeUnit: d.unit, abvPercent: abv, name: d.name);
  } else {
    await logQuickDose(db, personId: personId, item: item, at: now);
  }
  return WatchLogResult(true, 'Logged ${item.title}');
}

/// The catalog including this device's custom compounds, for code that runs without the app's providers.
Future<ReferenceRepository> loadCatalogFor(AppDatabase db, ReferenceRepository base) async {
  final rows = await (db.select(db.customSubstances)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  return base.withCustom(
    active: [for (final r in rows) if (!r.deleted) substanceFromCustom(r)],
    archived: [for (final r in rows) if (r.deleted) substanceFromCustom(r)],
  );
}

/// The person who is showing in the app (or the first one), for code that runs without providers.
Future<Person> currentPersonFor(AppDatabase db) async {
  final people = await db.activePeople();
  final id = await db.currentPersonId();
  return people.firstWhere((p) => p.id == id, orElse: () => people.isEmpty ? throw StateError('No people') : people.first);
}
