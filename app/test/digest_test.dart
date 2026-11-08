import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:substance_journal_app/data/digest.dart';
import 'package:substance_journal_app/data/digest_service.dart';

import 'helpers.dart';

void main() {
  testWidgets('the digest has a profile, month pages and one fact sheet per experience, small enough for a short context', (tester) async {
    final app = await buildTestApp(tester);
    final built = await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final product = await app.db.addProduct(substanceKey: 'cannabis', name: 'Blue Dream', thcPercent: 22, details: {'kind': 'flower', 'strainType': 'hybrid', 'terpenes': 'Myrcene'});
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(hours: 4)), title: 'Quiet night', locationName: 'Home');
      final start = testNow.subtract(const Duration(hours: 4));
      await app.db.addIngestion(
        experience: e,
        substanceKey: 'cannabis',
        route: 'smoked',
        time: start,
        dose: 2.7,
        unit: 'mg',
        absorbedMg: 2.7,
        productId: product.id,
        details: {'productThcMg': 27.0},
        notes: 'first bowl',
      );
      await app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: start.add(const Duration(minutes: 40)), dose: 2.7, unit: 'mg', absorbedMg: 2.7);
      await app.db.addIngestion(
        experience: e,
        substanceKey: 'alcohol',
        route: 'oral',
        time: start.add(const Duration(minutes: 20)),
        dose: 14,
        unit: 'g',
        details: {'drink': 'Beer', 'volume': 12.0, 'volumeUnit': 'oz', 'abv': 5.0},
      );
      await app.db.addTimedNote(experienceId: e.id, time: start.add(const Duration(minutes: 90)), note: 'feeling anxious, drank water');
      await app.db.addRating(experienceId: e.id, shulgin: '+', scores: {'mood': 4});
      return (
        person: me,
        experiences: await app.db.watchExperiences(me.id).first,
        ingestions: await app.db.ingestionsForPerson(me.id),
        notes: await app.db.watchTimedNotes(e.id).first,
        ratings: await app.db.watchRatings(e.id).first,
        products: await app.db.watchProducts('cannabis').first,
      );
    });

    Digest build([DigestOptions options = DigestOptions.full]) => buildDigest(
          person: built.person,
          experiences: built.experiences,
          ingestions: built.ingestions,
          notes: built.notes,
          ratings: built.ratings,
          products: built.products,
          byKey: app.reference.byKey,
          now: testNow,
          options: options,
        );

    final digest = build();
    expect(digest.files.keys, containsAll(['README.md', 'profile.md', 'index.json']));
    expect(digest.files.keys.where((k) => k.startsWith('months/')), hasLength(1));
    expect(digest.index, hasLength(1));
    final sheet = digest.files[digest.index.single.path]!;

    // Every dose, with potency, product and its own note.
    expect(sheet, contains('Quiet night'));
    expect(sheet, contains('first bowl'));
    expect(sheet, contains('Blue Dream 22% THC'));
    expect(sheet, contains('27 mg THC in what was used'));
    expect(sheet, contains('~2.7 mg absorbed'));
    // The curve, going-in tolerance, notes and ratings.
    expect(sheet, contains('## Estimated curve'));
    expect(sheet, contains('peaks about'));
    expect(sheet, contains('Alcohol: 1 standard drink;'));
    expect(sheet, contains('Overlap: '));
    expect(sheet, contains('## Going in'));
    expect(sheet, contains('feeling anxious, drank water'));
    expect(sheet, contains('mood 4'));
    // Small enough for a short window.
    for (final entry in digest.files.entries) {
      expect(entry.value.length / 4, lessThan(2000), reason: entry.key);
    }
    final index = jsonDecode(digest.files['index.json']!) as Map<String, dynamic>;
    expect((index['experiences'] as List).single['doses'], 3);
    expect(digest.files['profile.md'], contains('Cannabis: 2 doses'));

    // Leaving private details out for a cloud AI.
    final hidden = build(DigestOptions.private);
    final hiddenSheet = hidden.files[hidden.index.single.path]!;
    expect(hiddenSheet, isNot(contains('first bowl')));
    expect(hiddenSheet, isNot(contains('feeling anxious')));
    expect(hiddenSheet, isNot(contains('Home')));
    expect(hiddenSheet, contains('the person'));
    expect(hiddenSheet, contains('[omitted]'));
    // Three sizes: profile only, plus the month, plus the latest sheets.
    final small = composeSummary(digest, SummarySize.small);
    final medium = composeSummary(digest, SummarySize.medium);
    final large = composeSummary(digest, SummarySize.large);
    expect(small, contains('# Profile'));
    expect(small, isNot(contains('## Days')));
    expect(medium, contains('## Days'));
    expect(medium, isNot(contains('## Estimated curve')));
    expect(large, contains('## Estimated curve'));
    expect(estimateTokens(small), lessThan(estimateTokens(medium)));
    expect(estimateTokens(medium), lessThan(estimateTokens(large)));
    await disposeApp(tester, app);
  });

  testWidgets('the digest folder is written per person and replaced, not piled up', (tester) async {
    final app = await buildTestApp(tester);
    final root = Directory.systemTemp.createTempSync('sj_digest_');
    addTearDown(() => root.deleteSync(recursive: true));
    await dbRun(tester, () async {
      final me = await app.db.ensureDefaultPerson();
      final e = await app.db.addExperience(personId: me.id, sortDate: testNow.subtract(const Duration(hours: 2)));
      await app.db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: testNow.subtract(const Duration(hours: 2)), dose: 2.7, unit: 'mg');
      final count = await writeDigestFolder(root, app.db, app.reference.byKey, testNow);
      expect(count, greaterThan(3));
      await writeDigestFolder(root, app.db, app.reference.byKey, testNow);
    });
    final files = [for (final f in root.listSync(recursive: true)) if (f is File) p.posix.joinAll(p.split(p.relative(f.path, from: root.path)))];
    expect(files, contains('me/profile.md'));
    expect(files, contains('me/index.json'));
    expect(files.where((f) => f.startsWith('me/experiences/')), hasLength(1));
    expect(files, contains('people.json'));
    await disposeApp(tester, app);
  });
}
