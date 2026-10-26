import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

/// Seeds one experience with an MDMA dose for [person] before the app starts.
Future<Experience> seedExperience(
  WidgetTester tester,
  TestApp app,
  Person person, {
  String title = 'Saturday night',
  String substance = 'mdma',
  String route = 'oral',
  double dose = 100,
  String unit = 'mg',
  Duration ago = const Duration(hours: 1),
}) async {
  final exp = await dbRun(tester, () => app.db.addExperience(personId: person.id, sortDate: testNow.subtract(ago), title: title));
  await dbRun(
    tester,
    () => app.db.addIngestion(
      experience: exp,
      substanceKey: substance,
      route: route,
      time: testNow.subtract(ago),
      dose: dose,
      unit: unit,
    ),
  );
  return exp;
}

void main() {
  testWidgets('the journal lists experiences and opens one with its timeline and dose class', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await seedExperience(tester, app, me);
    await startApp(tester, app);

    expect(find.text('Saturday night'), findsOneWidget);
    expect(find.text('MDMA'), findsOneWidget);
    expect(find.text('1 ingestion  |  Jul 3, 2026 20:00'), findsOneWidget);

    await tester.tap(find.text('Saturday night'));
    await settle(tester);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Common'), findsOneWidget); // 100 mg MDMA
    expect(find.text('Ingestions'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('timed notes and ratings can be added and removed', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await seedExperience(tester, app, me);
    await startApp(tester, app);
    await tester.tap(find.text('Saturday night'));
    await settle(tester);

    await tapKey(tester, 'add-fab');
    await tapKey(tester, 'add-note');
    await tester.enterText(find.byKey(const ValueKey('note-text')), 'Feeling the first effects');
    await settle(tester, rounds: 1);
    await tapKey(tester, 'note-save');
    expect(find.text('Feeling the first effects'), findsOneWidget);
    expect(find.text('Notes during the experience'), findsOneWidget);

    await tapKey(tester, 'add-fab');
    await tapKey(tester, 'add-rating');
    await tapKey(tester, 'shulgin-plus2');
    await tapKey(tester, 'rating-save');
    expect(find.text('Ratings'), findsOneWidget);
    expect(find.textContaining('Intensity ++'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete note'));
    await settle(tester);
    expect(find.text('Feeling the first effects'), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('deleting an ingestion can be undone', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await seedExperience(tester, app, me);
    await startApp(tester, app);
    await tester.tap(find.text('Saturday night'));
    await settle(tester);

    final deleteButton = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('delete-'));
    await tester.tap(deleteButton);
    await settle(tester);
    expect(find.text('Nothing logged yet.'), findsOneWidget);
    expect(find.text('MDMA deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Nothing logged yet.'), findsNothing);
    expect(find.text('Common'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('experiences can be renamed, favorited and deleted with undo', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    await seedExperience(tester, app, me);
    await startApp(tester, app);
    await tester.tap(find.text('Saturday night'));
    await settle(tester);

    await tapKey(tester, 'experience-title');
    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Festival day');
    await tapKey(tester, 'title-save');
    expect(find.text('Festival day'), findsOneWidget);

    await tapKey(tester, 'favorite');
    expect(find.byIcon(Icons.star), findsOneWidget);

    await tapKey(tester, 'experience-menu');
    await tester.tap(find.text('Delete experience'));
    await settle(tester);
    await tapKey(tester, 'confirm-delete');
    expect(find.text("Me's journal is empty"), findsOneWidget);

    // Let the page transition and the snackbar's slide-in finish so Undo is on screen.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Undo'));
    // Undo runs a multi-step transaction; each step needs a round trip to the database.
    await settle(tester, rounds: 14);
    expect(find.text('Festival day'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('people have separate journals and switching never mixes them', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final bob = await dbRun(tester, () => app.db.addPerson('Bob'));
    await seedExperience(tester, app, me, title: 'My night');
    await seedExperience(tester, app, bob, title: "Bob's night", substance: 'lsd', route: 'sublingual', dose: 100, unit: 'µg');
    await startApp(tester, app);

    expect(find.text('My night'), findsOneWidget);
    expect(find.text("Bob's night"), findsNothing);

    await tapKey(tester, 'person-switcher');
    await tester.tap(find.byKey(ValueKey('switch-${bob.id}')));
    await settle(tester);
    expect(find.text("Bob's night"), findsOneWidget);
    expect(find.text('My night'), findsNothing);
    expect(find.text('LSD'), findsOneWidget);
    expect(find.text('MDMA'), findsNothing);

    await tapKey(tester, 'person-switcher');
    await tester.tap(find.byKey(ValueKey('switch-${me.id}')));
    await settle(tester);
    expect(find.text('My night'), findsOneWidget);
    expect(find.text("Bob's night"), findsNothing);
    await disposeApp(tester, app);
  });

  testWidgets('settings: adding a person switches to them, deleting removes their data', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapKey(tester, 'add-person');
    await tester.enterText(find.byKey(const ValueKey('person-name')), 'Sam');
    await tapKey(tester, 'person-save');
    expect(find.text('Sam'), findsWidgets);
    expect(find.text('Showing now'), findsOneWidget);

    final people = await dbRun(tester, app.db.activePeople);
    final sam = people.firstWhere((p) => p.name == 'Sam');
    await tapKey(tester, 'delete-person-${sam.id}');
    await tapKey(tester, 'confirm-delete-person');
    expect(find.text('Sam'), findsNothing);
    final after = await dbRun(tester, app.db.activePeople);
    expect(after.map((p) => p.name), ['Me']);
    await disposeApp(tester, app);
  });

  testWidgets('the compound list orders by my own history and my favorites; hiding works', (tester) async {
    final app = await buildTestApp(tester);
    final me = await dbRun(tester, app.db.ensureDefaultPerson);
    final bob = await dbRun(tester, () => app.db.addPerson('Bob'));
    // I use cannabis most; Bob uses MDMA a lot, which must not affect my ordering.
    for (final day in [1, 2, 3]) {
      await seedExperience(tester, app, me, title: 'c$day', substance: 'cannabis', route: 'smoked', dose: 2, unit: 'mg', ago: Duration(days: day));
    }
    for (final day in [1, 2, 3, 4, 5]) {
      await seedExperience(tester, app, bob, title: 'b$day', substance: 'mdma', ago: Duration(days: day));
    }
    await startApp(tester, app);

    await tester.tap(find.text('Compounds'));
    await settle(tester);
    // Compound tiles only (the tolerance shortcut is a tile too); the name is the first thing in the title row.
    List<String> order() => [
          for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
            if ((t.key as ValueKey?)?.value.toString().startsWith('compound-') ?? false)
              (((t.title as Row).children.first as Flexible).child as Text).data!,
        ];

    expect(order().first, 'Cannabis');
    expect(order().indexOf('Cannabis'), lessThan(order().indexOf('MDMA')));

    // Favorite LSD: it floats above Cannabis.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('compound-lsd')), matching: find.byIcon(Icons.star_border)));
    await settle(tester);
    expect(order().first, 'LSD');

    // Hide Ketamine from its menu.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('compound-ketamine')), matching: find.byType(PopupMenuButton<String>)));
    await settle(tester);
    await tester.tap(find.text('Hide from list'));
    await settle(tester);
    expect(find.byKey(const ValueKey('compound-ketamine')), findsNothing);
    expect(find.text('Hidden (1)'), findsOneWidget);

    await tester.tap(find.text('Hidden (1)'));
    await settle(tester);
    expect(find.byKey(const ValueKey('compound-ketamine')), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('a compound page shows reference data and starts logging at the dose step', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tester.tap(find.text('Compounds'));
    await settle(tester);
    await tapKey(tester, 'compound-lsd');

    expect(find.text('Safety notes'), findsOneWidget);
    expect(find.textContaining('NBOMe'), findsWidgets);
    expect(find.byKey(const ValueKey('roa-sublingual')), findsOneWidget);

    await tapKey(tester, 'log-this');
    expect(find.text('LSD dose'), findsOneWidget);
    await disposeApp(tester, app);
  });

  testWidgets('theme choice is saved', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(await dbRun(tester, () => app.db.getSetting('themeMode')), 'dark');
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    await disposeApp(tester, app);
  });
}
