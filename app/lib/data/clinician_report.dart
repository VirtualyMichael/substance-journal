import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sj_core/sj_core.dart';

import 'alcohol_data.dart';
import 'database.dart';
import 'reference_repository.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
/// The PDF's built-in font covers Latin-1 only; anything else (emoji, other scripts) becomes "?" rather than a gap.
String _safe(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x3BC) {
      out.writeCharCode(0xB5); // Greek mu to the micro sign, as in "ug"
    } else if (r <= 0xFF) {
      out.writeCharCode(r);
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class SubstanceRow {
  SubstanceRow(this.name);
  final String name;
  int doses = 0;
  final days = <DateTime>{};
  final totals = <String, double>{};
  final routes = <String>{};
  DateTime? last;

  String get total => totals.isEmpty ? '-' : totals.entries.map((e) => _safe('${_num(e.value)} ${e.key}')).join(' + ');
}

class ReportSession {
  const ReportSession({required this.when, required this.title, required this.items, required this.notes, required this.rating});
  final DateTime when;
  final String title;
  final List<String> items;
  final String notes;
  final String rating;
}

/// Everything one person's summary says, worked out before any drawing so it can be tested.
class ReportData {
  const ReportData({
    required this.personName,
    required this.from,
    required this.to,
    required this.generated,
    required this.substances,
    required this.alcoholDrinks,
    required this.alcoholDays,
    required this.alcoholMaxDay,
    required this.alcoholMaxDate,
    required this.sessions,
    required this.activeDays,
  });

  final String personName;
  final DateTime from;
  final DateTime to;
  final DateTime generated;
  final List<SubstanceRow> substances;

  /// Standard drinks in the period, the days with any drinking, and the heaviest day.
  final double alcoholDrinks;
  final int alcoholDays;
  final double alcoholMaxDay;
  final DateTime? alcoholMaxDate;
  final List<ReportSession> sessions;
  final int activeDays;

  int get days => to.difference(from).inDays + 1;
  double get alcoholPerWeek => days <= 0 ? 0 : alcoholDrinks / (days / 7);
  double get alcoholPerDrinkingDay => alcoholDays == 0 ? 0 : alcoholDrinks / alcoholDays;
}

/// Builds one person's summary for [from] to [to] (whole days). Pass only that person's rows.
ReportData buildReportData({
  required Person person,
  required Iterable<Ingestion> ingestions,
  required Iterable<Experience> experiences,
  required Iterable<Rating> ratings,
  required ReferenceRepository reference,
  required EstimateSettings alcoholSettings,
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day + 1);
  final inRange = [
    for (final i in ingestions)
      if (!i.deleted && !i.time.isBefore(start) && i.time.isBefore(end)) i,
  ]..sort((a, b) => a.time.compareTo(b.time));

  final rows = <String, SubstanceRow>{};
  final allDays = <DateTime>{};
  for (final i in inRange) {
    if (i.substanceKey == 'alcohol') continue;
    final name = _safe(reference.byKey[i.substanceKey]?.name ?? i.substanceKey);
    final r = rows.putIfAbsent(i.substanceKey, () => SubstanceRow(name));
    r.doses++;
    final day = DateTime(i.time.year, i.time.month, i.time.day);
    r.days.add(day);
    allDays.add(day);
    r.routes.add(i.route);
    if (i.dose != null && i.unit != null && i.unit!.isNotEmpty) r.totals[i.unit!] = (r.totals[i.unit!] ?? 0) + i.dose!;
    if (r.last == null || i.time.isAfter(r.last!)) r.last = i.time;
  }

  final drinks = [for (final i in inRange) if (i.substanceKey == 'alcohol') i];
  final perDay = dailyStandardDrinks(drinks, alcoholSettings);
  allDays.addAll(perDay.keys);
  DateTime? maxDate;
  var maxDay = 0.0;
  perDay.forEach((d, v) {
    if (v > maxDay) {
      maxDay = v;
      maxDate = d;
    }
  });

  final byExperience = <String, List<Ingestion>>{};
  for (final i in inRange) {
    byExperience.putIfAbsent(i.experienceId, () => []).add(i);
  }
  final ratingByExperience = <String, String>{};
  for (final r in ratings) {
    if (r.deleted || r.shulgin == null) continue;
    ratingByExperience[r.experienceId] = r.shulgin!;
  }
  const shulgin = {'minus': '-', 'plusMinus': '+/-', 'plus1': '+', 'plus2': '++', 'plus3': '+++', 'plus4': '++++'};
  final sessions = <ReportSession>[];
  for (final e in experiences) {
    final items = byExperience[e.id];
    if (e.deleted || items == null || items.isEmpty) continue;
    sessions.add(ReportSession(
      when: items.first.time,
      title: _safe(e.title),
      items: [
        for (final i in items)
          _safe('${reference.byKey[i.substanceKey]?.name ?? i.substanceKey}'
              '${i.dose == null ? '' : ' ${_num(i.dose!)} ${i.unit ?? ''}'.trimRight()} (${i.route})'),
      ],
      notes: _safe(e.notes),
      rating: shulgin[ratingByExperience[e.id]] ?? '',
    ));
  }
  sessions.sort((a, b) => a.when.compareTo(b.when));

  return ReportData(
    personName: _safe(person.name),
    from: start,
    to: DateTime(to.year, to.month, to.day),
    generated: now,
    substances: rows.values.toList()..sort((a, b) => b.doses.compareTo(a.doses)),
    alcoholDrinks: perDay.values.fold(0.0, (a, b) => a + b),
    alcoholDays: perDay.values.where((v) => v > 0).length,
    alcoholMaxDay: maxDay,
    alcoholMaxDate: maxDate,
    sessions: sessions,
    activeDays: allDays.length,
  );
}

/// The summary as a PDF: an overview a person can hand to a clinician or keep for themselves.
Future<Uint8List> buildReportPdf(ReportData d) async {
  final doc = pw.Document(title: 'Substance use summary', author: 'Substance Journal');
  final small = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  final head = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);

  pw.Widget table(List<String> header, List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: header,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Self-reported and estimated. Generated by Substance Journal on ${_day(d.generated)}. Page ${c.pageNumber} of ${c.pagesCount}',
        style: small,
      ),
    ),
    build: (c) => [
      pw.Text('Substance use summary', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text('${d.personName}  |  ${_day(d.from)} to ${_day(d.to)} (${d.days} days)', style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
        child: pw.Text(
          'This is a personal log kept by the person named above. Doses and times are as they recorded them and may be approximate. '
          'Alcohol is shown in standard drinks (about 14 g of pure alcohol each). It is not a medical record and not a diagnosis.',
          style: small,
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Text('At a glance', style: head),
      pw.SizedBox(height: 4),
      table(['Days with any use', 'Compounds logged', 'Sessions'], [
        ['${d.activeDays} of ${d.days}', '${d.substances.length + (d.alcoholDrinks > 0 ? 1 : 0)}', '${d.sessions.length}'],
      ]),
      if (d.alcoholDrinks > 0) ...[
        pw.SizedBox(height: 12),
        pw.Text('Alcohol', style: head),
        pw.SizedBox(height: 4),
        table(['Standard drinks', 'Drinking days', 'Per drinking day', 'Per week', 'Heaviest day'], [
          [
            _num(d.alcoholDrinks),
            '${d.alcoholDays}',
            _num(d.alcoholPerDrinkingDay),
            _num(d.alcoholPerWeek),
            d.alcoholMaxDate == null ? '-' : '${_num(d.alcoholMaxDay)} on ${_day(d.alcoholMaxDate!)}',
          ],
        ]),
      ],
      if (d.substances.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text('Other substances', style: head),
        pw.SizedBox(height: 4),
        table(
          ['Compound', 'Doses', 'Days', 'Total dose', 'Routes', 'Last used'],
          [
            for (final s in d.substances) [s.name, '${s.doses}', '${s.days.length}', s.total, s.routes.join(', '), s.last == null ? '-' : _day(s.last!)],
          ],
        ),
      ],
      pw.SizedBox(height: 12),
      pw.Text('Sessions', style: head),
      pw.SizedBox(height: 4),
      if (d.sessions.isEmpty) pw.Text('Nothing was logged in this period.', style: small),
      for (final s in d.sessions)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${_day(s.when)}${s.title.isEmpty ? '' : '  -  ${s.title}'}${s.rating.isEmpty ? '' : '  (intensity ${s.rating})'}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(s.items.join('; '), style: const pw.TextStyle(fontSize: 9)),
              if (s.notes.isNotEmpty) pw.Text('Notes: ${s.notes}', style: small),
            ],
          ),
        ),
    ],
  ));
  return doc.save();
}
