import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Drink recipes, compatible with Alcohol Tracker's share codes and duplicate detection.

const String recipeFormat = 'alcohol-tracker-recipes';
const int recipeVersion = 1;

class RecipeIngredient {
  const RecipeIngredient(this.quantity, this.name);
  final String quantity;
  final String name;

  Map<String, Object?> toJson() => {'quantity': quantity, 'name': name};
}

class Recipe {
  const Recipe({
    required this.name,
    this.ingredients = const [],
    this.instructions = '',
    this.yieldText = '1 serving',
    this.tags = const [],
    this.abvPercent,
  });

  final String name;
  final List<RecipeIngredient> ingredients;
  final String instructions;
  final String yieldText;
  final List<String> tags;

  /// Strength of the finished drink, if known.
  final double? abvPercent;

  Recipe copyWith({
    String? name,
    List<RecipeIngredient>? ingredients,
    String? instructions,
    String? yieldText,
    List<String>? tags,
    double? abvPercent,
    bool clearAbv = false,
  }) =>
      Recipe(
        name: name ?? this.name,
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions ?? this.instructions,
        yieldText: yieldText ?? this.yieldText,
        tags: tags ?? this.tags,
        abvPercent: clearAbv ? null : (abvPercent ?? this.abvPercent),
      );

  /// The portable form (the same keys Alcohol Tracker writes).
  Map<String, Object?> payload() => {
        'name': name,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'instructions': instructions,
        'yield_text': yieldText,
        'tags': tags,
        'abv_percent': abvPercent,
      };

  static Recipe? fromPayload(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final ingredients = json['ingredients'];
    final instructions = json['instructions'];
    if (name is! String || ingredients is! List || instructions is! String) return null;
    return Recipe(
      name: name,
      ingredients: [
        for (final i in ingredients)
          if (i is Map) RecipeIngredient('${i['quantity'] ?? ''}', '${i['name'] ?? ''}'),
      ],
      instructions: instructions,
      yieldText: json['yield_text'] is String ? json['yield_text'] as String : '1 serving',
      tags: [for (final t in (json['tags'] as List? ?? const [])) '$t'],
      abvPercent: (json['abv_percent'] as num?)?.toDouble(),
    );
  }

  /// Same value Alcohol Tracker computes, so a recipe imported from it is recognised as a
  /// duplicate: SHA-256 of the canonical JSON, lower-cased, with whitespace collapsed.
  String get fingerprint {
    final raw = canonicalJson(payload());
    final normalised = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return sha256.convert(utf8.encode(normalised)).toString();
  }

  /// Text to send someone: a readable card followed by the share code.
  String get shareText {
    final card = StringBuffer('$name - $yieldText\nIngredients:\n');
    for (final i in ingredients) {
      card.writeln('- ${i.quantity} ${i.name}'.replaceAll('  ', ' '));
    }
    card.write('Instructions:\n$instructions\n\nAlcohol Tracker share code:\n');
    card.write(const JsonEncoder.withIndent('  ').convert(recipeDocument([this])));
    return card.toString();
  }
}

Map<String, Object?> recipeDocument(List<Recipe> recipes) =>
    {'format': recipeFormat, 'version': recipeVersion, 'recipes': [for (final r in recipes) r.payload()]};

class RecipeFormatException implements Exception {
  const RecipeFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads a share code (JSON, with or without a readable card in front of it).
List<Recipe> parseRecipes(String text) {
  final start = text.indexOf('{');
  if (start < 0) throw const RecipeFormatException('Recipe share code must contain valid JSON.');
  final Object? value;
  try {
    value = jsonDecode(text.substring(start));
  } on FormatException {
    throw const RecipeFormatException('Recipe share code must contain valid JSON.');
  }
  if (value is! Map<String, dynamic> || value['format'] != recipeFormat || value['version'] != recipeVersion || value['recipes'] is! List) {
    throw const RecipeFormatException('Unsupported recipe file.');
  }
  final result = <Recipe>[];
  for (final row in value['recipes'] as List) {
    final recipe = Recipe.fromPayload(row);
    if (recipe == null) throw const RecipeFormatException('Recipe is missing required fields.');
    result.add(recipe);
  }
  return result;
}

/// JSON with sorted keys, no spaces and non-ASCII escaped: the same text as Python's
/// `json.dumps(value, sort_keys=True, separators=(",", ":"))`.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  void write(Object? v) {
    if (v == null) {
      out.write('null');
    } else if (v is bool) {
      out.write(v ? 'true' : 'false');
    } else if (v is int) {
      out.write(v);
    } else if (v is double) {
      out.write(v == v.roundToDouble() && v.abs() < 1e16 ? v.toStringAsFixed(1) : v.toString());
    } else if (v is String) {
      out.write(_pythonString(v));
    } else if (v is List) {
      out.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) out.write(',');
        write(v[i]);
      }
      out.write(']');
    } else if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(_pythonString(keys[i]));
        out.write(':');
        write(v[keys[i]]);
      }
      out.write('}');
    } else {
      throw ArgumentError('Cannot encode ${v.runtimeType}');
    }
  }

  write(value);
  return out.toString();
}

String _pythonString(String s) {
  final out = StringBuffer('"');
  for (final unit in s.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      default:
        if (unit < 0x20 || unit > 0x7e) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Words that suggest a base liquor, so searching "tequila" finds a Margarita even when the
/// card lists a generic ingredient. Same idea as Alcohol Tracker's liquor terms.
const Map<String, String> _liquorHints = {
  'tequila': 'Margarita Paloma Tequila Sunrise Frozen Margarita Oaxaca El Diablo Ranch Water Spiked Fresh Horchata',
  'vodka': 'Moscow Mule Bloody Mary Cosmopolitan Espresso Martini White Russian Black Russian Long Island Blue Lagoon Screwdriver Cape Codder Sea Breeze Bay Breeze Lemon Drop Kamikaze Sex on the Beach Harvey Wallbanger Mudslide French Martini Chocolate Martini Apple Martini Dirty Martini Vodka Soda',
  'rum': 'Mojito Daiquiri Mai Tai Pina Colada Dark and Stormy Long Island Hurricane Zombie Painkiller Jungle Bird Cuba Libre Rum Punch Bahama Mama Blue Hawaiian Rum and Coke',
  'gin': 'Martini Negroni Tom Collins French 75 Singapore Sling Gimlet Clover Club Last Word Bramble Ramos Corpse Bees Southside Eastside Gin and Tonic Dirty Martini',
  'whiskey': 'Old Fashioned Manhattan Whiskey Sour Sazerac Mint Julep Irish Coffee Long Island Rusty Godfather Hot Toddy Penicillin Kentucky Mule Washington Green Tea Seven Jack Whiskey Highball Scotch',
  'wine': 'French 75 Aperol Spritz Bellini Mimosa Kir Rose Sangria Mulled Wine Shandy Black and Tan',
  'brandy': 'Sidecar Brandy Alexander',
  'liqueur': 'Negroni Espresso Martini White Russian Black Russian B-52 Buttery Nipple',
};

List<String> liquorTerms(Recipe recipe) {
  final name = recipe.name.toLowerCase();
  return [
    for (final e in _liquorHints.entries)
      if (e.value.split(' ').any((word) => name.contains(word.toLowerCase()))) e.key,
  ];
}

/// Whether [recipe] matches a search: name, tags, ingredient names and likely base liquor.
bool recipeMatches(Recipe recipe, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = [
    recipe.name,
    ...recipe.tags,
    ...liquorTerms(recipe),
    for (final i in recipe.ingredients) i.name,
  ].join(' ').toLowerCase();
  return haystack.contains(q);
}
