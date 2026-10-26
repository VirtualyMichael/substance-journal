import 'recipes.dart';

/// The built-in recipe library. The detailed entries are the usual specs for each drink; the
/// strength is the finished drink's approximate ABV after dilution. Names with no detailed spec
/// yet keep Alcohol Tracker's generic card, which you can edit. Everything is a normal recipe
/// you can copy, edit or delete.

Recipe _r(String name, List<String> ingredients, String instructions, String yieldText, List<String> tags, double abv) => Recipe(
      name: name,
      ingredients: [
        for (final i in ingredients)
          RecipeIngredient(i.contains('|') ? i.split('|').first : '', i.contains('|') ? i.split('|').last : i),
      ],
      instructions: instructions,
      yieldText: yieldText,
      tags: tags,
      abvPercent: abv,
    );

const String _shake = 'Shake with ice until cold, then strain';
const String _stir = 'Stir with ice until very cold, then strain';

final List<Recipe> _detailed = [
  _r('Margarita', ['2 oz|tequila blanco', '1 oz|fresh lime juice', '1 oz|orange liqueur (triple sec)', 'optional|salt rim'], '$_shake over fresh ice in a salt-rimmed glass. Garnish with a lime wheel.', '1 cocktail', ['cocktail', 'tequila', 'sour'], 22),
  _r('Old Fashioned', ['2 oz|bourbon or rye', '1|sugar cube (or 1/4 oz simple syrup)', '2 dashes|Angostura bitters', '1|orange peel'], 'Muddle the sugar with the bitters and a splash of water. Add whiskey and ice, stir, and express the orange peel over the top.', '1 cocktail', ['cocktail', 'whiskey', 'stirred'], 30),
  _r('Manhattan', ['2 oz|rye whiskey', '1 oz|sweet vermouth', '2 dashes|Angostura bitters', '1|cocktail cherry'], '$_stir into a chilled coupe. Garnish with a cherry.', '1 cocktail', ['cocktail', 'whiskey', 'stirred'], 28),
  _r('Martini', ['2.5 oz|gin', '0.5 oz|dry vermouth', '1|lemon twist or olive'], '$_stir into a chilled glass. Garnish.', '1 cocktail', ['cocktail', 'gin', 'stirred'], 30),
  _r('Negroni', ['1 oz|gin', '1 oz|Campari', '1 oz|sweet vermouth', '1|orange peel'], 'Stir with ice, strain over a large ice cube, and garnish with orange peel.', '1 cocktail', ['cocktail', 'gin', 'stirred', 'bitter'], 22),
  _r('Mojito', ['2 oz|white rum', '1 oz|fresh lime juice', '0.75 oz|simple syrup', '8|mint leaves', 'top|soda water'], 'Gently muddle mint with syrup and lime. Add rum and crushed ice, stir, and top with soda.', '1 cocktail', ['cocktail', 'rum', 'long drink'], 10),
  _r('Daiquiri', ['2 oz|white rum', '1 oz|fresh lime juice', '0.75 oz|simple syrup'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'rum', 'sour'], 18),
  _r('Whiskey Sour', ['2 oz|bourbon', '0.75 oz|fresh lemon juice', '0.75 oz|simple syrup', 'optional|egg white'], '$_shake (dry shake first if using egg white) over fresh ice.', '1 cocktail', ['cocktail', 'whiskey', 'sour'], 18),
  _r('Tom Collins', ['2 oz|gin', '1 oz|fresh lemon juice', '0.5 oz|simple syrup', '3 oz|soda water'], 'Build in a tall glass over ice, stir gently, and garnish with a lemon wheel.', '1 cocktail', ['cocktail', 'gin', 'long drink'], 12),
  _r('Moscow Mule', ['2 oz|vodka', '0.5 oz|fresh lime juice', '4 oz|ginger beer'], 'Build over ice in a mug, stir, and garnish with lime.', '1 cocktail', ['cocktail', 'vodka', 'long drink'], 11),
  _r('Cosmopolitan', ['1.5 oz|citrus vodka', '1 oz|orange liqueur', '0.5 oz|fresh lime juice', '0.5 oz|cranberry juice'], '$_shake into a chilled coupe. Garnish with orange peel.', '1 cocktail', ['cocktail', 'vodka'], 20),
  _r('Espresso Martini', ['2 oz|vodka', '0.5 oz|coffee liqueur', '1 oz|fresh espresso', '0.25 oz|simple syrup'], 'Shake hard with ice and strain into a chilled coupe. Garnish with three coffee beans.', '1 cocktail', ['cocktail', 'vodka', 'coffee'], 18),
  _r('Gin and Tonic', ['2 oz|gin', '4 oz|tonic water', '1|lime wedge'], 'Build over plenty of ice in a tall glass and stir once.', '1 cocktail', ['highball', 'gin', 'long drink'], 12),
  _r('Cuba Libre', ['2 oz|rum', '4 oz|cola', '1|lime wedge'], 'Build over ice, squeezing in the lime.', '1 cocktail', ['highball', 'rum', 'long drink'], 12),
  _r('Rum and Coke', ['2 oz|rum', '4 oz|cola'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'rum', 'long drink'], 12),
  _r('Jack and Coke', ['2 oz|Tennessee whiskey', '4 oz|cola'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'whiskey', 'long drink'], 12),
  _r('Seven and Seven', ['2 oz|blended whiskey', '4 oz|lemon-lime soda'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'whiskey', 'long drink'], 12),
  _r('Scotch and Soda', ['2 oz|blended Scotch', '4 oz|soda water'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'whiskey', 'long drink'], 12),
  _r('Whiskey Highball', ['2 oz|whisky', '4 oz|soda water', '1|lemon peel'], 'Build over ice and express the peel over the top.', '1 cocktail', ['highball', 'whiskey', 'long drink'], 12),
  _r('Vodka Soda', ['2 oz|vodka', '4 oz|soda water', '1|lime wedge'], 'Build over ice and squeeze in the lime.', '1 cocktail', ['highball', 'vodka', 'long drink'], 12),
  _r('Screwdriver', ['2 oz|vodka', '4 oz|orange juice'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'vodka', 'long drink'], 13),
  _r('Cape Codder', ['1.5 oz|vodka', '4 oz|cranberry juice', '1|lime wedge'], 'Build over ice and squeeze in the lime.', '1 cocktail', ['highball', 'vodka', 'long drink'], 11),
  _r('Sea Breeze', ['1.5 oz|vodka', '3 oz|cranberry juice', '1 oz|grapefruit juice'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'vodka', 'long drink'], 11),
  _r('Bay Breeze', ['1.5 oz|vodka', '2 oz|cranberry juice', '2 oz|pineapple juice'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'vodka', 'long drink'], 11),
  _r('Aperol Spritz', ['3 oz|prosecco', '2 oz|Aperol', '1 oz|soda water', '1|orange slice'], 'Build over ice in a wine glass, prosecco first, then Aperol and soda.', '1 cocktail', ['cocktail', 'wine', 'spritz', 'bitter'], 9),
  _r('Mimosa', ['3 oz|sparkling wine', '3 oz|orange juice'], 'Pour chilled sparkling wine into a flute, then the juice.', '1 cocktail', ['cocktail', 'wine', 'brunch'], 6),
  _r('Bellini', ['4 oz|prosecco', '2 oz|white peach purée'], 'Spoon the purée into a flute and top with prosecco.', '1 cocktail', ['cocktail', 'wine', 'brunch'], 7),
  _r('Kir Royale', ['0.5 oz|crème de cassis', '4.5 oz|champagne'], 'Pour the cassis into a flute and top with champagne.', '1 cocktail', ['cocktail', 'wine'], 11),
  _r('Paloma', ['2 oz|tequila blanco', '0.5 oz|fresh lime juice', '3 oz|grapefruit soda', 'pinch|salt'], 'Build over ice in a salt-rimmed glass.', '1 cocktail', ['cocktail', 'tequila', 'long drink'], 13),
  _r('Ranch Water', ['2 oz|tequila blanco', '0.5 oz|fresh lime juice', '4 oz|sparkling mineral water'], 'Build over ice in a tall glass.', '1 cocktail', ['highball', 'tequila', 'long drink'], 11),
  _r('Tequila Sunrise', ['2 oz|tequila', '4 oz|orange juice', '0.5 oz|grenadine'], 'Build tequila and juice over ice, then pour the grenadine down the side so it sinks.', '1 cocktail', ['cocktail', 'tequila', 'long drink'], 11),
  _r('Dark and Stormy', ['2 oz|dark rum', '4 oz|ginger beer', '0.5 oz|fresh lime juice'], 'Build over ice with the rum floated on top.', '1 cocktail', ['cocktail', 'rum', 'long drink'], 12),
  _r('Pina Colada', ['2 oz|white rum', '1.5 oz|cream of coconut', '3 oz|pineapple juice'], 'Blend with a cup of ice until smooth.', '1 cocktail', ['cocktail', 'rum', 'frozen'], 9),
  _r('Mai Tai', ['2 oz|aged rum', '0.75 oz|fresh lime juice', '0.5 oz|orange curaçao', '0.5 oz|orgeat'], '$_shake over crushed ice. Garnish with mint.', '1 cocktail', ['cocktail', 'rum', 'tiki'], 17),
  _r('Sidecar', ['2 oz|cognac', '0.75 oz|orange liqueur', '0.75 oz|fresh lemon juice'], '$_shake into a chilled coupe, optional sugar rim.', '1 cocktail', ['cocktail', 'brandy', 'sour'], 22),
  _r('French 75', ['1 oz|gin', '0.5 oz|fresh lemon juice', '0.5 oz|simple syrup', '3 oz|champagne'], 'Shake the first three with ice, strain into a flute, and top with champagne.', '1 cocktail', ['cocktail', 'gin', 'wine'], 12),
  _r('Sazerac', ['2 oz|rye whiskey', '1|sugar cube', '3 dashes|Peychaud\'s bitters', 'rinse|absinthe', '1|lemon peel'], 'Rinse a chilled glass with absinthe. Stir the whiskey, sugar and bitters with ice, strain into the glass, and express the peel.', '1 cocktail', ['cocktail', 'whiskey', 'stirred'], 30),
  _r('Mint Julep', ['2.5 oz|bourbon', '0.25 oz|simple syrup', '8|mint leaves', 'lots|crushed ice'], 'Gently press mint with syrup in a cup, add bourbon and crushed ice, and stir until the cup frosts.', '1 cocktail', ['cocktail', 'whiskey'], 22),
  _r('White Russian', ['2 oz|vodka', '1 oz|coffee liqueur', '1 oz|cream'], 'Build vodka and liqueur over ice, then float the cream.', '1 cocktail', ['cocktail', 'vodka', 'creamy'], 20),
  _r('Black Russian', ['2 oz|vodka', '1 oz|coffee liqueur'], 'Build over ice and stir.', '1 cocktail', ['cocktail', 'vodka'], 25),
  _r('Long Island Iced Tea', ['0.5 oz|vodka', '0.5 oz|gin', '0.5 oz|white rum', '0.5 oz|tequila', '0.5 oz|orange liqueur', '1 oz|lemon juice', '1 oz|simple syrup', 'top|cola'], 'Build over ice, stir, and top with a splash of cola.', '1 cocktail', ['cocktail', 'long drink', 'strong'], 13),
  _r('Gimlet', ['2 oz|gin', '0.75 oz|lime cordial (or lime juice and syrup)'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'gin', 'sour'], 20),
  _r('Caipirinha', ['2 oz|cachaça', '1|lime, cut in wedges', '2 tsp|sugar'], 'Muddle lime with sugar, add cachaça and crushed ice, and stir.', '1 cocktail', ['cocktail', 'cachaça', 'sour'], 20),
  _r('Pisco Sour', ['2 oz|pisco', '1 oz|fresh lime juice', '0.75 oz|simple syrup', '1|egg white', '3 drops|Angostura bitters'], 'Dry shake, then shake with ice and strain. Dot the foam with bitters.', '1 cocktail', ['cocktail', 'pisco', 'sour'], 17),
  _r('Clover Club', ['2 oz|gin', '0.5 oz|fresh lemon juice', '0.5 oz|raspberry syrup', '1|egg white'], 'Dry shake, then shake with ice and strain into a coupe.', '1 cocktail', ['cocktail', 'gin', 'sour'], 18),
  _r('Last Word', ['0.75 oz|gin', '0.75 oz|green Chartreuse', '0.75 oz|maraschino liqueur', '0.75 oz|fresh lime juice'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'gin', 'sour', 'strong'], 24),
  _r('Paper Plane', ['0.75 oz|bourbon', '0.75 oz|Aperol', '0.75 oz|Amaro Nonino', '0.75 oz|fresh lemon juice'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'whiskey', 'bitter'], 17),
  _r('Boulevardier', ['1.25 oz|bourbon', '1 oz|Campari', '1 oz|sweet vermouth'], 'Stir with ice and strain over a large cube. Garnish with orange peel.', '1 cocktail', ['cocktail', 'whiskey', 'stirred', 'bitter'], 23),
  _r('Bloody Mary', ['2 oz|vodka', '4 oz|tomato juice', '0.5 oz|lemon juice', 'dashes|Worcestershire and hot sauce', 'pinch|celery salt and pepper'], 'Roll between two glasses with ice. Garnish with celery.', '1 cocktail', ['cocktail', 'vodka', 'savory', 'brunch'], 11),
  _r('Hot Toddy', ['1.5 oz|whiskey', '0.5 oz|honey', '0.5 oz|fresh lemon juice', '4 oz|hot water', '1|cinnamon stick'], 'Stir honey into the hot water, add whiskey and lemon, and garnish with the cinnamon.', '1 cocktail', ['cocktail', 'whiskey', 'hot'], 10),
  _r('Irish Coffee', ['1.5 oz|Irish whiskey', '1 tsp|brown sugar', '5 oz|hot coffee', 'float|lightly whipped cream'], 'Stir whiskey and sugar into the coffee, then float the cream over the back of a spoon.', '1 cocktail', ['cocktail', 'whiskey', 'hot', 'coffee'], 8),
  _r('Sangria', ['1 bottle (750 ml)|red wine', '1/4 cup|brandy', '1/4 cup|orange liqueur', '1 cup|orange juice', 'sliced|orange, apple and lemon'], 'Combine in a pitcher and chill for at least two hours. Serve over ice.', '6 servings', ['wine', 'batch'], 9),
  _r('Mulled Wine', ['1 bottle (750 ml)|red wine', '1|orange, sliced', '2|cinnamon sticks', '4|cloves', '2 tbsp|honey'], 'Warm gently without boiling for 15 to 20 minutes. Strain and serve hot.', '5 servings', ['wine', 'hot', 'batch'], 11),
  _r('Michelada', ['12 oz|light beer', '1 oz|fresh lime juice', 'dashes|hot sauce and Worcestershire', 'rim|chili-lime salt'], 'Rim a glass, add ice and the mixers, and top with beer.', '1 serving', ['beer', 'savory'], 4),
  _r('Shandy', ['6 oz|lager', '6 oz|lemonade'], 'Pour both over ice or chilled.', '1 serving', ['beer', 'long drink'], 2.5),
  _r('Black and Tan', ['6 oz|pale ale', '6 oz|stout'], 'Fill half a glass with pale ale, then pour the stout over the back of a spoon so it floats.', '1 serving', ['beer'], 5),
  _r('Bramble', ['2 oz|gin', '1 oz|fresh lemon juice', '0.5 oz|simple syrup', '0.5 oz|blackberry liqueur'], 'Shake the first three over crushed ice, then drizzle the liqueur over the top.', '1 cocktail', ['cocktail', 'gin', 'sour'], 18),
  _r('Jungle Bird', ['1.5 oz|dark rum', '0.75 oz|Campari', '1.5 oz|pineapple juice', '0.5 oz|fresh lime juice', '0.5 oz|simple syrup'], '$_shake over fresh ice.', '1 cocktail', ['cocktail', 'rum', 'tiki', 'bitter'], 15),
  _r('Amaretto Sour', ['2 oz|amaretto', '1 oz|fresh lemon juice', 'optional|egg white'], '$_shake (dry shake first with egg white) over fresh ice.', '1 cocktail', ['cocktail', 'liqueur', 'sour'], 13),
  _r('Brandy Alexander', ['1 oz|cognac', '1 oz|dark crème de cacao', '1 oz|cream', 'grate|nutmeg'], 'Shake with ice, strain into a coupe, and grate nutmeg on top.', '1 cocktail', ['cocktail', 'brandy', 'creamy'], 16),
  _r('Grasshopper', ['1 oz|green crème de menthe', '1 oz|white crème de cacao', '1 oz|cream'], 'Shake with ice and strain into a chilled coupe.', '1 cocktail', ['cocktail', 'liqueur', 'creamy'], 13),
  _r('Rusty Nail', ['1.5 oz|Scotch', '0.75 oz|Drambuie'], 'Build over ice and stir.', '1 cocktail', ['cocktail', 'whiskey'], 28),
  _r('Godfather', ['2 oz|Scotch', '0.5 oz|amaretto'], 'Build over ice and stir.', '1 cocktail', ['cocktail', 'whiskey'], 30),
  _r('Penicillin', ['2 oz|blended Scotch', '0.75 oz|fresh lemon juice', '0.75 oz|honey-ginger syrup', 'float|peaty Scotch'], 'Shake the first three with ice, strain over a large cube, and float the peaty Scotch.', '1 cocktail', ['cocktail', 'whiskey', 'sour'], 20),
  _r('Bees Knees', ['2 oz|gin', '0.75 oz|fresh lemon juice', '0.75 oz|honey syrup'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'gin', 'sour'], 19),
  _r('Corpse Reviver', ['0.75 oz|gin', '0.75 oz|orange liqueur', '0.75 oz|Lillet Blanc', '0.75 oz|fresh lemon juice', 'rinse|absinthe'], 'Shake with ice and strain into an absinthe-rinsed coupe.', '1 cocktail', ['cocktail', 'gin', 'sour'], 18),
  _r('Dirty Martini', ['2.5 oz|vodka or gin', '0.5 oz|dry vermouth', '0.5 oz|olive brine', '3|olives'], '$_stir (or shake) into a chilled glass. Garnish with olives.', '1 cocktail', ['cocktail', 'vodka', 'stirred'], 29),
  _r('Apple Martini', ['2 oz|vodka', '1 oz|sour apple liqueur', '0.5 oz|fresh lime juice'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'vodka'], 22),
  _r('Chocolate Martini', ['2 oz|vodka', '1 oz|chocolate liqueur', '0.5 oz|cream'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'vodka', 'creamy'], 22),
  _r('French Martini', ['1.5 oz|vodka', '0.5 oz|raspberry liqueur', '1.5 oz|pineapple juice'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'vodka'], 15),
  _r('Lemon Drop', ['2 oz|vodka', '0.75 oz|fresh lemon juice', '0.5 oz|orange liqueur', '0.5 oz|simple syrup'], '$_shake into a sugar-rimmed coupe.', '1 cocktail', ['cocktail', 'vodka', 'sour'], 20),
  _r('Kamikaze', ['1 oz|vodka', '1 oz|orange liqueur', '1 oz|fresh lime juice'], '$_shake into a glass or shot glasses.', '1 cocktail', ['cocktail', 'vodka', 'sour'], 18),
  _r('Sex on the Beach', ['1.5 oz|vodka', '0.5 oz|peach schnapps', '2 oz|orange juice', '2 oz|cranberry juice'], 'Build over ice in a tall glass.', '1 cocktail', ['cocktail', 'vodka', 'long drink'], 10),
  _r('Harvey Wallbanger', ['1.5 oz|vodka', '4 oz|orange juice', '0.5 oz|Galliano'], 'Build the vodka and juice over ice and float the Galliano.', '1 cocktail', ['cocktail', 'vodka', 'long drink'], 11),
  _r('Fuzzy Navel', ['1.5 oz|peach schnapps', '4 oz|orange juice'], 'Build over ice in a tall glass.', '1 cocktail', ['cocktail', 'long drink'], 5),
  _r('Mudslide', ['1 oz|vodka', '1 oz|coffee liqueur', '1 oz|Irish cream', '2 oz|cream or ice cream'], 'Blend with ice or shake and strain.', '1 cocktail', ['cocktail', 'creamy', 'dessert'], 14),
  _r('Blue Lagoon', ['1 oz|vodka', '1 oz|blue curaçao', '4 oz|lemonade'], 'Build over ice in a tall glass.', '1 cocktail', ['cocktail', 'vodka', 'long drink'], 10),
  _r('Blue Hawaiian', ['1 oz|rum', '1 oz|blue curaçao', '3 oz|pineapple juice', '1 oz|cream of coconut'], 'Blend with ice or shake and strain.', '1 cocktail', ['cocktail', 'rum', 'tiki'], 9),
  _r('Hurricane', ['2 oz|light rum', '2 oz|dark rum', '2 oz|passion fruit juice', '1 oz|orange juice', '0.5 oz|fresh lime juice', '0.5 oz|grenadine'], '$_shake over fresh ice.', '1 cocktail', ['cocktail', 'rum', 'tiki'], 16),
  _r('Painkiller', ['2 oz|dark rum', '4 oz|pineapple juice', '1 oz|orange juice', '1 oz|cream of coconut'], 'Shake with ice, strain over crushed ice, and grate nutmeg on top.', '1 cocktail', ['cocktail', 'rum', 'tiki'], 10),
  _r('Singapore Sling', ['1.5 oz|gin', '0.5 oz|cherry liqueur', '0.25 oz|orange liqueur', '0.25 oz|Bénédictine', '4 oz|pineapple juice', '0.5 oz|lime juice', 'dash|bitters'], 'Shake with ice and strain over fresh ice.', '1 cocktail', ['cocktail', 'gin', 'tiki'], 10),
  _r('Vesper', ['3 oz|gin', '1 oz|vodka', '0.5 oz|Lillet Blanc', '1|lemon peel'], '$_stir (or shake) into a chilled coupe and garnish with the peel.', '1 cocktail', ['cocktail', 'gin', 'stirred', 'strong'], 33),
  _r('Kentucky Mule', ['2 oz|bourbon', '0.5 oz|fresh lime juice', '4 oz|ginger beer'], 'Build over ice in a mug and stir.', '1 cocktail', ['cocktail', 'whiskey', 'long drink'], 12),
  _r('Jagerbomb', ['1.5 oz|Jägermeister', '4 oz|energy drink'], 'Drop the shot into the glass of energy drink and drink immediately.', '1 serving', ['shot'], 9),
  _r('B-52', ['0.5 oz|coffee liqueur', '0.5 oz|Irish cream', '0.5 oz|orange liqueur'], 'Layer in a shot glass in that order, pouring over the back of a spoon.', '1 shot', ['shot', 'layered'], 26),
  _r('Woo Woo', ['1 oz|vodka', '0.5 oz|peach schnapps', '1 oz|cranberry juice'], '$_shake into a glass.', '1 cocktail', ['cocktail', 'vodka'], 20),
  _r('Oaxaca Old Fashioned', ['1.5 oz|reposado tequila', '0.5 oz|mezcal', '1 tsp|agave syrup', '2 dashes|mole or chocolate bitters', '1|orange peel'], 'Stir over a large cube and express the orange peel.', '1 cocktail', ['cocktail', 'tequila', 'stirred'], 33),
  _r('Naked and Famous', ['0.75 oz|mezcal', '0.75 oz|Aperol', '0.75 oz|yellow Chartreuse', '0.75 oz|fresh lime juice'], '$_shake into a chilled coupe.', '1 cocktail', ['cocktail', 'mezcal', 'sour'], 19),
  _r('Ramos Gin Fizz', ['2 oz|gin', '0.5 oz|lemon juice', '0.5 oz|lime juice', '1 oz|simple syrup', '1.5 oz|cream', '1|egg white', '1 oz|soda water'], 'Dry shake hard, shake again with ice, strain into a glass, and top with soda.', '1 cocktail', ['cocktail', 'gin', 'creamy'], 12),
  _r('Frozen Margarita', ['2 oz|tequila', '1 oz|orange liqueur', '1 oz|fresh lime juice', '1 oz|simple syrup', '1 cup|ice'], 'Blend until smooth.', '1 cocktail', ['cocktail', 'tequila', 'frozen'], 14),
  _r('Rum Punch', ['2 oz|dark rum', '2 oz|orange juice', '2 oz|pineapple juice', '0.5 oz|fresh lime juice', 'splash|grenadine'], 'Build over ice and stir.', '1 cocktail', ['cocktail', 'rum', 'long drink'], 10),
];

