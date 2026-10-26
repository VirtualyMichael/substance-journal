import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/ui/calendar/calendar_data.dart';
import 'package:substance_journal_app/ui/timeline/timeline_data.dart';

import 'helpers.dart';

Person person(String id, String name) => Person(id: id, hlc: 'x', deleted: false, name: name, colorValue: 0xFF6750A4, isDefault: id == 'me');

Experience experience(String id, String personId, DateTime sortDate, {String title = ''}) => Experience(
      id: id,
      hlc: 'x',
      deleted: false,
      personId: personId,
      title: title,
      notes: '',
      sortDate: sortDate,
      createdAt: sortDate,
      isFavorite: false,
      locationName: null,
      latitude: null,
      longitude: null,
    );

Ingestion ingestion(String id, String experienceId, String personId, String substance, String route, double dose, DateTime time) => Ingestion(
      id: id,
      hlc: 'x',
      deleted: false,
      experienceId: experienceId,
      personId: personId,
      substanceKey: substance,
      route: route,
      time: time,
      endTime: null,
      dose: dose,
      unit: 'mg',
      doseIsEstimate: false,
      doseStdDev: null,
      stomachFullness: null,
      customUnitId: null,
      productId: null,
      absorbedMg: null,
      method: null,
      notes: '',
      detailsJson: '{}',
    );

