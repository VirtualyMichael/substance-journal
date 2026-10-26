import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import '../design.dart';

/// Heads-ups under the dose field: strong or heavy dose, a repeat dose, a high daily total,
/// raised tolerance. They inform and never stop you logging.
class AdvisoryList extends StatelessWidget {
  const AdvisoryList({super.key, required this.advisories});

  final List<DoseAdvisory> advisories;

  @override
  Widget build(BuildContext context) {
    if (advisories.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('advisories'),
      children: [
        for (final a in advisories)
          Card(
            margin: const EdgeInsets.only(top: Gap.sm),
            color: a.level == AdvisoryLevel.caution ? scheme.errorContainer : scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    a.level == AdvisoryLevel.caution ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: a.level == AdvisoryLevel.caution ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(a.detail, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