final Set<String> _detailedNames = {for (final r in _detailed) r.name};

/// Alcohol Tracker's built-in names that have no detailed spec above yet.
const List<String> _genericNames = [
  'Zombie', 'Tom Collins', 'Eastside', 'Southside', 'El Diablo', 'Green Tea Shot', 'White Tea Shot', 'Buttery Nipple',
  'Chocolate Cake Shot', 'Washington Apple', 'Bahama Mama', 'Rose Spritz',
];

/// Alcohol Tracker's generic card for a built-in name; recognised so an import does not double up.
Recipe genericRecipe(String name) => Recipe(
      name: name,
      ingredients: const [RecipeIngredient('2 oz', 'base spirit'), RecipeIngredient('to taste', 'mixer, ice, or garnish')],
      instructions: 'Combine over ice, stir or shake as appropriate, and serve.',
      yieldText: '1 cocktail',
      tags: const ['cocktail'],
      abvPercent: 25.0,
    );

final List<Recipe> builtInRecipes = [
  ..._detailed,
  for (final n in _genericNames)
    if (!_detailedNames.contains(n)) genericRecipe(n),
  const Recipe(
    name: 'Fresh Horchata',
    ingredients: [RecipeIngredient('1 cup', 'soaked rice'), RecipeIngredient('2 cups', 'water'), RecipeIngredient('1 stick', 'cinnamon'), RecipeIngredient('2 tbsp', 'sugar')],
    instructions: 'Blend soaked rice, water, and cinnamon; strain, sweeten, chill, and serve over ice.',
    yieldText: '2 servings',
    tags: ['zero-proof', 'fresh'],
    abvPercent: 0.0,
  ),
  const Recipe(
    name: 'Spiked Fresh Horchata',
    ingredients: [RecipeIngredient('1 cup', 'fresh horchata'), RecipeIngredient('1.5 oz', 'reposado tequila')],
    instructions: 'Shake with ice, strain over fresh ice, and dust with cinnamon.',
    yieldText: '1 cocktail',
    tags: ['horchata', 'cocktail'],
    abvPercent: 8.0,
  ),
];

/// Every name Alcohol Tracker ships as a built-in (for recognising its generic cards on import).
bool isGenericBuiltIn(Recipe r) {
  final g = genericRecipe(r.name);
  return r.fingerprint == g.fingerprint;
}
