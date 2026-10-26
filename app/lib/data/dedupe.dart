import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// Finding and merging duplicate entries.
///
/// Duplicates appear when two devices each imported the same history (their own random ids for
/// the same drink) and were then synced. Two doses are the same when they are for the same person,
/// compound and route at the same second with the same amount. Two doses in the SAME experience
/// are real twins (two identical drinks logged together) and are never merged; copies are the same
/// dose in DIFFERENT experiences.
///
/// Merging never loses information: the kept entry takes any note, end time, unit or detail the
/// copy had and the kept entry lacked, experiences are combined with all their doses, notes and
/// ratings, and every change can be undone.

String doseKey(String personId, String substanceKey, String route, DateTime time, double? dose) =>
    '$personId|$substanceKey|$route|${time.millisecondsSinceEpoch ~/ 1000}|${dose == null ? '' : dose.toStringAsFixed(4)}';

String noteKey(TimedNote n) => '${n.time.millisecondsSinceEpoch ~/ 1000}|${n.note.trim().toLowerCase()}';

String ratingKey(Rating r) => '${r.time == null ? '' : r.time!.millisecondsSinceEpoch ~/ 1000}|${r.shulgin ?? ''}|${r.scoresJson}';

int _experienceScore(Experience e) =>
    (e.title.isNotEmpty ? 2 : 0) + (e.notes.isNotEmpty ? 1 : 0) + (e.isFavorite ? 1 : 0) + (e.locationName != null ? 1 : 0);

/// What a cleanup would do.
class DuplicateScan {
  const DuplicateScan({
    required this.doseCopies,
    required this.experienceGroups,
    required this.deleteDoseIds,
    required this.experienceMerges,
    required this.noteCopies,
    required this.ratingCopies,
  });

  /// Doses that are copies of another dose.
  final int doseCopies;

  /// Sets of experiences that hold copies of the same doses (each set becomes one experience).
  final int experienceGroups;
  final Map<String, String> deleteDoseIds; // copy id -> the dose it is merged into
  final List<List<String>> experienceMerges; // first id in each list is the one kept
  final int noteCopies;
  final int ratingCopies;

  bool get isEmpty => doseCopies == 0 && experienceMerges.isEmpty && noteCopies == 0 && ratingCopies == 0;
}

class CleanupResult {
  const CleanupResult({required this.dosesMerged, required this.experiencesMerged, required this.notesMerged, required this.ratingsMerged});
  final int dosesMerged;
  final int experiencesMerged;
  final int notesMerged;
  final int ratingsMerged;
}

class DuplicateCleaner {
  DuplicateCleaner(this.db);

  final AppDatabase db;

  static const _undoKey = 'cleanupUndo';

  // ---- finding ----

  Future<DuplicateScan> scan() async {
    final experiences = {for (final e in await (db.select(db.experiences)..where((t) => t.deleted.equals(false))).get()) e.id: e};
    final doses = [for (final i in await (db.select(db.ingestions)..where((t) => t.deleted.equals(false))).get()) if (experiences.containsKey(i.experienceId)) i];

    final byKey = <String, List<Ingestion>>{};
    for (final i in doses) {
      byKey.putIfAbsent(doseKey(i.personId, i.substanceKey, i.route, i.time, i.dose), () => []).add(i);
    }

    final deletes = <String, String>{};
    final parent = <String, String>{};
    String find(String x) {
      var r = x;
      while (parent[r] != null && parent[r] != r) {
        r = parent[r]!;
      }
      parent[x] = r;
      return r;
    }

    void union(String a, String b) {
      parent.putIfAbsent(a, () => a);
      parent.putIfAbsent(b, () => b);
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final group in byKey.values) {
      final byExperience = <String, List<Ingestion>>{};
      for (final i in group) {
        byExperience.putIfAbsent(i.experienceId, () => []).add(i);
      }
      if (byExperience.length < 2) continue; // same experience: real twins, or just one
      final most = byExperience.values.map((l) => l.length).reduce((a, b) => a > b ? a : b);
      final candidates = [for (final e in byExperience.entries) if (e.value.length == most) e.key];
      candidates.sort((a, b) {
        final byScore = _experienceScore(experiences[b]!).compareTo(_experienceScore(experiences[a]!));
        return byScore != 0 ? byScore : a.compareTo(b);
      });
      final keeperExperience = candidates.first;
      final kept = [...byExperience[keeperExperience]!]..sort((a, b) => a.id.compareTo(b.id));
      var next = 0;
      for (final entry in byExperience.entries) {
        union(keeperExperience, entry.key);
        if (entry.key == keeperExperience) continue;
        for (final copy in entry.value) {
          deletes[copy.id] = kept[next % kept.length].id;
          next++;
        }
      }
    }

    final components = <String, List<String>>{};
    for (final id in parent.keys) {
      components.putIfAbsent(find(id), () => []).add(id);
    }
    final merges = <List<String>>[];
    for (final ids in components.values) {
      ids.sort((a, b) {
        final byScore = _experienceScore(experiences[b]!).compareTo(_experienceScore(experiences[a]!));
        return byScore != 0 ? byScore : a.compareTo(b);
      });
      if (ids.length > 1) merges.add(ids);
    }

    // Notes and ratings that are copies inside one experience, plus those that would collide once
    // experiences are merged.
    final notes = await (db.select(db.timedNotes)..where((t) => t.deleted.equals(false))).get();
    final ratings = await (db.select(db.ratings)..where((t) => t.deleted.equals(false))).get();
    String target(String experienceId) {
      for (final m in merges) {
        if (m.contains(experienceId)) return m.first;
      }
      return experienceId;
    }

    int copies<T>(Iterable<T> rows, String Function(T) experience, String Function(T) key) {
      final seen = <String>{};
      var n = 0;
      for (final r in rows) {
        if (!seen.add('${target(experience(r))}|${key(r)}')) n++;
      }
      return n;
    }

    return DuplicateScan(
      doseCopies: deletes.length,
      experienceGroups: merges.length,
      deleteDoseIds: deletes,
      experienceMerges: merges,
      noteCopies: copies<TimedNote>(notes, (n) => n.experienceId, noteKey),
      ratingCopies: copies<Rating>(ratings, (r) => r.experienceId, ratingKey),
    );
  }

