import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

void main() {
  const colada = Recipe(
    name: 'Piña Colada',
    ingredients: [RecipeIngredient('2 oz', 'white rum'), RecipeIngredient('1.5 oz', 'cream of coconut')],
    instructions: 'Blend with ice.\nServe cold.',
    yieldText: '1 cocktail',
    tags: ['cocktail', 'tiki'],
    abvPercent: 9.0,
  );

  test('the canonical JSON and fingerprint match Alcohol Tracker (Python) exactly', () {
    expect(
      canonicalJson(colada.payload()),
      r'{"abv_percent":9.0,"ingredients":[{"name":"white rum","quantity":"2 oz"},{"name":"cream of coconut","quantity":"1.5 oz"}],"instructions":"Blend with ice.\nServe cold.","name":"Pi\u00f1a Colada","tags":["cocktail","tiki"],"yield_text":"1 cocktail"}',
    );
    expect(colada.fingerprint, '243393d26f070ec7ac571e19bb83797263516949fb328861a38605adb6a4c9b5');
    const plain = Recipe(name: 'Plain', instructions: 'Mix.');
    expect(plain.fingerprint, 'f4a2c7e7aa821dc4c3cc0e902686df37f219de6da6642c1b4df4310a0a567165');
  });

  test('share text contains a readable card and a code that parses back to the same recipe', () {
    final text = colada.shareText;
    expect(text, contains('Ingredients:'));
    expect(text, contains('- 2 oz white rum'));
    final back = parseRecipes(text).single;
    expect(back.fingerprint, colada.fingerprint);
    expect(back.abvPercent, 9.0);
  });

  test('bad share codes are explained', () {
    expect(() => parseRecipes('no json here'), throwsA(isA<RecipeFormatException>()));
    expect(() => parseRecipes('{"format":"other"}'), throwsA(isA<RecipeFormatException>()));
    expect(() => parseRecipes('{"format":"alcohol-tracker-recipes","version":1,"recipes":[{"name":"x"}]}'), throwsA(isA<RecipeFormatException>()));
    expect(() => parseRecipes('{oops'), throwsA(isA<RecipeFormatException>()));
  });

  test('search matches names, tags, ingredients and the likely base liquor', () {
    const margarita = Recipe(name: 'Margarita', tags: ['cocktail'], ingredients: [RecipeIngredient('2 oz', 'base spirit')]);
    expect(recipeMatches(margarita, 'marg'), isTrue);
    expect(recipeMatches(margarita, 'tequila'), isTrue); // by name hint
    expect(recipeMatches(margarita, 'cocktail'), isTrue);
    expect(recipeMatches(margarita, 'spirit'), isTrue);
    expect(recipeMatches(margarita, 'whiskey'), isFalse);
    expect(recipeMatches(margarita, ''), isTrue);
  });

  test('the built-in library covers every Alcohol Tracker name with sensible cards', () {
    final names = [for (final r in builtInRecipes) r.name];
    expect(names.toSet().length, names.length); // no duplicate names
    expect(names.length, greaterThanOrEqualTo(100));
    for (final r in builtInRecipes) {
      expect(r.ingredients, isNotEmpty, reason: r.name);
      expect(r.instructions, isNotEmpty, reason: r.name);
      expect(r.abvPercent, allOf(greaterThanOrEqualTo(0), lessThan(45)), reason: r.name);
      expect(r.ingredients.every((i) => i.name.isNotEmpty), isTrue, reason: r.name);
    }
    for (final expected in ['Margarita', 'Old Fashioned', 'Negroni', 'Zombie', 'Fresh Horchata', 'Jagerbomb', 'Gin and Tonic']) {
      expect(names, contains(expected));
    }
    expect(builtInRecipes.where((r) => r.name == 'Margarita').single.ingredients.first.name, 'tequila blanco');
    expect(isGenericBuiltIn(genericRecipe('Zombie')), isTrue);
    expect(isGenericBuiltIn(builtInRecipes.firstWhere((r) => r.name == 'Margarita')), isFalse);
  });
}
