import 'reference.dart';
import 'tolerance.dart';

/// A heads-up about a dose being logged. These inform; they never block.
enum AdvisoryLevel { note, caution }

class DoseAdvisory {
  const DoseAdvisory(this.level, this.title, this.detail);
  final AdvisoryLevel level;
  final String title;
  final String detail;
}

/// A dose already in the journal, reduced to what the advisories need.
class PastDose {
  const PastDose({required this.substanceKey, required this.route, required this.time, this.dose, this.unit});
  final String substanceKey;
  final String route;
  final DateTime time;
  final double? dose;
  final String? unit;
}

String _span(Duration d) {
  if (d.inMinutes < 90) return '${d.inMinutes} min';
  if (d.inHours < 48) return '${(d.inMinutes / 60).toStringAsFixed(d.inMinutes % 60 == 0 ? 0 : 1)} h';
  return '${d.inDays} days';
}

String _amount(double v, String unit) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} $unit';

/// Notes for a dose of [substance] by [roa] taken at [at].
///
/// - A dose in the strong or heavy band of its route.
/// - A repeat dose while the previous one is still active, with the onset time spelled out:
///   re-dosing before the first has started working is a common way to take too much.
/// - A 24-hour total at or above the heavy dose.
/// - Tolerance from recent use of the same substance or its tolerance group.
///
/// Reference doses are for the route and unit shown, so substances without published bands
/// (custom compounds) get only the repeat-dose and tolerance notes. Alcohol is skipped: its
/// numbers are grams of ethanol and Alcohol mode has a blood-alcohol estimate instead.
List<DoseAdvisory> doseAdvisories({
  required Substance substance,
  required RouteOfAdministration roa,
  required double? dose,
  required DateTime at,
  required List<PastDose> past,
  required Map<String, Substance> byKey,
}) {
  if (substance.key == 'alcohol') return const [];
  final result = <DoseAdvisory>[];

  if (dose != null) {
    final cls = classifyDose(roa, dose);
    if (cls == DoseClass.heavy) {
      result.add(DoseAdvisory(
        AdvisoryLevel.caution,
        'Heavy dose',
        '${_amount(dose, roa.unit)} is at or above the published heavy dose (${_amount(roa.doseHeavy!, roa.unit)}). '
            'Risks rise steeply at this level, and a lower dose is safer.',
      ));
    } else if (cls == DoseClass.strong) {
      result.add(DoseAdvisory(
        AdvisoryLevel.note,
        'Strong dose',
        'This is in the strong range for this route. Effects will be intense and last longer.',
      ));
    }
  }

  final sameSubstance = [
    for (final p in past)
      if (p.substanceKey == substance.key && p.time.isBefore(at) && at.difference(p.time) < const Duration(days: 3)) p,
  ]..sort((a, b) => b.time.compareTo(a.time));

  if (sameSubstance.isNotEmpty) {
    final last = sameSubstance.first;
    final gap = at.difference(last.time);
    final total = roa.duration('total')?.maxMinutes;
    final onset = roa.duration('onset')?.maxMinutes;
    final active = total != null ? Duration(minutes: total.round()) : null;
    if (active != null && gap < active) {
      final lastText = last.dose != null && last.unit != null ? '${_amount(last.dose!, last.unit!)} ' : '';
      final notStarted = onset != null && gap < Duration(minutes: onset.round());
      result.add(DoseAdvisory(
        AdvisoryLevel.caution,
        'Still active from ${_span(gap)} ago',
        'You logged $lastText${_span(gap)} ago. '
            '${notStarted ? 'It may not have started working yet; onset can take up to ${_span(Duration(minutes: onset.round()))}. ' : ''}'
            'Waiting for the full effect before deciding on more is the safer habit.',
      ));
    }

    final heavy = roa.doseHeavy;
    if (dose != null && heavy != null) {
      var sum = dose;
      var counted = 0;
      for (final p in sameSubstance) {
        if (at.difference(p.time) <= const Duration(hours: 24) && p.dose != null && p.unit == roa.unit) {
          sum += p.dose!;
          counted++;
        }
      }
      if (counted > 0 && sum >= heavy && dose < heavy) {
        result.add(DoseAdvisory(
          AdvisoryLevel.caution,
          'High total today',
          'With the earlier dose${counted > 1 ? 's' : ''}, that is ${_amount(sum, roa.unit)} in 24 hours, '
              'at or above the heavy dose for one go (${_amount(heavy, roa.unit)}).',
        ));
      }
    }
  }

  if (substance.hasTolerance) {
    final track = toleranceTrackKey(substance);
    final events = [for (final p in past) UseEvent(p.substanceKey, p.time)];
    final level = currentToleranceLevel(events, byKey, track, at);
    if (level >= 0.25) {
      final recent = [
        for (final p in past)
          if (p.time.isBefore(at) && byKey[p.substanceKey] != null && byKey[p.substanceKey]!.hasTolerance && toleranceTrackKey(byKey[p.substanceKey]!) == track) p,
      ]..sort((a, b) => b.time.compareTo(a.time));
      final ago = recent.isEmpty ? '' : ' Last use ${_span(at.difference(recent.first.time))} ago.';
      result.add(DoseAdvisory(
        AdvisoryLevel.note,
        'Tolerance is up',
        'Recent use means effects will be weaker than usual.$ago '
            'Raising the dose to compensate raises the risk too; waiting lets tolerance fall.',
      ));
    }
  }
  return result;
}
