import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/reagent_tests.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var nowMs = DateTime(2026, 7, 1, 12).millisecondsSinceEpoch;
  int clock() => nowMs;

  late AppDatabase db;
  setUp(() => db = AppDatabase.memory(deviceId: 'a', nowMillis: clock));
  tearDown(() => db.close());

  Future<ReagentTest> record(Product p, String reagent, String outcome, {String kind = 'reagent', DateTime? at}) => db.addReagentTest(
        productId: p.id,
        substanceKey: p.substanceKey,
        testedAt: at ?? DateTime(2026, 7, 1, 20),
        kind: kind,
        reagent: reagent,
        initialColor: kind == 'reagent' ? 'Yellow' : '',
        finalColor: kind == 'reagent' ? 'Purple' : '',
        outcome: outcome,
      );

  test('an untested sample says so; a matching test never says safe, and any warning wins', () async {
    final p = await db.addProduct(substanceKey: 'mdma', name: 'Pink pill');
    var tests = await db.watchReagentTests().first;
    expect(SampleSummary.of(tests, p.id).status, SampleStatus.untested);

    await record(p, 'Marquis', 'matched');
    tests = await db.watchReagentTests().first;
    var summary = SampleSummary.of(tests, p.id);
    expect(summary.status, SampleStatus.checked);
    expect(summary.headline, isNot(contains('safe')));
    expect(summary.caution, contains('presumptive'));

    await record(p, 'Fentanyl strip', 'positive', kind: 'strip');
    tests = await db.watchReagentTests().first;
    summary = SampleSummary.of(tests, p.id);
    expect(summary.status, SampleStatus.flagged);
    expect(summary.caution, contains('Do not take it'));
    expect(summary.tests, hasLength(2));
    expect(SampleSummary.of(tests, 'someone-elses').status, SampleStatus.untested);
  });

  test('unclear and invalid results do not reassure', () async {
    final p = await db.addProduct(substanceKey: 'lsd', name: 'Blotter');
    await record(p, 'Ehrlich', 'unclear');
    await record(p, 'Other strip', 'invalid', kind: 'strip');
    expect(SampleSummary.of(await db.watchReagentTests().first, p.id).status, SampleStatus.untested);
  });

  test('a removed test stops counting, and coming back after undo restores it', () async {
    final p = await db.addProduct(substanceKey: 'mdma', name: 'Sample');
    final bad = await record(p, 'Marquis', 'unmatched');
    expect(SampleSummary.of(await db.watchReagentTests().first, p.id).status, SampleStatus.flagged);
    await db.setReagentTestDeleted(bad.id, true);
    expect(SampleSummary.of(await db.watchReagentTests().first, p.id).status, SampleStatus.untested);
    await db.setReagentTestDeleted(bad.id, false);
    expect(SampleSummary.of(await db.watchReagentTests().first, p.id).status, SampleStatus.flagged);
  });

  test('describes a test in one line', () async {
    final p = await db.addProduct(substanceKey: 'mdma', name: 'Sample');
    expect(describeTest(await record(p, 'Marquis', 'matched')), 'Marquis: yellow, then purple (matched the chart)');
    expect(describeTest(await record(p, 'Fentanyl strip', 'negative', kind: 'strip')), 'Fentanyl strip: negative');
  });

  test('suggestions are short and never include expected colours', () {
    expect(suggestedTests('mdma'), containsAll(['Marquis', 'Mecke', "Simon's"]));
    expect(suggestedTests('lsd'), ['Ehrlich']);
    expect(suggestedTests('alcohol'), isEmpty);
    expect(suggestedTests('some_new_compound'), contains('Fentanyl strip'));
  });

  test('tests sync to another device, and a removal on one reaches the other', () async {
    final other = AppDatabase.memory(deviceId: 'b', nowMillis: clock);
    addTearDown(other.close);
    final sa = SyncService(db, deviceName: 'A', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    final sb = SyncService(other, deviceName: 'B', now: () => DateTime.fromMillisecondsSinceEpoch(nowMs));
    await sb.acceptPairing((await sa.offerPairing()).encode());

    final p = await db.addProduct(substanceKey: 'mdma', name: 'Pink pill');
    final t = await record(p, 'Marquis', 'unmatched');
    nowMs += 60000;
    await sb.receivePackage(await sa.createPackage((await sa.peers()).single.deviceId, everything: true));
    expect((await other.watchReagentTests().first).single.outcome, 'unmatched');
    expect((await other.watchSamples().first).single.name, 'Pink pill');

    nowMs += 60000;
    await other.setReagentTestDeleted(t.id, true);
    nowMs += 60000;
    await sa.receivePackage(await sb.createPackage('a', everything: true));
    expect(await db.watchReagentTests().first, isEmpty);
  });

  test('a version 4 database gains the test log when it opens, keeping what it had', () async {
    final dir = Directory.systemTemp.createTempSync('sj_migrate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    final first = AppDatabase(NativeDatabase(file), deviceId: 'old');
    final product = await first.addProduct(substanceKey: 'mdma', name: 'Kept');
    await first.close();

    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE reagent_tests');
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    final upgraded = AppDatabase(NativeDatabase(file), deviceId: 'old');
    addTearDown(upgraded.close);
    await upgraded.addReagentTest(
      productId: product.id,
      substanceKey: 'mdma',
      testedAt: DateTime(2026, 7, 1),
      kind: 'strip',
      reagent: 'Fentanyl strip',
      outcome: 'negative',
    );
    expect((await upgraded.watchReagentTests().first).single.reagent, 'Fentanyl strip');
    expect((await upgraded.watchSamples().first).single.name, 'Kept');
  });
}
