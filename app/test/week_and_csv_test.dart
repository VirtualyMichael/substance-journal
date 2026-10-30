import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/cannabis_products.dart';
import 'package:substance_journal_app/data/csv_export.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/weekly_summary.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory(deviceId: 'd'));
  tearDown(() => db.close());

  final now = DateTime(2026, 7, 10, 15);

  Future<Ingestion> dose(String personId, DateTime at, String key, {double d = 5, String? productId, Map<String, Object?>? details, String notes = ''}) async {
    final e = await db.addExperience(personId: personId, sortDate: at);
    return db.addIngestion(experience: e, substanceKey: key, route: 'oral', time: at, dose: d, unit: 'mg', productId: productId, details: details, notes: notes);
  }

  test('the week counts doses and days without use, compares with the week before, and prices only what has a cost', () async {
    final me = await db.ensureDefaultPerson();
    final priced = await db.addProduct(substanceKey: 'cannabis', name: 'Kush', details: const ProductDetails(costPerGram: 10).toJson());
    final free = await db.addProduct(substanceKey: 'cannabis', name: 'Gift');
    await dose(me.id, DateTime(2026, 7, 10, 9), 'cannabis', productId: priced.id, details: {'grams': 0.5, 'fractionUsed': 1.0});
    await dose(me.id, DateTime(2026, 7, 10, 20), 'cannabis', productId: free.id, details: {'grams': 1.0});
    await dose(me.id, DateTime(2026, 7, 8, 12), 'alcohol');
    await dose(me.id, DateTime(2026, 7, 4, 12), 'alcohol'); // exactly 6 days back: the first day of the window
    await dose(me.id, DateTime(2026, 7, 3, 12), 'alcohol'); // a day too early: last week
    final old = await dose(me.id, DateTime(2026, 7, 5, 12), 'lsd');
    await db.setIngestionDeleted(old.id, true); // deleted doses never count

    final rows = await db.ingestionsForPerson(me.id);
    final products = await db.watchProducts('cannabis').first;
    final w = weekSummary(ingestions: rows, products: products, now: now);
    expect(w.doses, 4);
    expect(w.daysWithUse, 3);
    expect(w.daysWithout, 4);
    expect(w.spend, 5); // 0.5 g at $10; the gift has no cost, so it adds nothing
    expect(w.bySubstance.first.key, anyOf('cannabis', 'alcohol'));
    expect((w.previousDoses, w.previousDaysWithUse), (1, 1));

    final none = weekSummary(ingestions: const [], products: products, now: now);
    expect((none.doses, none.daysWithout, none.spend), (0, 7, null)); // no cost saved is not "spent nothing"
  });

  test('the CSV has one row per dose, oldest first, quotes properly and defuses spreadsheet formulas', () async {
    final me = await db.ensureDefaultPerson();
    final product = await db.addProduct(substanceKey: 'cannabis', name: 'Blue, Dream');
    await dose(me.id, DateTime(2026, 7, 2, 21, 30), 'cannabis', d: 12.5, productId: product.id, notes: '=HYPERLINK("http://x")');
    await dose(me.id, DateTime(2026, 7, 1, 8, 5), 'caffeine', notes: 'with "milk",\nsecond line');
    final gone = await dose(me.id, DateTime(2026, 7, 3, 8), 'lsd');
    await db.setIngestionDeleted(gone.id, true);

    final csv = buildIngestionsCsv(
      ingestions: await db.ingestionsForPerson(me.id),
      experiences: await db.watchExperiences(me.id).first,
      products: await db.watchProducts('cannabis').first,
      reference: loadReference(),
    );
    final lines = csv.split('\r\n');
    expect(lines.first, csvHeader.join(','));
    expect(lines[1], startsWith('2026-07-01,08:05,'));
    expect(csv, contains('"with ""milk"",\nsecond line"'));
    expect(csv, contains('2026-07-02,21:30,'));
    expect(csv, contains(',12.5,mg,'));
    expect(csv, contains('"Blue, Dream"'));
    expect(csv, contains("\"'=HYPERLINK(\"\"http://x\"\")\""));
    expect(csv, isNot(contains('2026-07-03')));
    expect(csvBytes(csv).take(3), [0xEF, 0xBB, 0xBF]);
  });
}
