import 'dart:convert';
import 'dart:typed_data';

import 'database.dart';
import 'reference_repository.dart';

const csvHeader = [
  'date',
  'time',
  'end_time',
  'compound',
  'route',
  'dose',
  'unit',
  'dose_is_estimate',
  'absorbed_mg',
  'method',
  'product',
  'experience',
  'notes',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// One CSV field. Anything a spreadsheet could read as a formula is prefixed with an apostrophe so
/// opening the file in Excel never runs text that came from a note or a product name.
String csvField(Object? value) {
  var s = value == null ? '' : '$value';
  if (s.isNotEmpty && '=+@\t\r'.contains(s[0]) || (s.startsWith('-') && double.tryParse(s) == null)) s = "'$s";
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// Every logged dose for one person, oldest first, one row each. Local time, as it was logged.
String buildIngestionsCsv({
  required Iterable<Ingestion> ingestions,
  required Iterable<Experience> experiences,
  required Iterable<Product> products,
  required ReferenceRepository reference,
}) {
  final titles = {for (final e in experiences) e.id: e.title};
  final productNames = {for (final p in products) p.id: p.name};
  final rows = [for (final i in ingestions) if (!i.deleted) i]..sort((a, b) => a.time.compareTo(b.time));
  final out = StringBuffer()..write('${csvHeader.join(',')}\r\n');
  for (final i in rows) {
    final fields = <Object?>[
      _date(i.time),
      _clock(i.time),
      i.endTime == null ? '' : _clock(i.endTime!),
      reference.byKey[i.substanceKey]?.name ?? i.substanceKey,
      i.route,
      i.dose == null ? '' : formatPlain(i.dose!),
      i.unit ?? '',
      i.doseIsEstimate ? 'yes' : 'no',
      i.absorbedMg == null ? '' : formatPlain(i.absorbedMg!),
      i.method ?? '',
      productNames[i.productId] ?? '',
      titles[i.experienceId] ?? '',
      i.notes,
    ];
    out.write('${fields.map(csvField).join(',')}\r\n');
  }
  return out.toString();
}

/// 12.0 -> "12", 0.25 -> "0.25": no trailing zeros, no exponent.
String formatPlain(double v) {
  final s = v.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

/// UTF-8 with a byte-order mark, so Excel reads accents and symbols (like the ug sign) correctly.
Uint8List csvBytes(String csv) => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
