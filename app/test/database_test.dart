import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';

void main() {
  personAndExperienceTests();
  late AppDatabase db;
  var clock = 1000000;

  setUp(() {
    clock = 1000000;
    db = AppDatabase.memory(nowMillis: () => clock);
  });
  tearDown(() => db.close());

  Future<(Person, Experience)> personWithExperience(String name) async {
    final person = await db.addPerson(name);
    final experience = await db.addExperience(personId: person.id, sortDate: DateTime(2026, 7, 1));
    return (person, experience);
  }

  test('ids are UUIDs and every write gets a strictly increasing clock stamp', () async {
    final (alice, _) = await personWithExperience('Alice');
    expect(alice.id, matches(RegExp(r'^[0-9a-f-]{36}$')));

    final stamps = <String>[];
    for (var i = 0; i < 5; i++) {
      final (person, _) = await personWithExperience('P$i');
      stamps.add(person.hlc);
    }
    final sorted = [...stamps]..sort();
    expect(stamps, sorted);
    expect(stamps.toSet().length, stamps.length);
    expect(Hlc.parse(stamps.first).nodeId, 'test-device');
  });

  test('ingestions are scoped to one person: people never mix', () async {
    final (alice, aliceExp) = await personWithExperience('Alice');
    final (bob, bobExp) = await personWithExperience('Bob');
    await db.addIngestion(experience: aliceExp, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20), dose: 100, unit: 'µg');
    await db.addIngestion(experience: bobExp, substanceKey: 'mdma', route: 'oral', time: DateTime(2026, 7, 1, 21), dose: 100, unit: 'mg');
    await db.addIngestion(experience: bobExp, substanceKey: 'alcohol', route: 'oral', time: DateTime(2026, 7, 1, 22), dose: 20, unit: 'g');

    final aliceRows = await db.ingestionsForPerson(alice.id);
    final bobRows = await db.ingestionsForPerson(bob.id);
    expect(aliceRows.map((r) => r.substanceKey), ['lsd']);
    expect(bobRows.map((r) => r.substanceKey), ['mdma', 'alcohol']);
    expect(aliceRows.every((r) => r.personId == alice.id), isTrue);

    // Alice's compound history ignores Bob's use.
    final usage = await db.usageForPerson(alice.id);
    expect(usage.keys, ['lsd']);
  });

  test('deleting writes a tombstone that sorts after the original edit', () async {
    final (alice, exp) = await personWithExperience('Alice');
    final ing = await db.addIngestion(experience: exp, substanceKey: 'cannabis', route: 'smoked', time: DateTime(2026, 7, 1, 20));
    await db.deleteIngestion(ing.id);

    expect(await db.ingestionsForPerson(alice.id), isEmpty);
    final raw = await db.select(db.ingestions).get();
    expect(raw, hasLength(1));
    expect(raw.single.deleted, isTrue);
    expect(Hlc.parse(raw.single.hlc) > Hlc.parse(ing.hlc), isTrue);
  });

  test('usage counts and last use feed the compound picker', () async {
    final (alice, exp) = await personWithExperience('Alice');
    for (final day in [1, 2, 3]) {
      await db.addIngestion(experience: exp, substanceKey: 'cannabis', route: 'smoked', time: DateTime(2026, 7, day));
    }
    await db.addIngestion(experience: exp, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 9));

    final usage = await db.usageForPerson(alice.id);
    expect(usage['cannabis']!.count, 3);
    expect(usage['cannabis']!.lastUsed, DateTime(2026, 7, 3));
    expect(usage['lsd']!.count, 1);
  });

  test('observing a remote clock moves local stamps past it', () async {
    db.observeHlc(Hlc(clock + 5000, 3, 'remote').toString());
    final person = await db.addPerson('After sync');
    expect(Hlc.parse(person.hlc) > Hlc(clock + 5000, 3, 'remote'), isTrue);
  });

  test('settings round-trip and only shared flag marks sync eligibility', () async {
    await db.setSetting('alcoholMode', 'true');
    await db.setSetting('theme', 'dark', shared: true);
    expect(await db.getSetting('alcoholMode'), 'true');
    final rows = await db.select(db.settings).get();
    expect({for (final r in rows) r.key: r.shared}, {'alcoholMode': false, 'theme': true});
  });
}

