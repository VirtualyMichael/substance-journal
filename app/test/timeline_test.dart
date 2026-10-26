import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/ui/dose_text.dart';
import 'package:substance_journal_app/ui/timeline/timeline_chart.dart';
import 'package:substance_journal_app/ui/timeline/timeline_data.dart';

import 'helpers.dart';

Ingestion ingestion(String substance, String route, double? dose, DateTime time, {String id = 'i'}) => Ingestion(
      id: id,
      hlc: 'x',
      deleted: false,
      experienceId: 'e',
      personId: 'p',
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
  test('alcohol reads in fl oz, shots and standard drinks, never grams of ethanol', () {
    Ingestion drink(String details, double grams) => ingestion('alcohol', 'oral', grams, DateTime(2026, 7, 3, 20)).copyWith(detailsJson: details);
    expect(describeIngestionDose(drink('{"volume":12,"volumeUnit":"oz","abv":5}', 14.02)), '12 fl oz at 5%');
    expect(describeIngestionDose(drink('{"volume":1,"volumeUnit":"shots","abv":40}', 14.02)), '1 shot at 40%');
    expect(describeIngestionDose(drink('{"volume":330,"volumeUnit":"ml","abv":5}', 12.9)), '330 ml at 5%');
    expect(describeIngestionDose(drink('{}', 28)), '2 standard drinks'); // e.g. imported with grams only
  });

  final reference = loadReference();
  final start = DateTime(2026, 7, 3, 20);

  group('series', () {
    test('LSD at a common dose peaks at about the dose factor and is labelled', () {
      final series = buildTimelineSeries(
        ingestions: [ingestion('lsd', 'sublingual', 100, start)],
        reference: reference,
        now: start.add(const Duration(hours: 1)),
      );
      expect(series, hasLength(1));
      expect(series.single.label, 'LSD 100 mg'.replaceAll('mg', 'mg'));
      expect(series.single.peak, closeTo(100 / 75, 1e-9));
      expect(series.single.points.first.$1, start);
    });

    test('an unknown dose falls back to the common dose so the timing still shows', () {
      final series = buildTimelineSeries(
        ingestions: [ingestion('mdma', 'oral', null, start)],
        reference: reference,
        now: start,
      );
      expect(series.single.peak, closeTo(1.0, 1e-9));
      expect(series.single.label, contains('dose unknown'));
    });

    test('cannabis uses its own route curve: edibles peak later than smoking', () {
      double peakMinute(String route, double dose) {
        final s = buildTimelineSeries(
          ingestions: [ingestion('cannabis', route, dose, start)],
          reference: reference,
          now: start,
        ).single;
        final best = s.points.reduce((a, b) => a.$2 >= b.$2 ? a : b);
        return best.$1.difference(start).inMinutes.toDouble();
      }

      expect(peakMinute('smoked', 3), lessThan(40));
      expect(peakMinute('oral', 10), greaterThan(90));
    });

    test('unknown substances are skipped instead of crashing', () {
      final series = buildTimelineSeries(
        ingestions: [ingestion('nope', 'oral', 1, start)],
        reference: reference,
        now: start,
      );
      expect(series, isEmpty);
    });

    test('a route the reference lacks borrows the nearest route instead of drawing nothing', () {
      final series = buildTimelineSeries(
        ingestions: [ingestion('lsd', 'oral', 100, start)], // only "sublingual" is published
        reference: reference,
        now: start,
      );
      expect(series, hasLength(1));
      expect(series.single.points.length, greaterThan(2));
    });

    test('several doses of one substance combine into one curve and each dose is marked', () {
      final times = [for (final m in [0, 30, 75]) start.add(Duration(minutes: m))];
      final series = buildTimelineSeries(
        ingestions: [
          for (var i = 0; i < times.length; i++) ingestion('alcohol', 'oral', 10, times[i], id: 'd$i'),
          ingestion('mdma', 'oral', 100, start, id: 'm'),
        ],
        reference: reference,
        now: start,
      );
      expect(series, hasLength(2)); // one per substance, not one per dose
      final alcohol = series.firstWhere((s) => s.label.startsWith('Alcohol'));
      expect(alcohol.doses, times);
      expect(alcohol.label, contains('3 doses'));
      expect(alcohol.label, contains('2.1 standard drinks')); // 30 g, not "30 g"
      final single = buildTimelineSeries(
        ingestions: [ingestion('alcohol', 'oral', 10, start)],
        reference: reference,
        now: start,
      ).single;
      expect(alcohol.peak, greaterThan(single.peak)); // the doses add up
    });
  });

  group('progress percent for the calendar badge', () {
    List<TimelineSeries> one(DateTime at) => buildTimelineSeries(
          ingestions: [ingestion('mdma', 'oral', 100, at)],
          reference: reference,
          now: at,
        );

    test('is 0 before the first dose, 100 once the curve has ended, and a whole number between', () {
      final series = one(start);
      final end = series.single.end;
      final total = end.difference(start);
      expect(experienceProgressPercent(series: series, now: start.subtract(const Duration(minutes: 1))), 0);
      expect(experienceProgressPercent(series: series, now: start), 0);
      expect(experienceProgressPercent(series: series, now: end), 100);
      expect(experienceProgressPercent(series: series, now: end.add(const Duration(days: 3))), 100);

      final half = experienceProgressPercent(series: series, now: start.add(total ~/ 2));
      expect(half, 50);
      final fifth = experienceProgressPercent(series: series, now: start.add(total ~/ 5));
      expect(fifth, 20);
      expect(fifth, isA<int>());
    });

    test('two people on the same day get independent percentages', () {
      final alice = one(start); // started at 20:00
      final bob = one(start.add(const Duration(hours: 2))); // started two hours later
      final now = start.add(const Duration(hours: 2, minutes: 30));
      final a = experienceProgressPercent(series: alice, now: now);
      final b = experienceProgressPercent(series: bob, now: now);
      expect(a, greaterThan(b));
      expect(b, greaterThan(0));
      expect(a, lessThan(100));
    });

    test('no series means 0', () {
      expect(experienceProgressPercent(series: const [], now: start), 0);
    });
  });

  group('chart', () {
    test('tick spacing keeps at most about eight labels', () {
      expect(TimelinePainter.tickStep(const Duration(hours: 2)), const Duration(minutes: 15));
      expect(TimelinePainter.tickStep(const Duration(hours: 8)), const Duration(hours: 1));
      expect(TimelinePainter.tickStep(const Duration(hours: 40)), const Duration(hours: 6));
      for (final h in [1, 3, 6, 12, 30, 90]) {
        final span = Duration(hours: h);
        expect(span.inMinutes / TimelinePainter.tickStep(span).inMinutes, lessThanOrEqualTo(8.5), reason: '$h h');
      }
    });

    testWidgets('hovering or tapping the chart shows a read-out without errors', (tester) async {
      final series = buildTimelineSeries(
        ingestions: [
          ingestion('alcohol', 'oral', 14, start, id: 'a'),
          ingestion('alcohol', 'oral', 14, start.add(const Duration(minutes: 40)), id: 'b'),
          ingestion('mdma', 'oral', 100, start, id: 'c'),
        ],
        reference: reference,
        now: start.add(const Duration(hours: 1)),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimelineChart(
            series: series,
            now: start.add(const Duration(hours: 1)),
            extraInfo: (t) => ['extra line'],
          ),
        ),
      ));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final box = tester.getRect(find.byType(TimelineChart));
      for (final f in [0.1, 0.4, 0.9, 1.5]) {
        await mouse.moveTo(Offset(box.left + box.width * f, box.center.dy)); // 1.5 is off the chart
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await mouse.moveTo(const Offset(-50, -50));
      await tester.tap(find.byType(TimelineChart));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders curves, markers and the Now line without errors', (tester) async {
      final series = buildTimelineSeries(
        ingestions: [
          ingestion('mdma', 'oral', 100, start, id: 'a'),
          ingestion('alcohol', 'oral', 25, start.add(const Duration(minutes: 90)), id: 'b'),
        ],
        reference: reference,
        now: start.add(const Duration(hours: 2)),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimelineChart(
            series: series,
            now: start.add(const Duration(hours: 2)),
            markers: [
              TimelineMarker(time: start.add(const Duration(hours: 1)), color: Colors.blue, label: 'note'),
              TimelineMarker(time: start.add(const Duration(hours: 3)), color: Colors.amber, label: '++', isRating: true),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('Timeline of 2 substances')), findsOneWidget);
    });

    testWidgets('an empty timeline renders a placeholder', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineChart(series: const [], now: start))));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Timeline with no ingestions'), findsOneWidget);
    });

    test('the painter range covers every curve and marker, and includes Now when it is near', () {
      final series = buildTimelineSeries(
        ingestions: [ingestion('lsd', 'sublingual', 100, start)],
        reference: reference,
        now: start,
      );
      final painter = TimelinePainter(
        series: series,
        markers: [TimelineMarker(time: start.add(const Duration(hours: 20)), color: Colors.red, label: 'late')],
        now: start.add(const Duration(hours: 22)),
        axisColor: Colors.black,
        gridColor: Colors.grey,
        textColor: Colors.black,
        nowColor: Colors.red,
      );
      final (from, to) = painter.range()!;
      expect(from.isBefore(start), isTrue);
      expect(to.isAfter(start.add(const Duration(hours: 20))), isTrue);
      expect(painter.yMax(), greaterThan(series.single.peak));
    });
  });
}
