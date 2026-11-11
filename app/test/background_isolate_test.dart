import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/digest.dart';
import 'package:substance_journal_app/data/history_stats.dart';
import 'package:substance_journal_app/data/reference_repository.dart';

// Isolate.run is called directly here (offMain runs inline under tests), to prove the rows,
// reference data and results really can cross to a background isolate and back.
Future<List<SubstanceHistory>> _histories(List<Ingestion> rows, Map<String, Substance> byKey, DateTime now) =>
    Isolate.run(() => buildHistories(ingestions: rows, byKey: byKey, settings: const EstimateSettings(), now: now));

Future<Digest> _digest(Person person, List<Experience> experiences, List<Ingestion> rows, Map<String, Substance> byKey, DateTime now) => Isolate.run(
      () => buildDigest(person: person, experiences: experiences, ingestions: rows, notes: const [], ratings: const [], products: const [], byKey: byKey, now: now),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('history and digest calculations can run on a background isolate', () async {
    final reference = await ReferenceRepository.load();
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final now = DateTime(2026, 7, 3, 21);
    final me = await db.ensureDefaultPerson();
    final e = await db.addExperience(personId: me.id, sortDate: now.subtract(const Duration(hours: 2)));
    await db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: now.subtract(const Duration(hours: 2)), dose: 2.7, unit: 'mg');
    await db.addIngestion(
      experience: e,
      substanceKey: 'alcohol',
      route: 'oral',
      time: now.subtract(const Duration(hours: 1)),
      dose: 14,
      unit: 'g',
      details: {'drink': 'Beer', 'volume': 12.0, 'volumeUnit': 'oz', 'abv': 5.0},
    );
    final rows = await db.ingestionsForPerson(me.id);
    final experiences = await db.watchExperiences(me.id).first;

    final histories = await _histories(rows, reference.byKey, now);
    expect(histories.map((h) => h.key), containsAll(['cannabis', 'alcohol']));
    final digest = await _digest(me, experiences, rows, reference.byKey, now);
    expect(digest.files.keys, contains('profile.md'));
  });
}