  // ---- applying ----

  Future<CleanupResult> apply(DuplicateScan scan) async {
    final before = <String, List<Map<String, dynamic>>>{'ingestions': [], 'experiences': [], 'timed_notes': [], 'ratings': []};
    var doses = 0, experiencesMerged = 0, notesMerged = 0, ratingsMerged = 0;

    await db.transaction(() async {
      final dosesById = {for (final i in await db.select(db.ingestions).get()) i.id: i};

      // 1) Copies of doses: fold anything extra into the kept dose, then retire the copy.
      for (final entry in scan.deleteDoseIds.entries) {
        final copy = dosesById[entry.key];
        final keeper = dosesById[entry.value];
        if (copy == null || keeper == null || copy.deleted) continue;
        before['ingestions']!
          ..add(copy.toJson())
          ..add(keeper.toJson());
        final merged = _mergeDose(keeper, copy);
        if (merged != null) {
          await db.into(db.ingestions).insertOnConflictUpdate(merged.copyWith(hlc: db.nextHlc()));
          dosesById[keeper.id] = merged;
        }
        await (db.update(db.ingestions)..where((t) => t.id.equals(copy.id)))
            .write(IngestionsCompanion(deleted: const Value(true), hlc: Value(db.nextHlc())));
        doses++;
      }

      // 2) Experiences holding the same doses become one, with everything moved across.
      final experiences = {for (final e in await db.select(db.experiences).get()) e.id: e};
      for (final group in scan.experienceMerges) {
        final keeper = experiences[group.first];
        if (keeper == null) continue;
        var merged = keeper;
        for (final id in group.skip(1)) {
          final other = experiences[id];
          if (other == null || other.deleted) continue;
          before['experiences']!.add(other.toJson());
          merged = _mergeExperience(merged, other);
          for (final i in await (db.select(db.ingestions)..where((t) => t.experienceId.equals(id))).get()) {
            before['ingestions']!.add(i.toJson());
            await (db.update(db.ingestions)..where((t) => t.id.equals(i.id)))
                .write(IngestionsCompanion(experienceId: Value(keeper.id), hlc: Value(db.nextHlc())));
          }
          for (final n in await (db.select(db.timedNotes)..where((t) => t.experienceId.equals(id))).get()) {
            before['timed_notes']!.add(n.toJson());
            await (db.update(db.timedNotes)..where((t) => t.id.equals(n.id)))
                .write(TimedNotesCompanion(experienceId: Value(keeper.id), hlc: Value(db.nextHlc())));
          }
          for (final r in await (db.select(db.ratings)..where((t) => t.experienceId.equals(id))).get()) {
            before['ratings']!.add(r.toJson());
            await (db.update(db.ratings)..where((t) => t.id.equals(r.id)))
                .write(RatingsCompanion(experienceId: Value(keeper.id), hlc: Value(db.nextHlc())));
          }
          await (db.update(db.experiences)..where((t) => t.id.equals(id)))
              .write(ExperiencesCompanion(deleted: const Value(true), hlc: Value(db.nextHlc())));
          experiencesMerged++;
        }
        if (merged != keeper) {
          before['experiences']!.add(keeper.toJson());
          await db.into(db.experiences).insertOnConflictUpdate(merged.copyWith(hlc: db.nextHlc()));
        }
      }

      // 3) Notes and ratings that are now copies within one experience.
      final seenNotes = <String>{};
      for (final n in await (db.select(db.timedNotes)
            ..where((t) => t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()) {
        if (!seenNotes.add('${n.experienceId}|${noteKey(n)}')) {
          before['timed_notes']!.add(n.toJson());
          await (db.update(db.timedNotes)..where((t) => t.id.equals(n.id)))
              .write(TimedNotesCompanion(deleted: const Value(true), hlc: Value(db.nextHlc())));
          notesMerged++;
        }
      }
      final seenRatings = <String>{};
      for (final r in await (db.select(db.ratings)
            ..where((t) => t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()) {
        if (!seenRatings.add('${r.experienceId}|${ratingKey(r)}')) {
          before['ratings']!.add(r.toJson());
          await (db.update(db.ratings)..where((t) => t.id.equals(r.id)))
              .write(RatingsCompanion(deleted: const Value(true), hlc: Value(db.nextHlc())));
          ratingsMerged++;
        }
      }

      await db.setSetting(_undoKey, jsonEncode({'at': DateTime.now().toIso8601String(), 'rows': before}));
    });
    return CleanupResult(dosesMerged: doses, experiencesMerged: experiencesMerged, notesMerged: notesMerged, ratingsMerged: ratingsMerged);
  }

  Ingestion? _mergeDose(Ingestion keeper, Ingestion copy) {
    var changed = false;
    var notes = keeper.notes;
    if (copy.notes.trim().isNotEmpty && !keeper.notes.contains(copy.notes.trim())) {
      notes = keeper.notes.isEmpty ? copy.notes : '${keeper.notes} | ${copy.notes}';
      changed = true;
    }
    Map<String, dynamic> details(Ingestion i) {
      try {
        return jsonDecode(i.detailsJson) as Map<String, dynamic>;
      } on Object {
        return {};
      }
    }

    final mergedDetails = {...details(copy), ...details(keeper)};
    final detailsJson = jsonEncode(mergedDetails);
    if (detailsJson != keeper.detailsJson && mergedDetails.length > details(keeper).length) changed = true;
    final next = keeper.copyWith(
      notes: notes,
      endTime: Value(keeper.endTime ?? copy.endTime),
      stomachFullness: Value(keeper.stomachFullness ?? copy.stomachFullness),
      customUnitId: Value(keeper.customUnitId ?? copy.customUnitId),
      doseStdDev: Value(keeper.doseStdDev ?? copy.doseStdDev),
      absorbedMg: Value(keeper.absorbedMg ?? copy.absorbedMg),
      method: Value(keeper.method ?? copy.method),
      detailsJson: detailsJson,
    );
    if (next.endTime != keeper.endTime || next.stomachFullness != keeper.stomachFullness || next.customUnitId != keeper.customUnitId || next.doseStdDev != keeper.doseStdDev || next.absorbedMg != keeper.absorbedMg || next.method != keeper.method) {
      changed = true;
    }
    return changed ? next : null;
  }

  Experience _mergeExperience(Experience keeper, Experience other) {
    String join(String a, String b) => b.trim().isEmpty || a.contains(b.trim()) ? a : (a.isEmpty ? b : '$a\n\n$b');
    return keeper.copyWith(
      title: keeper.title.isEmpty ? other.title : keeper.title,
      notes: join(keeper.notes, other.notes),
      isFavorite: keeper.isFavorite || other.isFavorite,
      sortDate: other.sortDate.isBefore(keeper.sortDate) ? other.sortDate : keeper.sortDate,
      createdAt: other.createdAt.isBefore(keeper.createdAt) ? other.createdAt : keeper.createdAt,
      locationName: Value(keeper.locationName ?? other.locationName),
      latitude: Value(keeper.latitude ?? other.latitude),
      longitude: Value(keeper.longitude ?? other.longitude),
    );
  }

  // ---- undoing ----

  Future<bool> hasUndo() async => (await db.getSetting(_undoKey)) != null;

  /// Puts back every entry the last cleanup changed. Returns how many were restored.
  Future<int> undo() async {
    final raw = await db.getSetting(_undoKey);
    if (raw == null) return 0;
    final rows = (jsonDecode(raw) as Map<String, dynamic>)['rows'] as Map<String, dynamic>;
    var restored = 0;
    await db.transaction(() async {
      Future<void> put<T extends Table, D extends DataClass>(TableInfo<T, D> table, List<dynamic>? list, D Function(Map<String, dynamic>) from, D Function(D, String) stamp) async {
        // The oldest snapshot of each row is the state before the cleanup touched it.
        final seen = <String>{};
        for (final json in list ?? const []) {
          final id = (json as Map<String, dynamic>)['id'] as String;
          if (!seen.add(id)) continue;
          await db.into(table).insertOnConflictUpdate(stamp(from(json), db.nextHlc()) as Insertable<D>);
          restored++;
        }
      }

      await put(db.experiences, rows['experiences'], Experience.fromJson, (r, h) => r.copyWith(hlc: h));
      await put(db.ingestions, rows['ingestions'], Ingestion.fromJson, (r, h) => r.copyWith(hlc: h));
      await put(db.timedNotes, rows['timed_notes'], TimedNote.fromJson, (r, h) => r.copyWith(hlc: h));
      await put(db.ratings, rows['ratings'], Rating.fromJson, (r, h) => r.copyWith(hlc: h));
      await (db.delete(db.settings)..where((t) => t.key.equals(_undoKey))).go();
    });
    return restored;
  }
}