void main() {
  final reference = loadReference();
  final me = person('me', 'Me');
  final bob = person('bob', 'Bob');
  final july3 = DateTime(2026, 7, 3);

  Map<DateTime, List<DayPerson>> calendar({
    required List<Person> people,
    required List<Experience> experiences,
    required List<Ingestion> ingestions,
    required DateTime now,
    DateTime? from,
    DateTime? to,
  }) =>
      buildCalendar(
        people: people,
        experiences: experiences,
        ingestions: ingestions,
        reference: reference,
        now: now,
        from: from ?? DateTime(2026, 6, 29),
        to: to ?? DateTime(2026, 8, 2),
      );

  group('buildCalendar', () {
    final meExp = experience('e1', 'me', DateTime(2026, 7, 3, 17));
    final meDose = ingestion('i1', 'e1', 'me', 'mdma', 'oral', 100, DateTime(2026, 7, 3, 17));
    final bobExp = experience('e2', 'bob', DateTime(2026, 7, 3, 19));
    final bobDose = ingestion('i2', 'e2', 'bob', 'mdma', 'oral', 100, DateTime(2026, 7, 3, 19));

    test('one person on a day gives one entry', () {
      final days = calendar(people: [me, bob], experiences: [meExp], ingestions: [meDose], now: DateTime(2026, 7, 3, 21));
      expect(days[july3], hasLength(1));
      expect(days[july3]!.single.person.name, 'Me');
      expect(days[july3]!.single.substanceKeys, ['mdma']);
    });

    test('two people on the same day each get their own whole-number percent', () {
      final now = DateTime(2026, 7, 3, 21);
      final days = calendar(people: [me, bob], experiences: [meExp, bobExp], ingestions: [meDose, bobDose], now: now);
      final entries = days[july3]!;
      expect(entries.map((e) => e.person.name), ['Bob', 'Me']);
      final mine = entries.firstWhere((e) => e.person.id == 'me');
      final his = entries.firstWhere((e) => e.person.id == 'bob');
      // Me started two hours earlier, so is further along.
      expect(mine.percent, greaterThan(his.percent));
      expect(his.percent, greaterThan(0));
      expect(mine.percent, lessThan(100));

      // The numbers equal each person's own timeline progress, nothing blended.
      int own(Ingestion i) => experienceProgressPercent(
            series: buildTimelineSeries(ingestions: [i], reference: reference, now: now),
            now: now,
          );
      expect(mine.percent, own(meDose));
      expect(his.percent, own(bobDose));
    });

    test("adding another person's ingestion never changes my percent", () {
      final now = DateTime(2026, 7, 3, 21);
      final alone = calendar(people: [me, bob], experiences: [meExp], ingestions: [meDose], now: now);
      final together = calendar(people: [me, bob], experiences: [meExp, bobExp], ingestions: [meDose, bobDose], now: now);
      int mine(Map<DateTime, List<DayPerson>> d) => d[july3]!.firstWhere((e) => e.person.id == 'me').percent;
      expect(mine(together), mine(alone));
    });

    test('percent is 0 before the start, whole numbers while running, and 100 after the end', () {
      int at(DateTime now) =>
          calendar(people: [me], experiences: [meExp], ingestions: [meDose], now: now)[july3]!.single.percent;
      expect(at(DateTime(2026, 7, 3, 16)), 0);
      expect(at(DateTime(2026, 7, 4, 12)), 100);
      final mid = at(DateTime(2026, 7, 3, 19));
      expect(mid, inInclusiveRange(1, 99));
      expect(mid, isA<int>());
    });

    test('a night that runs past midnight appears on both days', () {
      final lateExp = experience('late', 'me', DateTime(2026, 7, 3, 23));
      final lateDose = ingestion('late', 'late', 'me', 'mdma', 'oral', 100, DateTime(2026, 7, 3, 23));
      final days = calendar(people: [me], experiences: [lateExp], ingestions: [lateDose], now: DateTime(2026, 7, 5));
      expect(days.keys, containsAll([DateTime(2026, 7, 3), DateTime(2026, 7, 4)]));
      expect(days[DateTime(2026, 7, 5)], isNull);
    });

    test('two experiences for one person on a day show the one in progress', () {
      final morning = experience('am', 'me', DateTime(2026, 7, 3, 8));
      final morningDose = ingestion('am', 'am', 'me', 'nicotine', 'buccal', 2, DateTime(2026, 7, 3, 8));
      final days = calendar(
        people: [me],
        experiences: [morning, meExp],
        ingestions: [morningDose, meDose],
        now: DateTime(2026, 7, 3, 19),
      );
      final entry = days[july3]!.single;
      expect(entry.experienceId, 'e1');
      expect(entry.inProgress, isTrue);
    });

    test('days outside the requested range are left out', () {
      final days = calendar(
        people: [me],
        experiences: [meExp],
        ingestions: [meDose],
        now: DateTime(2026, 7, 5),
        from: DateTime(2026, 7, 10),
        to: DateTime(2026, 7, 20),
      );
      expect(days, isEmpty);
    });

    test('experiences with no ingestions or an unknown person are ignored; unknown substances still show', () {
      final empty = experience('empty', 'me', DateTime(2026, 7, 3));
      final stranger = experience('x', 'ghost', DateTime(2026, 7, 3));
      final strangerDose = ingestion('x', 'x', 'ghost', 'mdma', 'oral', 100, DateTime(2026, 7, 3, 12));
      final mystery = experience('m', 'me', DateTime(2026, 7, 3, 12));
      final mysteryDose = ingestion('m', 'm', 'me', 'nope', 'oral', 1, DateTime(2026, 7, 3, 12));
      final days = calendar(
        people: [me],
        experiences: [empty, stranger, mystery],
        ingestions: [strangerDose, mysteryDose],
        now: DateTime(2026, 7, 3, 13),
      );
      expect(days[july3], hasLength(1));
      expect(days[july3]!.single.experienceId, 'm');
      expect(days[july3]!.single.percent, inInclusiveRange(1, 99));
    });
  });

  group('monthGrid', () {
    test('July 2026 starts on Monday June 29 and ends on Sunday August 2', () {
      final grid = monthGrid(DateTime(2026, 7));
      expect(grid, hasLength(35));
      expect(grid.first, DateTime(2026, 6, 29));
      expect(grid.last, DateTime(2026, 8, 2));
      expect(grid.first.weekday, DateTime.monday);
      expect(grid.last.weekday, DateTime.sunday);
    });

    test('a 28-day February that starts on a Monday needs exactly four rows', () {
      final grid = monthGrid(DateTime(2027, 2));
      expect(grid, hasLength(28));
      expect(grid.first, DateTime(2027, 2, 1));
    });

    test('a month that spills into six weeks gets six rows', () {
      expect(monthGrid(DateTime(2026, 8)), hasLength(42)); // Aug 1, 2026 is a Saturday, 31 days
    });

    test('every grid is whole weeks and contains the whole month', () {
      for (var m = 1; m <= 12; m++) {
        final grid = monthGrid(DateTime(2026, m));
        expect(grid.length % 7, 0);
        final inMonth = grid.where((d) => d.month == m).length;
        expect(inMonth, DateTime(2026, m + 1, 0).day);
      }
    });
  });

  group('screen', () {
    Future<(TestApp, Person, Person)> twoPeopleOnJuly3(WidgetTester tester) async {
      final app = await buildTestApp(tester);
      final meRow = await dbRun(tester, app.db.ensureDefaultPerson);
      final bobRow = await dbRun(tester, () => app.db.addPerson('Bob'));
      Future<void> add(Person p, String title, Duration ago) async {
        final exp = await dbRun(tester, () => app.db.addExperience(personId: p.id, sortDate: testNow.subtract(ago), title: title));
        await dbRun(
          tester,
          () => app.db.addIngestion(experience: exp, substanceKey: 'mdma', route: 'oral', time: testNow.subtract(ago), dose: 100, unit: 'mg'),
        );
      }

      await add(meRow, 'My night', const Duration(hours: 4));
      await add(bobRow, "Bob's night", const Duration(hours: 2));
      return (app, meRow, bobRow);
    }

    testWidgets('a day with two people shows the badge with each percent', (tester) async {
      final (app, meRow, bobRow) = await twoPeopleOnJuly3(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Calendar'));
      await settle(tester);

      expect(find.text('July 2026'), findsOneWidget);
      final badge = find.descendant(of: find.byKey(const ValueKey('day-2026-7-3')), matching: find.byKey(const ValueKey('person-badge')));
      expect(badge, findsOneWidget);

      final now = testNow;
      int percentFor(Duration ago) {
        final i = ingestionFor(ago);
        return experienceProgressPercent(series: buildTimelineSeries(ingestions: [i], reference: app.reference, now: now), now: now);
      }

      // The badge lists people alphabetically: Bob first, then Me.
      // Each percent follows a dot in that person's colour.
      final text = tester.widget<Text>(find.byKey(const ValueKey('badge-text'))).textSpan!.toPlainText().replaceAll('●', '').trim();
      expect(text, '${percentFor(const Duration(hours: 2))}% ${percentFor(const Duration(hours: 4))}%');
      expect(RegExp(r'^\d+% \d+%$').hasMatch(text), isTrue);
      expect(meRow.id, isNot(bobRow.id));

      // No other day has a badge.
      expect(find.byKey(const ValueKey('person-badge')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('a day with one person has no badge but shows their substance dot', (tester) async {
      final app = await buildTestApp(tester);
      final meRow = await dbRun(tester, app.db.ensureDefaultPerson);
      final exp = await dbRun(tester, () => app.db.addExperience(personId: meRow.id, sortDate: testNow, title: 'Solo'));
      await dbRun(
        tester,
        () => app.db.addIngestion(experience: exp, substanceKey: 'lsd', route: 'sublingual', time: testNow, dose: 100, unit: 'µg'),
      );
      await startApp(tester, app);
      await tester.tap(find.text('Calendar'));
      await settle(tester);
      expect(find.byKey(const ValueKey('person-badge')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'July 3, Me')), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets('tapping the day lists both people with their progress; tapping one opens their experience', (tester) async {
      final (app, meRow, bobRow) = await twoPeopleOnJuly3(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Calendar'));
      await settle(tester);

      await tapKey(tester, 'day-2026-7-3');
      expect(find.byKey(ValueKey('day-entry-${meRow.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('day-entry-${bobRow.id}')), findsOneWidget);
      expect(find.textContaining('% through'), findsNWidgets(2));
      expect(find.textContaining("Bob: Bob's night"), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('day-entry-${bobRow.id}')));
      await settle(tester, rounds: 6);
      expect(find.text("Bob's night"), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      // Opening Bob's experience switched the open journal to Bob.
      expect(await dbRun(tester, app.db.currentPersonId), bobRow.id);
      await disposeApp(tester, app);
    });

    testWidgets('month navigation and Today', (tester) async {
      final app = await buildTestApp(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Calendar'));
      await settle(tester);
      expect(find.text('July 2026'), findsOneWidget);
      await tapKey(tester, 'month-next');
      expect(find.text('August 2026'), findsOneWidget);
      await tapKey(tester, 'month-prev');
      await tapKey(tester, 'month-prev');
      expect(find.text('June 2026'), findsOneWidget);
      await tapKey(tester, 'month-today');
      expect(find.text('July 2026'), findsOneWidget);
      await disposeApp(tester, app);
    });

    testWidgets("changing person keeps the badge but moves the dots to the new person's days", (tester) async {
      final (app, meRow, bobRow) = await twoPeopleOnJuly3(tester);
      await startApp(tester, app);
      await tester.tap(find.text('Calendar'));
      await settle(tester);
      expect(find.byKey(const ValueKey('person-badge')), findsOneWidget);
      await dbRun(tester, () => app.db.setCurrentPerson(bobRow.id));
      await settle(tester);
      expect(find.byKey(const ValueKey('person-badge')), findsOneWidget);
      expect(meRow.name, 'Me');
      await disposeApp(tester, app);
    });
  });
}

/// The MDMA ingestion the screen tests create, [ago] before the test clock.
Ingestion ingestionFor(Duration ago) =>
    ingestion('t', 'e', 'p', 'mdma', 'oral', 100, testNow.subtract(ago));
