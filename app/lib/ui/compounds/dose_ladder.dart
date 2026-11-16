import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/dose_audit.dart';
import '../add/dose_widgets.dart' show doseClassColor, doseClassLabel;
import '../design.dart';
import '../link_tile.dart';

/// One rung of the dose ladder: its band, the range it covers in the route's unit, and what it means.
class DoseStep {
  const DoseStep(this.cls, this.from, this.to);
  final DoseClass cls;
  final double? from;

  /// Null for the open-ended heavy step.
  final double? to;
}

/// The five steps (threshold, low, common, high, heavy) a route publishes, in order. Threshold
/// runs up to where low begins; heavy is open-ended.
List<DoseStep> doseSteps(RouteOfAdministration roa) => [
      if (roa.doseThreshold != null) DoseStep(DoseClass.threshold, roa.doseThreshold, roa.doseLight?.min ?? roa.doseCommon?.min),
      if (roa.doseLight?.min != null) DoseStep(DoseClass.light, roa.doseLight!.min, roa.doseLight!.max),
      if (roa.doseCommon?.min != null) DoseStep(DoseClass.common, roa.doseCommon!.min, roa.doseCommon!.max),
      if (roa.doseStrong?.min != null) DoseStep(DoseClass.strong, roa.doseStrong!.min, roa.doseStrong!.max ?? roa.doseHeavy),
      if (roa.doseHeavy != null) DoseStep(DoseClass.heavy, roa.doseHeavy, null),
    ];

/// What each step tends to feel like, in plain words. Never a recommendation.
String doseStepMeaning(DoseClass c) => switch (c) {
      DoseClass.belowThreshold => 'Usually no noticeable effect.',
      DoseClass.threshold => 'Effects are barely noticeable, if at all.',
      DoseClass.light => 'Mild effects that are usually easy to manage.',
      DoseClass.common => 'The full effects most people describe.',
      DoseClass.strong => 'Strong effects that are harder to manage, with more side effects.',
      DoseClass.heavy => 'Very strong effects; the risk of a bad experience and of harm rises.',
    };

