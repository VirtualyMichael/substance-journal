import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/alcohol_data.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/ui/alcohol/alcohol_analytics_page.dart';
import 'package:substance_journal_app/ui/alcohol/alcohol_view_model.dart';

import 'helpers.dart';

Future<LoggedDrink> beerAt(AppDatabase db, String personId, DateTime at, {String name = 'Beer - 12 oz 5%'}) =>
    db.logDrink(personId: personId, at: at, volume: 12, volumeUnit: 'oz', abvPercent: 5, name: name);

/// A person with Alcohol mode switched on and the starter presets, before the app starts.
Future<(TestApp, Person)> alcoholApp(WidgetTester tester) async {
  final app = await buildTestApp(tester);
  final me = await dbRun(tester, app.db.ensureDefaultPerson);
  await dbRun(tester, app.db.ensureDefaultDrinkPresets);
  await dbRun(tester, () => app.db.setSetting('alcoholMode', 'true'));
  return (app, me);
}

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  const settings = EstimateSettings();

  group('summaries', () {
    final now = DateTime(2026, 7, 3, 21);

    Future<List<Ingestion>> drinks(Future<void> Function(AppDatabase db, Person me) seed) async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final me = await db.ensureDefaultPerson();
      await seed(db, me);
      return db.ingestionsForPerson(me.id);
    }

    test('today: BAC rises with drinks, standard drinks add up, and a clear time is estimated', () async {
      final all = await drinks((db, me) async {
        await beerAt(db, me.id, now.subtract(const Duration(hours: 2)));
        await beerAt(db, me.id, now.subtract(const Duration(hours: 1)));
        await beerAt(db, me.id, now.subtract(const Duration(minutes: 10)));
      });
      final s = summarizeAlcoholDay(allDrinks: all, settings: settings, now: now);
      expect(s.drinksOfDay, hasLength(3));
      expect(s.standardDrinks, closeTo(3.0, 1e-9));
      expect(s.bacNow!, greaterThan(0.01));
      expect(s.bacNow!, lessThan(0.15));
      expect(s.inBodyNow!, greaterThan(1.0));
      expect(s.peakBac, greaterThanOrEqualTo(s.bacNow!));
      expect(s.clearTime, isNotNull);
      expect(s.clearTime!.isAfter(now), isTrue);
      expect(s.bacSeries, isNotEmpty);
    });

    test('with no drinks everything is zero and there is no curve', () async {
      final s = summarizeAlcoholDay(allDrinks: const [], settings: settings, now: now);
      expect(s.isEmpty, isTrue);
      expect(s.bacNow, 0);
      expect(s.clearTime, isNull);
      expect(s.standardDrinks, 0);
    });

    test('a night past midnight is one curve for today and a separate total for each day', () async {
      final justAfterMidnight = DateTime(2026, 7, 3, 1, 30);
      final all = await drinks((db, me) async {
        await beerAt(db, me.id, DateTime(2026, 7, 2, 22));
        await beerAt(db, me.id, DateTime(2026, 7, 2, 23, 30));
        await beerAt(db, me.id, justAfterMidnight);
      });
      final s = summarizeAlcoholDay(allDrinks: all, settings: settings, now: DateTime(2026, 7, 3, 2));
      expect(s.drinksOfDay, hasLength(1)); // only the 01:30 beer is "today"
      expect(s.standardDrinks, closeTo(1.0, 1e-9));
      expect(s.bacNow!, greaterThan(0.02)); // but the earlier drinks still count towards BAC
      final yesterday = summarizeAlcoholDay(allDrinks: all, settings: settings, now: DateTime(2026, 7, 3, 2), day: DateTime(2026, 7, 2));
      expect(yesterday.drinksOfDay, hasLength(2));
      expect(yesterday.bacNow, isNull);
      expect(yesterday.peakBac, greaterThan(0.02));
    });

    test('drinks more than 36 hours ago no longer count towards today', () async {
      final all = await drinks((db, me) async {
        await beerAt(db, me.id, now.subtract(const Duration(hours: 40)));
      });
      final s = summarizeAlcoholDay(allDrinks: all, settings: settings, now: now);
      expect(s.bacNow, 0);
      expect(s.drinksOfDay, isEmpty);
    });

    test('a heavier body gives a lower BAC for the same drinks', () async {
      final all = await drinks((db, me) async {
        await beerAt(db, me.id, now.subtract(const Duration(minutes: 40)));
        await beerAt(db, me.id, now.subtract(const Duration(minutes: 20)));
      });
      final light = summarizeAlcoholDay(allDrinks: all, settings: const EstimateSettings(userWeightLbs: 120), now: now);
      final heavy = summarizeAlcoholDay(allDrinks: all, settings: const EstimateSettings(userWeightLbs: 240), now: now);
      expect(light.bacNow!, greaterThan(heavy.bacNow!));
    });
  });

  group('presets and history helpers', () {
    Preset preset(String id, String name) =>
        Preset(id: id, hlc: 'x', deleted: false, substanceKey: 'alcohol', route: 'oral', name: name, amount: 12, unit: 'oz', detailsJson: '{"abv":5}');

    test('top presets are the most used in the last 90 days, topped up in list order', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final me = await db.ensureDefaultPerson();
      final now = DateTime(2026, 7, 3, 21);
      for (var i = 0; i < 3; i++) {
        await beerAt(db, me.id, now.subtract(Duration(days: i + 1)), name: 'Wine');
      }
      await beerAt(db, me.id, now.subtract(const Duration(days: 2, hours: 3)), name: 'Gin');
      await beerAt(db, me.id, now.subtract(const Duration(days: 200)), name: 'Old favourite');
      final presets = [preset('a', 'Beer'), preset('b', 'Gin'), preset('c', 'Old favourite'), preset('d', 'Wine'), preset('e', 'Zin')];
      final top = topPresets(presets, await db.ingestionsForPerson(me.id), now);
      expect(top.map((p) => p.name), ['Wine', 'Gin', 'Beer', 'Old favourite']);
      expect(topPresets(presets, const [], now, count: 2).map((p) => p.name), ['Beer', 'Gin']);
    });

    test('drinking days list each day once, newest first, with totals', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final me = await db.ensureDefaultPerson();
      await beerAt(db, me.id, DateTime(2026, 7, 1, 20));
      await beerAt(db, me.id, DateTime(2026, 7, 1, 22));
      await beerAt(db, me.id, DateTime(2026, 6, 28, 19));
      final days = drinkingDays(await db.ingestionsForPerson(me.id), settings);
      expect(days.map((d) => d.day), [DateTime(2026, 7, 1), DateTime(2026, 6, 28)]);
      expect(days.first.drinks, 2);
      expect(days.first.standardDrinks, closeTo(2.0, 1e-9));
    });

    test('tolerance builds after heavy nights and the projected baseline date follows', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final me = await db.ensureDefaultPerson();
      final now = DateTime(2026, 7, 10, 12);
      for (final day in [3, 5, 6]) {
        for (var i = 0; i < 7; i++) {
          await beerAt(db, me.id, DateTime(2026, 7, day, 20).add(Duration(minutes: i * 20)));
        }
      }
      final drinks = await db.ingestionsForPerson(me.id);
      final t = summarizeTolerance(allDrinks: drinks, settings: settings, now: now);
      expect(t.multiplierNow, greaterThan(1.05));
      expect(t.multiplierNow, lessThanOrEqualTo(2.0)); // bounded by the max extra dose
      expect(t.baselineBy, isNotNull);
      expect(t.baselineBy!.isAfter(DateTime(2026, 7, 10)), isTrue);

      final none = summarizeTolerance(allDrinks: const [], settings: settings, now: now);
      expect(none.series, isEmpty);
      expect(none.multiplierNow, 1.0);
      expect(none.baselineBy, isNull);
    });
  });

  group('screens', () {
    testWidgets('turning Alcohol mode on swaps the pages, seeds six drinks, and turning it off restores them', (tester) async {
      final app = await buildTestApp(tester);
      await dbRun(tester, app.db.ensureDefaultPerson);
      await startApp(tester, app);
      expect(find.text('Journal'), findsWidgets);
      expect(find.text('Compounds'), findsOneWidget);

      await tapKey(tester, 'mode-toggle');
      expect(find.text('Today'), findsWidgets);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Compounds'), findsNothing);
      expect(find.text('Calendar'), findsNothing);
      expect((await dbRun(tester, () => app.db.watchDrinkPresets().first)), hasLength(6));
      expect(await dbRun(tester, () => app.db.getSetting('alcoholMode')), 'true');

      await tapKey(tester, 'mode-toggle');
      expect(find.text('Compounds'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      expect(await dbRun(tester, () => app.db.getSetting('alcoholMode')), 'false');
      await disposeApp(tester, app);
    });

    testWidgets('the quick-add chips log a drink for now, and undo takes it back', (tester) async {
      final (app, me) = await alcoholApp(tester);
      await startApp(tester, app);
      expect(find.text('Nothing logged today.'), findsOneWidget);
      expect(textOf(tester, 'std-drinks'), '0.0');

      final beer = (await dbRun(tester, () => app.db.watchDrinkPresets().first)).firstWhere((p) => p.name == 'Beer - 12 oz 5%');
      await tapKey(tester, 'quick-${beer.id}');
      expect(find.text('Nothing logged today.'), findsNothing);
      expect(find.text('Beer - 12 oz 5%'), findsWidgets);
      expect(textOf(tester, 'std-drinks'), '1.0');
      expect(double.parse(textOf(tester, 'bac-now').replaceAll('%', '')), greaterThanOrEqualTo(0));

      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(row.time, testNow);
      expect(row.dose, closeTo(14.016, 1e-3));

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Undo'));
      await settle(tester, rounds: 8);
      expect(find.text('Nothing logged today.'), findsOneWidget);
      expect(await dbRun(tester, () => app.db.ingestionsForPerson(me.id)), isEmpty);
      await disposeApp(tester, app);
    });

    testWidgets('the dropdown adds any saved drink', (tester) async {
      final (app, me) = await alcoholApp(tester);
      await startApp(tester, app);
      await tester.tap(find.byKey(const ValueKey('preset-dropdown')));
      await settle(tester);
      await tester.tap(find.text('Wine - 5 oz 12%').last);
      await settle(tester);
      await tapKey(tester, 'quick-add-selected');
      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(DrinkDetails.of(row).name, 'Wine - 5 oz 12%');
      expect(standardDrinksOf(row, settings), closeTo(1.0, 1e-9));
      await disposeApp(tester, app);
    });

    testWidgets('a custom drink can be added with its own volume, ABV and duration', (tester) async {
      final (app, me) = await alcoholApp(tester);
      await startApp(tester, app);

      await tapKey(tester, 'custom-drink');
      await tapKey(tester, 'drink-save');
      expect(find.text('Enter the volume.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('drink-name')), 'IPA');
      await tester.enterText(find.byKey(const ValueKey('drink-volume')), '16');
      await tester.enterText(find.byKey(const ValueKey('drink-abv')), '7');
      await settle(tester, rounds: 2);
      expect(find.textContaining('26.2 g ethanol'), findsOneWidget); // 16 oz x 7% x 23.36
      await tester.enterText(find.byKey(const ValueKey('drink-took')), '45');
      await tapKey(tester, 'drink-save');

      final row = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(DrinkDetails.of(row).name, 'IPA');
      expect(row.dose, closeTo(16 * 0.07 * 23.36, 1e-9));
      expect(row.endTime, testNow.add(const Duration(minutes: 45)));
      expect(find.text('IPA'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('a logged drink can be edited and deleted with undo', (tester) async {
      final (app, me) = await alcoholApp(tester);
      final logged = await dbRun(tester, () => beerAt(app.db, me.id, testNow.subtract(const Duration(hours: 1))));
      await startApp(tester, app);

      await tapKey(tester, 'drink-${logged.ingestion.id}');
      await tester.enterText(find.byKey(const ValueKey('drink-volume')), '24');
      await tapKey(tester, 'drink-save');
      final edited = (await dbRun(tester, () => app.db.ingestionsForPerson(me.id))).single;
      expect(DrinkDetails.of(edited).volume, 24);
      expect(edited.dose, closeTo(24 * 0.05 * 23.36, 1e-9));
      expect(textOf(tester, 'std-drinks'), '2.0');

      await tapKey(tester, 'delete-drink-${logged.ingestion.id}');
      expect(find.text('Nothing logged today.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Undo'));
      await settle(tester, rounds: 6);
      expect(find.text('Nothing logged today.'), findsNothing);
      await disposeApp(tester, app);
    });

    testWidgets("today's status shows a clear-by time after recent drinks and 'clear' when nothing is in the body", (tester) async {
      final (app, me) = await alcoholApp(tester);
      await dbRun(tester, () => beerAt(app.db, me.id, testNow.subtract(const Duration(minutes: 30))));
      await dbRun(tester, () => beerAt(app.db, me.id, testNow.subtract(const Duration(minutes: 10))));
      await startApp(tester, app);
      expect(textOf(tester, 'clear-by'), matches(RegExp(r'^\d\d:\d\d$')));
      expect(find.byKey(const ValueKey('bac-chart')), findsOneWidget);
      await disposeApp(tester, app);

      final (empty, _) = await alcoholApp(tester);
      await startApp(tester, empty);
      expect(textOf(tester, 'clear-by'), 'clear');
      await disposeApp(tester, empty);
    });

    testWidgets("another person's drinks are not mine, and quick add goes to whoever is open", (tester) async {
      final (app, me) = await alcoholApp(tester);
      final bob = await dbRun(tester, () => app.db.addPerson('Bob'));
      await dbRun(tester, () => beerAt(app.db, bob.id, testNow.subtract(const Duration(hours: 1)), name: "Bob's beer"));
      await startApp(tester, app);
      expect(find.text("Bob's beer"), findsNothing);
      expect(find.text('Nothing logged today.'), findsOneWidget);

      await tapKey(tester, 'person-switcher');
      await tester.tap(find.byKey(ValueKey('switch-${bob.id}')));
      await settle(tester);
      expect(find.text("Bob's beer"), findsOneWidget);

      final preset = (await dbRun(tester, () => app.db.watchDrinkPresets().first)).first;
      await tapKey(tester, 'quick-${preset.id}');
      expect(await dbRun(tester, () => app.db.ingestionsForPerson(bob.id)), hasLength(2));
      expect(await dbRun(tester, () => app.db.ingestionsForPerson(me.id)), isEmpty);
      await disposeApp(tester, app);
    });

    testWidgets('history lists previous drinking days and opens one', (tester) async {
      final (app, me) = await alcoholApp(tester);
      await dbRun(tester, () => beerAt(app.db, me.id, DateTime(2026, 7, 1, 20)));
      await dbRun(tester, () => beerAt(app.db, me.id, DateTime(2026, 7, 1, 21)));
      await dbRun(tester, () => beerAt(app.db, me.id, DateTime(2026, 6, 28, 19), name: 'Saturday pint'));
      await startApp(tester, app);

      await tester.tap(find.text('History'));
      await settle(tester);
      expect(find.byKey(const ValueKey('history-2026-7-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-2026-6-28')), findsOneWidget);
      expect(find.textContaining('2 drinks'), findsOneWidget);
      expect(find.textContaining('1 drink  |'), findsOneWidget);

      await tapKey(tester, 'history-2026-6-28');
      expect(find.text('Saturday pint'), findsOneWidget);
      expect(find.text('Jun 28, 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('preset-dropdown')), findsNothing); // quick add is for today only
      expect(find.byKey(const ValueKey('bac-peak')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('history is empty before any drinking', (tester) async {
      final (app, _) = await alcoholApp(tester);
      await startApp(tester, app);
      await tester.tap(find.text('History'));
      await settle(tester);
      expect(find.byKey(const ValueKey('no-history')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('analytics: averages, range choice, heatmap and tolerance', (tester) async {
      final (app, me) = await alcoholApp(tester);
      // Three drinking days in the last week: 2, 1 and 3 standard drinks.
      for (final (day, count) in [(2, 2), (1, 1), (3, 3)]) {
        for (var i = 0; i < count; i++) {
          await dbRun(tester, () => beerAt(app.db, me.id, DateTime(2026, 7, day, 19).add(Duration(minutes: i * 30))));
        }
      }
      await startApp(tester, app);
      await tester.tap(find.text('Analytics'));
      await settle(tester);

      // Last 30 days ending Jul 3: 6 standard drinks over 30 days, 3 drinking days.
      expect(textOf(tester, 'total-drinks'), '6.0');
      expect(textOf(tester, 'avg-drinks'), '0.2'); // 6 / 30
      expect(textOf(tester, 'avg-days'), '0.7'); // 7 x 3 / 30
      expect(textOf(tester, 'heaviest'), '3.0 on 7/3');

      await tapKey(tester, 'range-7');
      expect(textOf(tester, 'avg-drinks'), '0.9'); // 6 / 7
      expect(textOf(tester, 'avg-days'), '3.0'); // 7 x 3 / 7

      expect(find.byKey(const ValueKey('daily-bars')), findsOneWidget);
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('heat-2026-7-3')), findsOneWidget);
      await tapKey(tester, 'heat-prev');
      expect(find.text('June 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('tolerance-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('tolerance-now')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('body settings are saved per person, validated, and change the estimate', (tester) async {
      final (app, me) = await alcoholApp(tester);
      await dbRun(tester, () => beerAt(app.db, me.id, testNow.subtract(const Duration(minutes: 30))));
      await dbRun(tester, () => beerAt(app.db, me.id, testNow.subtract(const Duration(minutes: 10))));
      await startApp(tester, app);
      final before = double.parse(textOf(tester, 'bac-now').replaceAll('%', ''));

      await tester.tap(find.text('Settings'));
      await settle(tester);
      await tapKey(tester, 'estimates-tile');
      await tester.enterText(find.byKey(const ValueKey('est-weight')), '10');
      await tapKey(tester, 'estimates-save');
      expect(find.text('Weight must be between 50 and 700 lb.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('est-weight')), '110');
      await tapKey(tester, 'estimates-save');
      expect(find.byKey(const ValueKey('est-saved')), findsOneWidget);
      expect((await dbRun(tester, () => app.db.getEstimateSettings(me.id))).userWeightLbs, 110);

      await tester.tap(find.text('Today'));
      await settle(tester);
      final after = double.parse(textOf(tester, 'bac-now').replaceAll('%', ''));
      expect(after, greaterThan(before)); // a lighter body reaches a higher BAC from the same drinks
      await disposeApp(tester, app);
    });

    testWidgets('presets can be added, edited and deleted from settings', (tester) async {
      final (app, _) = await alcoholApp(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Settings'));
      await settle(tester);

      await tapKey(tester, 'add-preset');
      await tester.enterText(find.byKey(const ValueKey('preset-name')), 'Pint of cider');
      await tester.enterText(find.byKey(const ValueKey('preset-volume')), '20');
      await tester.enterText(find.byKey(const ValueKey('preset-abv')), '4.5');
      await tapKey(tester, 'preset-save');
      final presets = await dbRun(tester, () => app.db.watchDrinkPresets().first);
      final cider = presets.firstWhere((p) => p.name == 'Pint of cider');
      expect(cider.amount, 20);
      expect(find.byKey(ValueKey('preset-${cider.id}')), findsOneWidget);

      await tapKey(tester, 'preset-${cider.id}');
      await tester.enterText(find.byKey(const ValueKey('preset-abv')), '5');
      await tapKey(tester, 'preset-save');
      expect(presetAbv(await dbRun(tester, () => app.db.watchDrinkPresets().first), 'Pint of cider'), 5);

      await tapKey(tester, 'delete-preset-${cider.id}');
      expect(find.byKey(ValueKey('preset-${cider.id}')), findsNothing);
      await disposeApp(tester, app);
    });
  });
}

double presetAbv(List<Preset> presets, String name) {
  final p = presets.firstWhere((x) => x.name == name);
  return double.parse(RegExp(r'"abv":([0-9.]+)').firstMatch(p.detailsJson)!.group(1)!);
}
