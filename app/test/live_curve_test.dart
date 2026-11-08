import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/live_curve.dart';

import 'helpers.dart';

void main() {
  testWidgets('the live curve has a line per active substance, BAC for alcohol, and nothing when idle', (tester) async {
    final app = await buildTestApp(tester);
    final rows = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(hours: 2)));
      await app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: testNow.subtract(const Duration(minutes: 40)), dose: 2.7, unit: 'mg');
      await app.db.addIngestion(
        experience: e,
        substanceKey: 'alcohol',
        route: 'oral',
        time: testNow.subtract(const Duration(minutes: 30)),
        dose: 14,
        unit: 'g',
        details: {'drink': 'Beer', 'volume': 12.0, 'volumeUnit': 'oz', 'abv': 5.0},
      );
      return app.db.ingestionsForPerson(me.id);
    });
    const settings = EstimateSettings();
    final payload = buildLiveCurve(ingestions: rows, reference: app.reference, alcoholSettings: settings, now: testNow)!;

    final lines = payload['lines'] as List;
    expect(lines.map((l) => (l as Map)['name']), containsAll(['Cannabis', 'Alcohol']));
    for (final l in lines) {
      expect((l as Map)['pts'], isNotEmpty);
      expect(l['doses'], hasLength(1));
      expect(l['color'], isA<int>());
    }
    final bac = payload['bac'] as Map;
    expect(bac['now'] as double, greaterThan(0.001));
    expect(bac['pts'], isNotEmpty);
    expect(payload['endsAt'] as int, greaterThan(testNow.millisecondsSinceEpoch));
    expect(payload['to'] as int, testNow.add(const Duration(hours: 6)).millisecondsSinceEpoch);
    expect(() => jsonEncode(payload), returnsNormally);

    // The same journal a day later: everything has worn off, so there is nothing to show.
    final later = testNow.add(const Duration(days: 2));
    expect(buildLiveCurve(ingestions: rows, reference: app.reference, alcoholSettings: settings, now: later), isNull);
    // No journal at all.
    expect(buildLiveCurve(ingestions: const [], reference: app.reference, alcoholSettings: settings, now: testNow), isNull);
    await disposeApp(tester, app);
  });
}