/// "0.25", "75", "1.5": no trailing zeros.
String trimNumber(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(v < 1 ? 3 : 2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// "75-150", "300+", "10-20".
String doseStepRange(DoseStep step) {
  if (step.to == null) return '${trimNumber(step.from!)}+';
  if (step.from == step.to) return trimNumber(step.from!);
  return '${trimNumber(step.from!)}-${trimNumber(step.to!)}';
}

/// The unit spelled out, so nobody confuses µg with mg.
String unitInWords(String unit) => switch (unit.replaceAll('μ', 'µ')) {
      'µg' || 'ug' || 'mcg' => 'µg (micrograms: 1000 µg = 1 mg)',
      'mg' => 'mg (milligrams: 1000 mg = 1 g)',
      'g' => 'g (grams)',
      'ml' || 'mL' => 'ml (millilitres)',
      _ => unit,
    };

/// A plainer equivalent for big or small numbers ("= 1.5 g", "= 250 mg"), or null.
String? plainEquivalent(double value, String unit) {
  final u = unit.replaceAll('μ', 'µ');
  if ((u == 'µg' || u == 'ug' || u == 'mcg') && value >= 1000) return '${trimNumber(value / 1000)} mg';
  if (u == 'mg' && value >= 1000) return '${trimNumber(value / 1000)} g';
  if (u == 'mg' && value < 1) return '${trimNumber(value * 1000)} µg';
  if (u == 'g' && value < 1) return '${trimNumber(value * 1000)} mg';
  return null;
}

String _equivalence(DoseStep step, String unit) {
  final a = step.from == null ? null : plainEquivalent(step.from!, unit);
  final b = step.to == null ? null : plainEquivalent(step.to!, unit);
  if (a == null && b == null) return '';
  if (step.to == null) return ' (${a!}+)';
  if (a != null && b != null) return ' (${a.split(' ').first}-$b)';
  return ' (${a ?? b})';
}

/// The dose ladder for one route: a colour bar of the five steps in order, then each step's
/// range and meaning, then where the numbers come from.
class DoseLadder extends StatelessWidget {
  const DoseLadder({super.key, required this.roa, required this.substance, this.audit});

  final RouteOfAdministration roa;
  final Substance substance;

  /// The cross-referenced audit for this route, when there is one.
  final AuditedRoute? audit;

  @override
  Widget build(BuildContext context) {
    final steps = doseSteps(roa);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (steps.isEmpty) {
      return Text('No dose bands are published for this route.', key: ValueKey('ladder-none-${roa.route}'), style: text.bodySmall);
    }
    return Column(
      key: ValueKey('dose-ladder-${roa.route}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Doses in ${unitInWords(roa.unit)}', key: ValueKey('ladder-unit-${roa.route}'), style: text.labelMedium),
        const SizedBox(height: Gap.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              for (final s in steps)
                Expanded(
                  child: Container(
                    key: ValueKey('ladder-bar-${roa.route}-${s.cls.name}'),
                    color: doseClassColor(scheme, s.cls),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: Column(
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: Text(doseClassLabel(s.cls), style: text.labelMedium)),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(doseStepRange(s), style: text.labelSmall)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        for (final s in steps)
          Padding(
            key: ValueKey('ladder-step-${roa.route}-${s.cls.name}'),
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4, right: Gap.sm),
                  decoration: BoxDecoration(color: doseClassColor(scheme, s.cls), shape: BoxShape.circle, border: Border.all(color: scheme.outline)),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${doseClassLabel(s.cls)}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '${doseStepRange(s)} ${roa.unit}${_equivalence(s, roa.unit)}. '),
                      TextSpan(text: doseStepMeaning(s.cls), style: text.bodySmall),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Published ranges, not advice. The same amount lands differently with body weight, tolerance, other substances and how pure it is.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        _Provenance(roa: roa, substance: substance, audit: audit),
      ],
    );
  }
}

/// "Checked against N sources", the spread when they disagree, and the sources themselves.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.roa, required this.substance, this.audit});

  final RouteOfAdministration roa;
  final Substance substance;
  final AuditedRoute? audit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = audit;
    if (a == null) {
      final line = substance.audited
          ? 'Checked by hand against ${substance.sources.length} sources (listed under Sources below)'
          : substance.crossChecked
              ? 'Two sources (PsychonautWiki and TripSit) within 50% of each other; not yet cross-checked by hand'
              : 'One source (PsychonautWiki) — not yet cross-checked';
      return Text(line, key: ValueKey('dose-sources-${roa.route}'), style: text.bodySmall);
    }
    final names = a.sources.map((s) => s.name.split(',').first.split(' (').first).toList();
    final headline = a.sources.length < 2
        ? 'One source (${names.first}): no second source publishes doses for this route, so confidence is low'
        : 'Checked against ${a.sources.length} sources: ${names.join(', ')}';
    final spread = a.agreement == AuditAgreement.agree ? null : _spread(a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headline, key: ValueKey('dose-sources-${roa.route}'), style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          'Confidence: ${a.confidence.name}. ${switch (a.agreement) {
            AuditAgreement.agree => 'The sources agree.',
            AuditAgreement.minorDifferences => 'The sources differ a little.',
            AuditAgreement.disagree => 'The sources disagree; the ladder uses the middle figure, or the lower one when only two differ.',
          }}',
          key: ValueKey('dose-agreement-${roa.route}'),
          style: text.bodySmall,
        ),
        if (spread != null) Text(spread, key: ValueKey('dose-spread-${roa.route}'), style: text.bodySmall),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('dose-source-list-${roa.route}'),
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text('How the sources compare', style: text.labelLarge),
            children: [
              if (a.note.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: Gap.sm), child: Text(a.note, style: text.bodySmall)),
              for (final s in a.sources)
                LinkTile(s.url, label: s.name, description: [s.bandsAsPublished, if (s.retrieved != null) 'Read ${s.retrieved}'].where((e) => e.isNotEmpty).join(' · ')),
            ],
          ),
        ),
      ],
    );
  }

  /// "Common: 75 - 150 µg (PsychonautWiki), 100-150ug (TripSit), 50 - 150 ug (Erowid)".
  static String? _spread(AuditedRoute a) {
    final parts = <String>[];
    for (final s in a.sources) {
      final m = RegExp(r'common ([^;]+)', caseSensitive: false).firstMatch(s.bandsAsPublished);
      if (m != null) parts.add('${m.group(1)!.trim()} (${s.name.split(',').first.split(' (').first})');
    }
    if (parts.length < 2) return null;
    return 'Common dose as each source publishes it: ${parts.join(', ')}';
  }
}
