import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/cannabis_products.dart';
import 'package:substance_journal_app/data/database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory(deviceId: 'd'));
  tearDown(() => db.close());

  Future<void> session(String personId, Product product, DateTime at, {Map<String, int>? scores, bool alcoholToo = false}) async {
    final e = await db.addExperience(personId: personId, sortDate: at);
    await db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: at, dose: 5, unit: 'mg', productId: product.id);
    if (alcoholToo) await db.addIngestion(experience: e, substanceKey: 'alcohol', route: 'oral', time: at, dose: 14, unit: 'g');
    if (scores != null) await db.addRating(experienceId: e.id, scores: scores);
  }

  test('averages each feeling over the sessions a product was in, and flags sessions with other substances', () async {
    final me = await db.ensureDefaultPerson();
    final dream = await db.addProduct(substanceKey: 'cannabis', name: 'Blue Dream', thcPercent: 20);
    final gelato = await db.addProduct(substanceKey: 'cannabis', name: 'Gelato', thcPercent: 24);
    for (var i = 0; i < 3; i++) {
      await session(me.id, dream, DateTime(2026, 7, 1 + i, 20), scores: {'mood': 8, 'pain': 2});
      await session(me.id, gelato, DateTime(2026, 7, 10 + i, 20), scores: {'mood': 6, 'pain': 5}, alcoholToo: i == 0);
    }
    await session(me.id, dream, DateTime(2026, 7, 20, 20)); // unrated

    final ingestions = await db.ingestionsForPerson(me.id);
    final ratings = await db.watchRatingsForPerson(me.id).first;
    expect(ratings, hasLength(6));

    final d = ProductOutcomes.of(dream, ingestions, ratings);
    expect((d.experiences, d.rated, d.withOthers), (4, 3, 0));
    expect(d.averages['mood'], 8);
    final g = ProductOutcomes.of(gelato, ingestions, ratings);
    expect(g.withOthers, 1);

    final all = {dream: d, gelato: g};
    expect(bestFor('mood', all)!.product.name, 'Blue Dream');
    expect(bestFor('pain', all)!.product.name, 'Blue Dream'); // lower is better
    expect(bestFor('sleep', all), isNull); // nobody rated sleep
    expect(bestFor('mood', all, minRatings: 4), isNull); // not enough data behind it
  });

  test("another person's ratings never count", () async {
    final me = await db.ensureDefaultPerson();
    final alex = await db.addPerson('Alex');
    final p = await db.addProduct(substanceKey: 'cannabis', name: 'Gelato');
    await session(alex.id, p, DateTime(2026, 7, 1, 20), scores: {'mood': 9});
    final ratings = await db.watchRatingsForPerson(me.id).first;
    expect(ratings, isEmpty);
  });
}
