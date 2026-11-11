import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/ui/charts/interactive_line_chart.dart';

void main() {
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2026, 11, 11);
  final series = ChartSeries(
    label: 'Cannabis',
    color: Colors.green,
    points: [for (var d = 0; d <= 10; d++) (from.add(Duration(days: d)), 10.0 - d)],
    format: (v) => v.toStringAsFixed(1),
  );

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

  testWidgets('dragging shows a readout with the date and each value, and markers draw', (tester) async {
    await tester.pumpWidget(host(InteractiveLineChart(
      series: [series],
      from: from,
      to: to,
      markers: [ChartMarker(DateTime(2026, 11, 5), 'Half')],
      bands: const [ChartBand(0, 0.5, 'Low', Color(0x2000FF00))],
      extraReadout: (at) => ['Half from here: later'],
    )));
    expect(find.byKey(const ValueKey('chart-readout')), findsNothing);

    final chart = tester.getRect(find.byType(InteractiveLineChart));
    await tester.dragFrom(chart.centerLeft + const Offset(60, 0), const Offset(120, 0));
    await tester.pump();
    final readout = find.byKey(const ValueKey('chart-readout'));
    expect(readout, findsOneWidget);
    expect(find.descendant(of: readout, matching: find.textContaining('Nov')), findsOneWidget);
    expect(find.descendant(of: readout, matching: find.textContaining('Cannabis: ')), findsOneWidget);
    expect(find.text('Half from here: later'), findsOneWidget);
  });

  testWidgets('an empty range says so', (tester) async {
    await tester.pumpWidget(host(InteractiveLineChart(series: [series], from: DateTime(2025, 1, 1), to: DateTime(2025, 2, 1))));
    expect(find.text('Nothing to show for this range.'), findsOneWidget);
  });

  testWidgets('range chips report the chosen span', (tester) async {
    ChartRange? picked;
    await tester.pumpWidget(host(RangeChips(value: ChartRange.month, onChanged: (r) => picked = r)));
    await tester.tap(find.byKey(const ValueKey('range-year')));
    expect(picked, ChartRange.year);
    expect(ChartRange.all.span, isNull);
  });
}
