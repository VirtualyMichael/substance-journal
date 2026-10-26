import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

// Golden vectors come from Alcohol Tracker's Python code: python scripts/export_alcohol_golden.py
// Python datetimes are naive; they are parsed as UTC here so no DST rule can interfere.
DateTime _t(String iso) => DateTime.parse('${iso}Z');

EstimateSettings _settings(Map<String, dynamic> j) => EstimateSettings(
      absorptionMinutes: (j['absorption_minutes'] as num).toInt(),
      absorptionLagMinutes: (j['absorption_lag_minutes'] as num).toDouble(),
      eliminationStandardDrinksPerHour: (j['elimination_standard_drinks_per_hour'] as num).toDouble(),
      toleranceHalfLifeDays: (j['tolerance_half_life_days'] as num).toDouble(),
      toleranceMaxExtraDose: (j['tolerance_max_extra_dose'] as num).toDouble(),
      toleranceHalfSaturationExposure: (j['tolerance_half_saturation_exposure'] as num).toDouble(),
      standardDrinkVolumeOz: (j['standard_drink_volume_oz'] as num).toDouble(),
      standardDrinkAbvPercent: (j['standard_drink_abv_percent'] as num).toDouble(),
      userWeightLbs: (j['user_weight_lbs'] as num).toDouble(),
      userGender: j['user_gender'] as String,
      userHeightCm: (j['user_height_cm'] as num).toDouble(),
      userAgeYears: (j['user_age_years'] as num).toDouble(),
      bacModel: j['bac_model'] as String,
    );

const _tol = 1e-9;

