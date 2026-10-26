import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

// Golden vectors come from the Python implementation: python scripts/export_effect_golden.py
// Python datetimes are naive; they are parsed as UTC so no DST rule can interfere.
DateTime _t(String iso) => DateTime.parse('${iso}Z');

void main() {
  final golden = jsonDecode(File('test/golden/effect_curve.json').readAsStringSync()) as Map<String, dynamic>;
  final byKey = {for (final s in parseSubstances(File('../../../data/substances.json').readAsStringSync())) s.key: s};

  for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
    test('generic curve matches Python: ${c['name']} (now ${c['now_label']})', () {
      final doses = [
        for (final d in (c['doses'] as List).cast<Map<String, dynamic>>())
          CurveIngestion(
            substanceKey: d['substance'] as String,
            roaId: d['roa'] as String,
            amount: (d['amount'] as num).toDouble(),
            occurredAt: _t(d['at'] as String),
          ),
      ];
      // Route-specific models are off: Python only has the trapezoid.
      final series = sessionEffectSeries(doses, byKey, now: _t(c['now'] as String), useRouteModels: false);
      final expected = (c['series'] as List).cast<List<dynamic>>();
      expect(series.length, expected.length);
      for (var i = 0; i < series.length; i++) {
        expect(series[i].$1, _t(expected[i][0] as String), reason: 'time $i');
        expect(series[i].$2, closeTo((expected[i][1] as num).toDouble(), 1e-9), reason: 'value $i');
      }
    });
  }

  test('empty and unknown inputs give no series', () {
    expect(sessionEffectSeries(const [], byKey), isEmpty);
    final unknown = CurveIngestion(substanceKey: 'nope', roaId: 'nope:oral', amount: 1, occurredAt: DateTime.utc(2026));
    expect(sessionEffectSeries([unknown], byKey), isEmpty);
  });

  test('the golden set is not trivially flat', () {
    final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();
    final lsd = cases.firstWhere((c) => c['name'] == 'lsd' && c['now_label'] == 'during');
    final peak = (lsd['series'] as List).map((p) => (p[1] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    expect(peak, closeTo(100 / 75, 1e-9)); // dose / common-min
  });
}
