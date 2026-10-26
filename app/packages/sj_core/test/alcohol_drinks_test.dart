import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

DateTime _day(String iso) => DateTime.parse('${iso}T00:00:00Z');

void main() {
  final golden = jsonDecode(File('test/golden/alcohol.json').readAsStringSync()) as Map<String, dynamic>;

  group('drink sizes match Alcohol Tracker', () {
    for (final raw in (golden['drink_sizes'] as List).cast<Map<String, dynamic>>()) {
      final unit = raw['unit'] == 'fl_oz' ? 'oz' : raw['unit'] as String;
      test('${raw['amount']} ${raw['unit']} at ${raw['abv']}%', () {
        const s = EstimateSettings();
        final amount = (raw['amount'] as num).toDouble();
        final abv = (raw['abv'] as num).toDouble();
        expect(drinkFluidOunces(amount, unit), closeTo((raw['fluid_oz'] as num).toDouble(), 1e-12));
        final grams = drinkGrams(amount, unit, abv);
        expect(grams, closeTo((raw['grams'] as num).toDouble(), 1e-9));
        expect(standardDrinksFromGrams(grams, s), closeTo((raw['standard_drinks'] as num).toDouble(), 1e-9));
        // The same drink through the model's own class.
        final drink = alcoholIngestionFor(at: DateTime.utc(2026), volume: amount, volumeUnit: unit, abvPercent: abv);
        expect(drink.standardDrinks(s), closeTo((raw['standard_drinks'] as num).toDouble(), 1e-9));
      });
    }

    test('millilitres convert through fluid ounces', () {
      expect(drinkFluidOunces(355, 'ml'), closeTo(12.0, 0.01));
      expect(drinkGrams(355, 'ml', 5), closeTo(drinkGrams(12, 'oz', 5), 0.02));
    });

    test('a drink recorded only in grams gives the same standard drinks', () {
      final grams = drinkGrams(12, 'oz', 5);
      final fromGrams = alcoholIngestionFor(at: DateTime.utc(2026), grams: grams);
      final fromVolume = alcoholIngestionFor(at: DateTime.utc(2026), volume: 12, volumeUnit: 'oz', abvPercent: 5);
      expect(fromGrams.standardDrinks(const EstimateSettings()), closeTo(fromVolume.standardDrinks(const EstimateSettings()), 1e-9));
      expect(grams, closeTo(14.016, 1e-3)); // one US standard drink is 14 g
    });

    test('a shot follows the standard-drink volume setting', () {
      const s = EstimateSettings(standardDrinkVolumeOz: 1.25);
      expect(drinkFluidOunces(2, 'shots', shotOz: s.standardDrinkVolumeOz), 2.5);
    });
  });

  group('daily summaries match analytics.py', () {
    for (final raw in (golden['analytics'] as List).cast<Map<String, dynamic>>()) {
      test(raw['name'] as String, () {
        final totals = {for (final e in (raw['totals'] as List).cast<List<dynamic>>()) _day(e[0] as String): (e[1] as num).toDouble()};
        final filled = fillDailyTotals(totals, today: _day('2026-07-12'));
        final expected = {
          for (final e in (raw['filled_through_12th'] as List).cast<List<dynamic>>()) _day(e[0] as String): (e[1] as num).toDouble(),
        };
        expect(filled, expected);

        for (final r in (raw['ranges'] as List).cast<Map<String, dynamic>>()) {
          final a = _day(r['start'] as String);
          final b = _day(r['end'] as String);
          expect(averageDrinkingDays(totals, a, b), closeTo((r['drinking_days_per_week'] as num).toDouble(), 1e-12), reason: 'days $a-$b');
          expect(averageStandardDrinksPerDay(totals, a, b), closeTo((r['drinks_per_day'] as num).toDouble(), 1e-12), reason: 'drinks $a-$b');
        }
      });
    }

    test('local dates work as well as UTC ones', () {
      final totals = {DateTime(2026, 7, 1, 21): 3.0, DateTime(2026, 7, 3, 2): 1.0};
      final filled = fillDailyTotals(totals, today: DateTime(2026, 7, 4, 9));
      expect(filled.keys, [DateTime(2026, 7, 1), DateTime(2026, 7, 2), DateTime(2026, 7, 3), DateTime(2026, 7, 4)]);
      expect(filled[DateTime(2026, 7, 2)], 0);
    });
  });

  group('settings storage', () {
    test('round-trips every field', () {
      const s = EstimateSettings(
        absorptionMinutes: 30,
        absorptionLagMinutes: 10,
        eliminationStandardDrinksPerHour: 0.8,
        toleranceHalfLifeDays: 4,
        toleranceMaxExtraDose: 1.5,
        toleranceHalfSaturationExposure: 2,
        standardDrinkVolumeOz: 1.25,
        standardDrinkAbvPercent: 35,
        userWeightLbs: 180,
        userGender: 'F',
        userHeightCm: 165,
        userAgeYears: 41,
        bacModel: bacModelWidmark,
      );
      final back = estimateSettingsFromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), s.toJson());
      expect(back.bacModel, bacModelWidmark);
      expect(back.userGender, 'F');
    });

    test('missing or invalid values fall back to the defaults', () {
      final s = estimateSettingsFromJson({'userWeightLbs': 'heavy', 'bacModel': 'nonsense', 'userAgeYears': 33});
      expect(s.userWeightLbs, const EstimateSettings().userWeightLbs);
      expect(s.bacModel, bacModelWatson);
      expect(s.userAgeYears, 33);
      expect(estimateSettingsFromJson(const {}).toJson(), const EstimateSettings().toJson());
    });

    test('validation flags implausible numbers', () {
      expect(validateEstimateSettings(const EstimateSettings()), isEmpty);
      expect(validateEstimateSettings(const EstimateSettings(userWeightLbs: 10)), hasLength(1));
      expect(validateEstimateSettings(const EstimateSettings(userHeightCm: 10, userAgeYears: 5)), hasLength(2));
      expect(validateEstimateSettings(const EstimateSettings(eliminationStandardDrinksPerHour: 3)), hasLength(1));
      expect(validateEstimateSettings(const EstimateSettings(standardDrinkAbvPercent: 120)), hasLength(1));
    });
  });
}