void personAndExperienceTests() {
  late AppDatabase db;
  var clock = 5000000;

  setUp(() {
    clock = 5000000;
    db = AppDatabase.memory(nowMillis: () => clock);
  });
  tearDown(() => db.close());

  test('a fresh install gets one default person, and asking again does not add more', () async {
    final first = await db.ensureDefaultPerson();
    final second = await db.ensureDefaultPerson();
    expect(first.id, second.id);
    expect(first.isDefault, isTrue);
    expect(await db.activePeople(), hasLength(1));
  });

  test('deleting an experience tombstones its ingestions, notes and ratings, and undo restores them', () async {
    final me = await db.ensureDefaultPerson();
    final exp = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1));
    await db.addIngestion(experience: exp, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20), dose: 100);
    await db.addTimedNote(experienceId: exp.id, time: DateTime(2026, 7, 1, 21), note: 'hello');
    await db.addRating(experienceId: exp.id, time: DateTime(2026, 7, 1, 22), shulgin: 'plus2');

    await db.deleteExperience(exp.id);
    expect(await db.ingestionsForPerson(me.id), isEmpty);
    expect(await db.watchExperiences(me.id).first, isEmpty);
    expect(await db.watchTimedNotes(exp.id).first, isEmpty);
    expect(await db.watchRatings(exp.id).first, isEmpty);
    // The rows are still there as tombstones so the delete can sync.
    expect(await db.select(db.experiences).get(), hasLength(1));

    await db.setExperienceDeleted(exp.id, false);
    expect(await db.watchExperiences(me.id).first, hasLength(1));
    expect(await db.ingestionsForPerson(me.id), hasLength(1));
    expect(await db.watchTimedNotes(exp.id).first, hasLength(1));
    expect(await db.watchRatings(exp.id).first, hasLength(1));
  });

  test('deleting a person removes all of their data and nobody else\'s', () async {
    final me = await db.ensureDefaultPerson();
    final bob = await db.addPerson('Bob');
    final myExp = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1));
    final bobExp = await db.addExperience(personId: bob.id, sortDate: DateTime(2026, 7, 1));
    await db.addIngestion(experience: myExp, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20));
    await db.addIngestion(experience: bobExp, substanceKey: 'mdma', route: 'oral', time: DateTime(2026, 7, 1, 20));

    await db.deletePerson(bob.id);
    expect((await db.activePeople()).map((p) => p.name), ['Me']);
    expect(await db.ingestionsForPerson(bob.id), isEmpty);
    expect(await db.ingestionsForPerson(me.id), hasLength(1));
    await expectLater(db.deletePerson(me.id), throwsStateError);
  });

  test('editing an ingestion changes only that row and stamps a newer clock', () async {
    final me = await db.ensureDefaultPerson();
    final exp = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1));
    final a = await db.addIngestion(experience: exp, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 7, 1, 20), dose: 100);
    final b = await db.addIngestion(experience: exp, substanceKey: 'mdma', route: 'oral', time: DateTime(2026, 7, 1, 21), dose: 80);
    await db.updateIngestion(a.id, dose: const Value(120.0), notes: 'second tab');
    final rows = {for (final r in await db.ingestionsForPerson(me.id)) r.id: r};
    expect(rows[a.id]!.dose, 120);
    expect(rows[a.id]!.notes, 'second tab');
    expect(Hlc.parse(rows[a.id]!.hlc) > Hlc.parse(a.hlc), isTrue);
    expect(rows[b.id]!.dose, 80);
    expect(rows[b.id]!.hlc, b.hlc);
  });

  test('compound preferences are stored per person', () async {
    final me = await db.ensureDefaultPerson();
    final bob = await db.addPerson('Bob');
    await db.toggleFavorite(me.id, 'lsd');
    await db.setHidden(me.id, 'ketamine', true);
    expect((await db.getCompoundPrefs(me.id)).favorites, {'lsd'});
    expect((await db.getCompoundPrefs(me.id)).hidden, {'ketamine'});
    expect((await db.getCompoundPrefs(bob.id)).favorites, isEmpty);
    expect((await db.getCompoundPrefs(bob.id)).hidden, isEmpty);

    await db.toggleFavorite(me.id, 'lsd');
    await db.setHidden(me.id, 'ketamine', false);
    expect((await db.getCompoundPrefs(me.id)).favorites, isEmpty);
    expect((await db.getCompoundPrefs(me.id)).hidden, isEmpty);
  });

  test('timed notes, ratings and cannabis details are stored', () async {
    final me = await db.ensureDefaultPerson();
    final exp = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 7, 1));
    final ing = await db.addIngestion(
      experience: exp,
      substanceKey: 'cannabis',
      route: 'smoked',
      time: DateTime(2026, 7, 1, 20),
      dose: 2.7,
      unit: 'mg',
      absorbedMg: 2.7,
      method: 'joint',
      details: {'grams': 0.1, 'thcPercent': 15},
    );
    expect(ing.method, 'joint');
    expect(ing.absorbedMg, 2.7);
    expect(ing.detailsJson, '{"grams":0.1,"thcPercent":15}');

    final note = await db.addTimedNote(experienceId: exp.id, time: DateTime(2026, 7, 1, 21), note: 'peak');
    final rating = await db.addRating(experienceId: exp.id, shulgin: 'plus3', scores: {'mood': 8});
    expect(note.showOnTimeline, isTrue);
    expect(rating.scoresJson, '{"mood":8}');
    await db.deleteTimedNote(note.id);
    await db.deleteRating(rating.id);
    expect(await db.watchTimedNotes(exp.id).first, isEmpty);
    expect(await db.watchRatings(exp.id).first, isEmpty);
  });
}
