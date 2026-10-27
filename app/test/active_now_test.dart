import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/active_now.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final reference = loadReference();
  late AppDatabase db;
  late Person me;
  setUp(() async {
    db = AppDatabase.memory(deviceId: 'd');
    me = await db.ensureDefaultPerson();
  });
  tearDown(() => db.close());

  final t0 = DateTime(2026, 7, 1, 20);
  double max(RouteOfAdministration r, String p) => r.duration(p)?.maxMinutes ?? r.duration(p)?.minMinutes ?? 0;

  Future<Ingestion> dose(String substance, String route, DateTime at, {double? amount}) async {
    final e = await db.addExperience(personId: me.id, sortDate: at);
    return db.addIngestion(experience: e, substanceKey: substance, route: route, time: at, dose: amount ?? 1, unit: 'mg');
  }

  test('walks through the phases using the longest published timings', () async {
    final roa = reference.byKey['mdma']!.roas.first;
    final onset = max(roa, 'onset'), comeup = max(roa, 'comeup'), peak = max(roa, 'peak'), offset = max(roa, 'offset');
    final i = await dose('mdma', roa.route, t0);
    List<ActiveSubstance> at(double minutes) => activeNow(ingestions: [i], reference: reference, now: t0.add(Duration(minutes: minutes.round())));

    expect(at(1).single.latest.phase, DosePhase.onset);
    expect(at(onset + 1).single.latest.phase, DosePhase.comeup);
    expect(at(onset + comeup + 1).single.latest.phase, DosePhase.peak);
    expect(at(onset + comeup + peak + 1).single.latest.phase, DosePhase.comedown);

    final d = at(1).single.latest;
    expect(d.fullEffectAt, t0.add(Duration(minutes: (onset + comeup).round())));
    expect(d.mainEffectsEndAt, t0.add(Duration(minutes: (onset + comeup + peak + offset).round())));
    expect(d.fullEffectReached, isFalse);
    expect(at(onset + comeup + 1).single.latest.fullEffectReached, isTrue);
  });

  test('lingering after-effects are followed for a while, then it drops off the list', () async {
    final roa = reference.byKey['mdma']!.roas.first;
    final core = max(roa, 'onset') + max(roa, 'comeup') + max(roa, 'peak') + max(roa, 'offset');
    final linger = max(roa, 'afterglow').clamp(0.0, maxLingerMinutes.toDouble());
    final i = await dose('mdma', roa.route, t0);
    List<ActiveSubstance> at(double m) => activeNow(ingestions: [i], reference: reference, now: t0.add(Duration(minutes: m.round())));
    if (linger > 0) {
      expect(at(core + 1).single.latest.phase, DosePhase.lingering);
      expect(at(core + linger + 5), isEmpty);
    } else {
      expect(at(core + 5), isEmpty);
    }
  });

  test('alcohol, deleted doses and doses in the future are left out', () async {
    final a = await dose('alcohol', 'oral', t0);
    final deleted = await dose('mdma', 'oral', t0);
    await db.setIngestionDeleted(deleted.id, true);
    final future = await dose('mdma', 'oral', t0.add(const Duration(hours: 3)));
    final live = (await db.ingestionsForPerson(me.id));
    expect(activeNow(ingestions: live, reference: reference, now: t0.add(const Duration(minutes: 5))), isEmpty);
    expect(a.id, isNotEmpty);
    expect(future.id, isNotEmpty);
  });

  test('two doses of one substance group together, the latest one drives the times', () async {
    final first = await dose('mdma', 'oral', t0);
    final second = await dose('mdma', 'oral', t0.add(const Duration(minutes: 90)));
    final other = await dose('lsd', 'sublingual', t0.add(const Duration(minutes: 30)));
    final list = activeNow(ingestions: [second, other, first], reference: reference, now: t0.add(const Duration(minutes: 100)));
    expect(list.length, 2);
    final mdma = list.firstWhere((a) => a.substance.key == 'mdma');
    expect(mdma.doses.map((d) => d.ingestion.id), [first.id, second.id]);
    expect(mdma.latest.ingestion.id, second.id);
    // The one that ends last is listed first.
    expect(list.first.latest.lingerEndsAt.isAfter(list.last.latest.lingerEndsAt) || list.first.latest.lingerEndsAt == list.last.latest.lingerEndsAt, isTrue);
  });

  test('a route without its own timings borrows the nearest route instead of vanishing', () async {
    final i = await dose('mdma', 'rectal', t0);
    expect(activeNow(ingestions: [i], reference: reference, now: t0.add(const Duration(minutes: 5))), isNotEmpty);
  });
}
