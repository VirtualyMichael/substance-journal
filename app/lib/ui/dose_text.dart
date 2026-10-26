import 'dart:convert';

import '../data/database.dart';
import 'design.dart';

/// How an ingestion's dose reads in lists: "2 pills (240 mg)", "100 mg (est.)" or "dose unknown".
String describeIngestionDose(Ingestion ingestion) {
  final details = ingestion.detailsJson.isEmpty ? const <String, dynamic>{} : jsonDecode(ingestion.detailsJson) as Map<String, dynamic>;
  final count = (details['unitCount'] as num?)?.toDouble();
  final estimate = ingestion.doseIsEstimate ? ' (est.)' : '';
  if (ingestion.customUnitId != null && count != null) {
    final word = count == 1 ? details['unitSingular'] : details['unitPlural'];
    return '${formatDose(count, null)} $word (${formatDose(ingestion.dose, ingestion.unit)})$estimate';
  }
  return '${formatDose(ingestion.dose, ingestion.unit)}$estimate';
}
