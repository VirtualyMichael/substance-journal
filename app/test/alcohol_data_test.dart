import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/alcohol_data.dart';
import 'package:substance_journal_app/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  final t0 = DateTime(2026, 7, 3, 20);

  group('logging drinks', () {
    test('a 12 oz 5% beer is one US standard drink, stored as grams with its details', () async {
      final me = await db.ensureDefaultPerson();
      final logged = await db.logDrink(personId: me.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5, name: 'Beer');
      final row = logged.ingestion;
      expect(row.substanceKey, 'alcohol');
      expect(row.route, 'oral');
      expect(row.unit, 'g');
      expect(row.dose, closeTo(14.016, 1e-3));
      expect(row.endTime, isNull);
      expect(standardDrinksOf(row, const EstimateSettings()), closeTo(1.0, 1e-9));
      final details = DrinkDetails.of(row);
      expect([details.name, details.volume, details.volumeUnit, details.abv], ['Beer', 12.0, 'oz', 5.0]);
      expect(describeDrink(row), 'Beer');
      expect(logged.createdExperience, isTrue);
    });

    test('drinks within 12 hours join the same experience; later ones start a new one', () async {
      final me = await db.ensureDefaultPerson();
      final first = await db.logDrink(personId: me.id, at: t0, volume: 1, volumeUnit: 'shots', abvPercent: 40);
      final second = await db.logDrink(personId: me.id, at: t0.add(const Duration(hours: 3)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      expect(second.experienceId, first.experienceId);
      expect(second.createdExperience, isFalse);
      final next = await db.logDrink(personId: me.id, at: t0.add(const Duration(hours: 3, minutes: 12 * 60 + 1)), volume: 5, volumeUnit: 'oz', abvPercent: 12);
      expect(next.experienceId, isNot(first.experienceId));
      expect(next.createdExperience, isTrue);
    });

    test("another person's recent drinks never absorb mine into their experience", () async {
      final me = await db.ensureDefaultPerson();
      final bob = await db.addPerson('Bob');
      final bobs = await db.logDrink(personId: bob.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5);
      final mine = await db.logDrink(personId: me.id, at: t0.add(const Duration(minutes: 30)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      expect(mine.experienceId, isNot(bobs.experienceId));
      expect((await db.ingestionsForPerson(me.id)).single.personId, me.id);
    });

    test('a drink back-dated before its experience pulls the experience start earlier', () async {
      final me = await db.ensureDefaultPerson();
      final first = await db.logDrink(personId: me.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5);
      await db.logDrink(personId: me.id, at: t0.subtract(const Duration(hours: 1)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      final exp = await (db.select(db.experiences)..where((t) => t.id.equals(first.experienceId))).getSingle();
      expect(exp.sortDate, t0.subtract(const Duration(hours: 1)));
    });

    test('a drink that took a while records its end time and the model sees the duration', () async {
      final me = await db.ensureDefaultPerson();
      final logged = await db.logDrink(personId: me.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5, durationMinutes: 45);
      expect(logged.ingestion.endTime, t0.add(const Duration(minutes: 45)));
      expect(alcoholDrinkFrom(logged.ingestion, const EstimateSettings()).durationMinutes, 45);
    });

    test('undo removes the drink, and the experience too if the drink started it', () async {
      final me = await db.ensureDefaultPerson();
      final first = await db.logDrink(personId: me.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5);
      final second = await db.logDrink(personId: me.id, at: t0.add(const Duration(hours: 1)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      await db.undoLoggedDrink(second);
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
      expect(await db.watchExperiences(me.id).first, hasLength(1));
      await db.undoLoggedDrink(first);
      expect(await db.ingestionsForPerson(me.id), isEmpty);
      expect(await db.watchExperiences(me.id).first, isEmpty);
    });

    test('a shot follows the standard-drink volume', () async {
      final me = await db.ensureDefaultPerson();
      final logged = await db.logDrink(personId: me.id, at: t0, volume: 2, volumeUnit: 'shots', abvPercent: 40, shotOz: 1.25);
      expect(logged.ingestion.dose, closeTo(drinkGrams(2.5, 'oz', 40), 1e-9));
    });
  });

  group('presets', () {
    test('the six starter drinks are added once', () async {
      await db.ensureDefaultDrinkPresets();
      await db.ensureDefaultDrinkPresets();
      final presets = await db.watchDrinkPresets().first;
      expect(presets, hasLength(6));
      expect(presets.map((p) => p.name), containsAll(['Shot - 40%', 'Beer - 12 oz 5%', 'Wine - 5 oz 12%']));
    });

    test('they are not re-added after the user deletes them all', () async {
      await db.ensureDefaultDrinkPresets();
      for (final p in await db.watchDrinkPresets().first) {
        await db.setDrinkPresetDeleted(p.id, true);
      }
      await db.ensureDefaultDrinkPresets();
      expect(await db.watchDrinkPresets().first, isEmpty);
    });

    test('create, edit and delete a preset', () async {
      final p = await db.addDrinkPreset(name: 'Pint', volume: 16, volumeUnit: 'oz', abvPercent: 4.5);
      expect(p.amount, 16);
      expect(p.unit, 'oz');
      await db.updateDrinkPreset(p.id, name: 'Imperial pint', volume: 20, abvPercent: 5);
      final edited = (await db.watchDrinkPresets().first).single;
      expect(edited.name, 'Imperial pint');
      expect(edited.amount, 20);
      expect(edited.detailsJson, '{"abv":5.0}');
      expect(edited.unit, 'oz'); // untouched
      await db.setDrinkPresetDeleted(p.id, true);
      expect(await db.watchDrinkPresets().first, isEmpty);
    });
  });

  group('estimate settings', () {
    test('are stored per person and default when never saved', () async {
      final me = await db.ensureDefaultPerson();
      final bob = await db.addPerson('Bob');
      expect((await db.getEstimateSettings(me.id)).toJson(), const EstimateSettings().toJson());
      await db.setEstimateSettings(bob.id, const EstimateSettings(userWeightLbs: 210, userGender: 'M', bacModel: bacModelWidmark));
      expect((await db.getEstimateSettings(bob.id)).userWeightLbs, 210);
      expect((await db.getEstimateSettings(bob.id)).bacModel, bacModelWidmark);
      expect((await db.getEstimateSettings(me.id)).userWeightLbs, const EstimateSettings().userWeightLbs);
      expect(await db.watchEstimateSettings(bob.id).first, isA<EstimateSettings>());
    });
  });

  group('summaries', () {
    test('daily standard drinks sum by calendar day', () async {
      final me = await db.ensureDefaultPerson();
      await db.logDrink(personId: me.id, at: DateTime(2026, 7, 1, 21), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      await db.logDrink(personId: me.id, at: DateTime(2026, 7, 1, 23, 30), volume: 1, volumeUnit: 'shots', abvPercent: 40);
      await db.logDrink(personId: me.id, at: DateTime(2026, 7, 2, 0, 15), volume: 5, volumeUnit: 'oz', abvPercent: 12);
      final totals = dailyStandardDrinks(await db.ingestionsForPerson(me.id), const EstimateSettings());
      expect(totals.keys, [DateTime(2026, 7, 1), DateTime(2026, 7, 2)]);
      expect(totals[DateTime(2026, 7, 1)], closeTo(2.0, 1e-9));
      expect(totals[DateTime(2026, 7, 2)], closeTo(1.0, 1e-9)); // 5 oz at 12% = 0.6 oz
    });

    test('the BAC curve rises, peaks above zero, and falls back to zero', () async {
      final me = await db.ensureDefaultPerson();
      await db.logDrink(personId: me.id, at: t0, volume: 12, volumeUnit: 'oz', abvPercent: 5);
      await db.logDrink(personId: me.id, at: t0.add(const Duration(minutes: 20)), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      final drinks = await db.ingestionsForPerson(me.id);
      final series = bacSeries(drinks, const EstimateSettings(), from: t0, to: t0.add(const Duration(hours: 8)));
      final (peakAt, peak) = peakValue(series);
      expect(peak, greaterThan(0.02));
      expect(peak, lessThan(0.1));
      expect(peakAt!.isAfter(t0), isTrue);
      expect(series.first.$2, 0);
      expect(series.last.$2, 0);
    });

    test('with no drinks there is no curve', () {
      expect(bacSeries(const [], const EstimateSettings(), from: t0, to: t0.add(const Duration(hours: 2))), isEmpty);
    });
  });
}
