import 'dart:convert';

import '../data/alcohol_data.dart';
import '../data/database.dart';
import 'design.dart';

/// How an ingestion's dose reads in lists: "2 pills (240 mg)", "100 mg (est.)" or "dose unknown".
String describeIngestionDose(Ingestion ingestion) {
  if (ingestion.substanceKey == 'alcohol') return describeAlcoholDose(ingestion);
  final details = ingestion.detailsJson.isEmpty ? const <String, dynamic>{} : jsonDecode(ingestion.detailsJson) as Map<String, dynamic>;
  final count = (details['unitCount'] as num?)?.toDouble();
  final estimate = ingestion.doseIsEstimate ? ' (est.)' : '';
  if (ingestion.customUnitId != null && count != null) {
    final word = count == 1 ? details['unitSingular'] : details['unitPlural'];
    return '${formatDose(count, null)} $word (${formatDose(ingestion.dose, ingestion.unit)})$estimate';
  }
  return '${formatDose(ingestion.dose, ingestion.unit)}$estimate';
}

/// "12 fl oz at 5%" or "2 shots at 40%"; with no recorded volume, the standard drinks in the
/// grams of ethanol ("0.5 standard drinks"). Nobody thinks in grams of ethanol.
String describeAlcoholDose(Ingestion ingestion) {
  final d = DrinkDetails.of(ingestion);
  if (d.hasVolume) return '${alcoholVolumeText(d.volume!, d.volumeUnit!)} at ${_trim(d.abv!)}%';
  final grams = ingestion.dose;
  if (grams == null) return 'dose unknown';
  return '${_trim(grams / 14.0, digits: 1)} standard drinks';
}

String _trim(double v, {int digits = 1}) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(digits);

/// "12 fl oz", "1 shot", "330 ml".
String alcoholVolumeText(double volume, String unit) {
  final label = switch (unit) {
    'oz' => 'fl oz',
    'shots' => volume == 1 ? 'shot' : 'shots',
    _ => unit,
  };
  return '${_trim(volume)} $label';
}
