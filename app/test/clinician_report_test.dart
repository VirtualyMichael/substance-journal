import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/clinician_report.dart';
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

  final now = DateTime(2026, 7, 31, 12);

  Future<ReportData> build({DateTime? from}) async => buildReportData(
        person: me,
        ingestions: await db.ingestionsForPerson(me.id),
        experiences: await db.watchExperiences(me.id).first,
        ratings: await db.watchRatingsForPerson(me.id).first,
        reference: reference,
        alcoholSettings: const EstimateSettings(),
        from: from ?? DateTime(2026, 5, 3),
        to: now,
        now: now,
      );

  Future<void> seed() async {
    Future<Experience> session(DateTime at, {String title = '', String notes = ''}) async {
      final e = await db.addExperience(personId: me.id, sortDate: at);
      if (title.isNotEmpty || notes.isNotEmpty) await db.updateExperience(e.id, title: title, notes: notes);
      return e;
    }

    final a = await session(DateTime(2026, 6, 1, 20), title: 'Festival', notes: 'Slept badly after');
    await db.addIngestion(experience: a, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 6, 1, 20), dose: 100, unit: 'µg');
    await db.addIngestion(experience: a, substanceKey: 'cannabis', route: 'smoked', time: DateTime(2026, 6, 1, 22), dose: 3, unit: 'mg');
    await db.addRating(experienceId: a.id, shulgin: 'plus2');
    final b = await session(DateTime(2026, 6, 20, 21));
    await db.addIngestion(experience: b, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 6, 20, 21), dose: 50, unit: 'µg');
    for (var i = 0; i < 4; i++) {
      await db.logDrink(personId: me.id, at: DateTime(2026, 7, 10, 19, 10 * i), volume: 12, volumeUnit: 'oz', abvPercent: 5);
    }
    // Outside the period, and deleted: neither may count.
    final old = await session(DateTime(2026, 1, 5, 20));
    await db.addIngestion(experience: old, substanceKey: 'mdma', route: 'oral', time: DateTime(2026, 1, 5, 20), dose: 100, unit: 'mg');
    final gone = await db.addIngestion(experience: b, substanceKey: 'ketamine', route: 'insufflated', time: DateTime(2026, 6, 20, 22), dose: 30, unit: 'mg');
    await db.setIngestionDeleted(gone.id, true);
  }

  test('totals, days, alcohol and sessions come out right, and out-of-range or deleted doses do not count', () async {
    await seed();
    final d = await build();
    expect(d.days, 90);
    final lsd = d.substances.firstWhere((s) => s.name == 'LSD');
    expect((lsd.doses, lsd.days.length, lsd.total), (2, 2, '150 µg'));
    expect(d.substances.map((s) => s.name), isNot(contains('MDMA')));
    expect(d.substances.map((s) => s.name), isNot(contains('Ketamine')));
    expect(d.alcoholDrinks, closeTo(4, 0.05)); // four 12 oz beers
    expect(d.alcoholDays, 1);
    expect(d.alcoholMaxDate, DateTime(2026, 7, 10));
    expect(d.alcoholPerDrinkingDay, closeTo(4, 0.05));
    expect(d.activeDays, 3); // Jun 1, Jun 20, Jul 10
    expect(d.sessions.length, 3);
    final festival = d.sessions.firstWhere((s) => s.title == 'Festival');
    expect(festival.items, ['LSD 100 µg (sublingual)', 'Cannabis 3 mg (smoked)']);
    expect(festival.rating, '++');
    expect(festival.notes, 'Slept badly after');
  });

  test('text the PDF font cannot draw becomes a question mark, and the Greek mu becomes the micro sign', () async {
    final e = await db.addExperience(personId: me.id, sortDate: DateTime(2026, 6, 1));
    await db.updateExperience(e.id, title: 'Party 🎉', notes: 'ok');
    await db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: DateTime(2026, 6, 1, 20), dose: 100, unit: 'μg');
    final d = await build();
    expect(d.sessions.single.title, 'Party ?');
    expect(d.sessions.single.items.single, 'LSD 100 µg (sublingual)');
    expect(d.substances.single.total, '100 µg');
  });

  test('the PDF is a real, multi-section document, even for an empty period', () async {
    await seed();
    final bytes = await buildReportPdf(await build());
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
    final empty = await buildReportPdf(await build(from: DateTime(2020, 1, 1)).then((d) => buildReportData(
          person: me,
          ingestions: const [],
          experiences: const [],
          ratings: const [],
          reference: reference,
          alcoholSettings: const EstimateSettings(),
          from: d.from,
          to: now,
          now: now,
        )));
    expect(ascii.decode(empty.sublist(0, 5)), '%PDF-');
  });
}
