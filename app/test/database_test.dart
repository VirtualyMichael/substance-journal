import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';

void main() {
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