void main() {
  final golden = jsonDecode(File('test/golden/alcohol.json').readAsStringSync()) as Map<String, dynamic>;
  final scenarios = golden['scenarios'] as Map<String, dynamic>;
  final body = golden['body'] as Map<String, dynamic>;
  final t0 = _t(golden['t0'] as String);

  List<AlcoholIngestion> ingestions(String scenario) => [
        for (final i in (scenarios[scenario] as List).cast<Map<String, dynamic>>())
          AlcoholIngestion(
            occurredAt: _t(i['at'] as String),
            amount: (i['amount'] as num).toDouble(),
            unit: i['unit'] as String,
            abvPercent: (i['abv'] as num).toDouble(),
            durationMinutes: (i['duration'] as num).toDouble(),
          ),
      ];

  group('body model', () {
    body.forEach((name, raw) {
      final b = raw as Map<String, dynamic>;
      final s = _settings(b['settings'] as Map<String, dynamic>);
      test('$name: body water, ratio, BAC and tolerance multiplier', () {
        expect(totalBodyWaterLitres(s), closeTo((b['total_body_water'] as num).toDouble(), _tol));
        expect(bodyWaterDistributionRatio(s), closeTo((b['distribution_ratio'] as num).toDouble(), _tol));
        (b['bac'] as Map<String, dynamic>).forEach((drinks, expected) {
          expect(estimateBac(double.parse(drinks), s), closeTo((expected as num).toDouble(), _tol), reason: 'bac $drinks');
        });
        (b['multiplier'] as Map<String, dynamic>).forEach((score, expected) {
          expect(toleranceMultiplier(double.parse(score), s), closeTo((expected as num).toDouble(), _tol),
              reason: 'multiplier $score');
        });
      });
    });
  });

  for (final raw in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
    final name = '${raw['settings']} / ${raw['scenario']}';
    final s = _settings((body[raw['settings']] as Map<String, dynamic>)['settings'] as Map<String, dynamic>);
    final items = ingestions(raw['scenario'] as String);

    group(name, () {
      test('drink sizes', () {
        final sd = (raw['standard_drinks'] as List).cast<num>();
        final grams = (raw['pure_grams'] as List).cast<num>();
        for (var i = 0; i < items.length; i++) {
          expect(items[i].standardDrinks(s), closeTo(sd[i].toDouble(), _tol));
          expect(items[i].pureAlcoholGrams(s), closeTo(grams[i].toDouble(), _tol));
        }
      });

      test('effect series matches point for point', () {
        final series = effectSeries(items, t0, s);
        final expected = (raw['effect_series'] as List).cast<List<dynamic>>();
        expect(series.length, expected.length);
        for (var i = 0; i < series.length; i++) {
          expect(series[i].$1, _t(expected[i][0] as String), reason: 'time $i');
          expect(series[i].$2, closeTo((expected[i][1] as num).toDouble(), _tol), reason: 'value $i');
        }
        final (peakAt, peak) = peakValue(series);
        final expectedPeak = raw['peak'] as List<dynamic>;
        expect(peak, closeTo((expectedPeak[1] as num).toDouble(), _tol));
        expect(peakAt, expectedPeak[0] == null ? null : _t(expectedPeak[0] as String));

        final bacSeries = [for (final (t, v) in series) (t, estimateBac(v, s))];
        final clear = estimatedClearTime(bacSeries);
        expect(clear, raw['clear_time'] == null ? null : _t(raw['clear_time'] as String));
      });

      test('active, unabsorbed and total alcohol at probe times', () {
        for (final p in (raw['probes'] as List).cast<Map<String, dynamic>>()) {
          final at = _t(p['at'] as String);
          expect(estimateActiveStandardDrinks(items, at, s), closeTo((p['active'] as num).toDouble(), _tol), reason: '${p['at']} active');
          expect(estimateUnabsorbedStandardDrinks(items, at, s), closeTo((p['unabsorbed'] as num).toDouble(), _tol),
              reason: '${p['at']} unabsorbed');
          expect(estimateAlcoholInBody(items, at, s), closeTo((p['in_body'] as num).toDouble(), _tol), reason: '${p['at']} in body');
        }
      });

      test('sessions and exposure', () {
        final sessions = groupIntoSessions(items, s);
        final expected = (raw['sessions'] as List).cast<List<dynamic>>();
        expect(sessions.length, expected.length);
        for (var i = 0; i < sessions.length; i++) {
          final indices = [for (final item in sessions[i]) items.indexOf(item)];
          expect(indices, expected[i].cast<int>(), reason: 'session $i');
        }
        final exposures = (raw['exposures'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < sessions.length; i++) {
          final e = sessionExposure(sessions[i], s);
          expect(e.start, _t(exposures[i]['start'] as String));
          expect(e.peakBac, closeTo((exposures[i]['peak_bac'] as num).toDouble(), _tol));
          expect(e.peakAt, exposures[i]['peak_at'] == null ? null : _t(exposures[i]['peak_at'] as String));
          expect(e.exposureBacHours, closeTo((exposures[i]['exposure'] as num).toDouble(), _tol));
        }
      });

      test('daily load, tolerance series and dose multiplier', () {
        final loads = dailyToleranceLoad(items, s);
        final expectedLoads = (raw['daily_load'] as List).cast<List<dynamic>>();
        expect(loads.length, expectedLoads.length);
        for (final e in expectedLoads) {
          expect(loads[_t(e[0] as String)], closeTo((e[1] as num).toDouble(), _tol), reason: 'load ${e[0]}');
        }

        final endDay = _t(raw['tolerance_end_day'] as String);
        final tol = toleranceSeries(loads, endDay, s);
        final expectedTol = (raw['tolerance_series'] as List).cast<List<dynamic>>();
        expect(tol.length, expectedTol.length);
        for (var i = 0; i < tol.length; i++) {
          expect(tol[i].$1, _t(expectedTol[i][0] as String));
          expect(tol[i].$2, closeTo((expectedTol[i][1] as num).toDouble(), _tol), reason: 'tolerance $i');
        }

        final mult = toleranceMultiplierSeries(loads, endDay, s);
        final expectedMult = (raw['multiplier_series'] as List).cast<List<dynamic>>();
        expect(mult.length, expectedMult.length);
        for (var i = 0; i < mult.length; i++) {
          expect(mult[i].$2, closeTo((expectedMult[i][1] as num).toDouble(), _tol), reason: 'multiplier $i');
        }
      });
    });
  }

  test('empty session exposure is zero', () {
    final e = sessionExposure(const []);
    expect(e.exposureBacHours, 0.0);
    expect(e.peakAt, isNull);
  });
}
