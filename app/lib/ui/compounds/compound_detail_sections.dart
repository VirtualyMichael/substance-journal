import 'package:flutter/material.dart';

import '../../data/compound_details.dart';
import '../design.dart';
import '../link_tile.dart';

/// What it is, how it works, typical effects, timing and harm-reduction notes for one compound,
/// with the sources they were written from.
class CompoundDetailSections extends StatelessWidget {
  const CompoundDetailSections({super.key, required this.detail, required this.details});

  final CompoundDetail detail;

  /// For looking up effect definitions.
  final CompoundDetails details;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget heading(String s) => Padding(padding: const EdgeInsets.only(top: Gap.md, bottom: 4), child: Text(s, style: text.titleMedium));
    return Column(
      key: const ValueKey('compound-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('What it is'),
        Text(detail.whatItIs, key: const ValueKey('details-what')),
        heading('How it works'),
        Text(detail.howItWorks, key: const ValueKey('details-how')),
        if (detail.effects.isNotEmpty) ...[
          heading('Typical effects'),
          Wrap(
            key: const ValueKey('details-effects'),
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final name in detail.effects)
                _EffectChip(name: name, info: details.effect(name)),
            ],
          ),
          const SizedBox(height: 4),
          Text('As the sources list them; not everyone feels all of these, and the dose, the person and the setting change them. Tap one to read what it means.',
              style: text.bodySmall),
        ],
        if (detail.timing.isNotEmpty) ...[
          heading('Timing'),
          Text(detail.timing, key: const ValueKey('details-timing')),
        ],
        if (detail.harmReduction.isNotEmpty) ...[
          heading('Harm-reduction notes'),
          for (final (i, n) in detail.harmReduction.indexed)
            Padding(
              key: ValueKey('details-harm-$i'),
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(right: 6), child: Text('-')),
                Expanded(child: Text(n)),
              ]),
            ),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('details-sources'),
            tilePadding: EdgeInsets.zero,
            title: Text('Sources for these sections', style: text.labelLarge),
            children: [
              for (final s in detail.sources)
                LinkTile(s.url, label: s.name, description: [s.usedFor, if (s.retrieved != null) 'Read ${s.retrieved}'].where((e) => e.isNotEmpty).join(' · ')),
            ],
          ),
        ),
      ],
    );
  }
}

class _EffectChip extends StatelessWidget {
  const _EffectChip({required this.name, this.info});
  final String name;
  final EffectInfo? info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    return ActionChip(
      key: ValueKey('effect-$name'),
      label: Text(name),
      visualDensity: VisualDensity.compact,
      avatar: i == null ? null : const Icon(Icons.info_outline, size: 16),
      onPressed: i == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(i.name),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.description),
                        LinkTile(i.url, label: 'Read more on PsychonautWiki'),
                      ],
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
                ),
              ),
    );
  }
}
