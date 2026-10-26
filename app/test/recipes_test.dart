import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/alcohol_import.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/sync.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<List<RecipeRow>> live() => db.watchRecipes().first;

  const mine = Recipe(
    name: 'House Punch',
    ingredients: [RecipeIngredient('2 oz', 'rum'), RecipeIngredient('4 oz', 'juice')],
    instructions: 'Stir.',
    yieldText: '1 drink',
    tags: ['punch'],
    abvPercent: 10,
  );

  group('library', () {
    test('built-ins are seeded once with stable ids and survive edits, deletes and a second call', () async {
      await db.ensureBuiltInRecipes();
      final first = await live();
      expect(first.length, builtInRecipes.length);
      expect(first.every((r) => r.id.startsWith('builtin:')), isTrue);

      final margarita = first.firstWhere((r) => r.name == 'Margarita');
      await db.updateRecipe(margarita.id, const Recipe(name: 'Margarita', instructions: 'My way.'));
      final negroni = first.firstWhere((r) => r.name == 'Negroni');
      await db.setRecipeDeleted(negroni.id, true);

      await db.ensureBuiltInRecipes(); // does nothing the second time
      final again = await live();
      expect(again.length, builtInRecipes.length - 1);
      expect(again.firstWhere((r) => r.id == margarita.id).payload, contains('My way.'));
    });

    test('adding skips an identical recipe, and importing a deleted one brings it back', () async {
      expect(await db.addRecipe(mine), isTrue);
      expect(await db.addRecipe(mine), isFalse);
      final row = (await live()).single;
      await db.setRecipeDeleted(row.id, true);
      expect(await live(), isEmpty);
      final (added, skipped) = await db.importRecipes([mine, mine.copyWith(name: 'Other')]);
      expect((added, skipped), (2, 0));
      expect((await live()).length, 2);
      expect((await live()).any((r) => r.id == row.id), isTrue); // the same row, undeleted
    });

    test('search finds built-ins by name, ingredient and base liquor', () async {
      await db.ensureBuiltInRecipes();
      final recipes = [for (final r in await live()) Recipe.fromPayload(jsonDecode(r.payload))!];
      List<String> find(String q) => [for (final r in recipes) if (recipeMatches(r, q)) r.name];
      expect(find('negroni'), contains('Negroni'));
      expect(find('campari'), contains('Negroni'));
      expect(find('tequila'), containsAll(['Margarita', 'Paloma']));
      expect(find('xyzzy'), isEmpty);
    });
  });

  group('from Alcohol Tracker', () {
    test('your own and edited recipes come across; its untouched built-ins and repeats do not', () async {
      final edited = genericRecipe('Margarita').copyWith(instructions: 'Salt the rim first.');
      final export = TrackerExport(source: 'database', drinks: const [], recipeCount: 4, recipes: [
        mine,
        edited,
        genericRecipe('Zombie'), // Alcohol Tracker's own placeholder card
        mine, // listed twice
      ]);
      await db.ensureDefaultPerson();
      final result = await importTrackerExport(db, export);
      expect(result.recipesAdded, 2);
      expect(result.recipesSkipped, 2);
      expect((await live()).map((r) => r.name).toSet(), {'House Punch', 'Margarita'});

      final again = await importTrackerExport(db, export);
      expect(again.recipesAdded, 0);
    });
  });

  test('recipes sync between devices, and the later edit wins', () async {
    var nowMs = DateTime(2026, 7, 1).millisecondsSinceEpoch;
    final a = AppDatabase.memory(deviceId: 'a', nowMillis: () => nowMs);
    final b = AppDatabase.memory(deviceId: 'b', nowMillis: () => nowMs);
    addTearDown(a.close);
    addTearDown(b.close);
    final sa = SyncService(a, deviceName: 'A');
    final sb = SyncService(b, deviceName: 'B');
    await sb.acceptPairing((await sa.offerPairing()).encode());

    await a.ensureBuiltInRecipes();
    await a.addRecipe(mine);
    nowMs += 60000;
    await sb.receivePackage(await sa.createPackage((await sa.peers()).single.deviceId, everything: true));
    expect((await b.watchRecipes().first).length, builtInRecipes.length + 1);

    final row = (await b.watchRecipes().first).firstWhere((r) => r.name == 'House Punch');
    nowMs += 60000;
    await b.updateRecipe(row.id, mine.copyWith(instructions: 'Shake instead.'));
    await sa.receivePackage(await sb.createPackage('a', everything: true));
    final onA = (await a.watchRecipes().first).firstWhere((r) => r.id == row.id);
    expect(onA.payload, contains('Shake instead.'));
  });

  group('screen', () {
    Future<TestApp> open(WidgetTester tester) async {
      final app = await buildTestApp(tester);
      await dbRun(tester, app.db.ensureDefaultPerson);
      await dbRun(tester, app.db.ensureDefaultDrinkPresets);
      await dbRun(tester, () => app.db.setSetting('alcoholMode', 'true'));
      await startApp(tester, app);
      await tester.tap(find.text('Recipes'));
      await settle(tester, rounds: 8);
      return app;
    }

    testWidgets('search narrows the list; opening a recipe shows its ingredients', (tester) async {
      final app = await open(tester);
      expect(find.textContaining('of ${builtInRecipes.length} recipes'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('recipe-search')), 'negroni');
      await settle(tester);
      expect(find.text('Negroni'), findsOneWidget);
      expect(find.text('Margarita'), findsNothing);
      await tester.tap(find.text('Negroni'));
      await settle(tester);
      expect(find.textContaining('Campari'), findsOneWidget);
      expect(find.text('Instructions'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('create a recipe, then edit it', (tester) async {
      final app = await open(tester);
      await tapKey(tester, 'add-recipe');
      await tester.enterText(find.byKey(const ValueKey('recipe-name')), 'Garden Spritz');
      await tester.enterText(find.byKey(const ValueKey('recipe-abv')), '7');
      await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '3 oz');
      await tester.enterText(find.byKey(const ValueKey('ingredient-name-0')), 'prosecco');
      await tapKey(tester, 'recipe-save');
      await settle(tester, rounds: 6);
      await tester.enterText(find.byKey(const ValueKey('recipe-search')), 'garden');
      await settle(tester);
      expect(find.text('Garden Spritz'), findsOneWidget);

      await tester.tap(find.text('Garden Spritz'));
      await settle(tester);
      await tapKey(tester, 'edit-recipe');
      await tester.enterText(find.byKey(const ValueKey('recipe-name')), 'Garden Spritz 2');
      await tapKey(tester, 'recipe-save');
      await settle(tester, rounds: 6);
      expect(find.text('Garden Spritz 2'), findsWidgets);

      final rows = await dbRun(tester, () => app.db.watchRecipes().first);
      expect(rows.where((r) => r.name == 'Garden Spritz 2'), hasLength(1));
      await disposeApp(tester, app);
    });

    testWidgets('a name is required and a bad ABV is explained', (tester) async {
      final app = await open(tester);
      await tapKey(tester, 'add-recipe');
      await tapKey(tester, 'recipe-save');
      expect(find.text('Give the recipe a name.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('recipe-name')), 'X');
      await tester.enterText(find.byKey(const ValueKey('recipe-abv')), '150');
      await tapKey(tester, 'recipe-save');
      expect(find.text('ABV must be between 0 and 100.'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('import by pasted share code adds the recipe; a bad code is explained', (tester) async {
      final app = await open(tester);
      await tapKey(tester, 'import-recipes');
      await tester.enterText(find.byKey(const ValueKey('recipe-import-field')), 'nonsense');
      await tapKey(tester, 'recipe-import-ok');
      expect(find.textContaining('valid JSON'), findsOneWidget);

      await tapKey(tester, 'import-recipes');
      await tester.enterText(find.byKey(const ValueKey('recipe-import-field')), mine.shareText);
      await tapKey(tester, 'recipe-import-ok');
      await settle(tester, rounds: 6);
      expect(find.textContaining('1 recipes added'), findsOneWidget);
      expect((await dbRun(tester, () => app.db.watchRecipes().first)).any((r) => r.name == 'House Punch'), isTrue);
      await disposeApp(tester, app);
    });
  });
}
