import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../data/reagent_tests.dart';
import '../../providers.dart';
import '../design.dart';
import '../testing/testing_page.dart';
import 'dose_widgets.dart';

/// Optional link from a dose to a sample in the drug-checking log. Choosing one shows what its tests
/// found, with a strong warning if any test did not match or was positive. It never says "safe".
class DoseSampleBar extends ConsumerWidget {
  const DoseSampleBar({super.key, required this.substance, required this.value, required this.onChanged});

  final Substance substance;
  final DoseInput value;
  final ValueChanged<DoseInput> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = [for (final p in ref.watch(samplesProvider).value ?? const <Product>[]) if (p.substanceKey == substance.key) p];
    // Legal everyday products have nothing to test; everything else gets the offer.
    if (samples.isEmpty && suggestedTests(substance.key).isEmpty) return const SizedBox.shrink();
    final tests = ref.watch(reagentTestsProvider).value ?? const <ReagentTest>[];
    final chosen = samples.where((p) => p.id == value.productId).firstOrNull;
    final summary = chosen == null ? null : SampleSummary.of(tests, chosen.id);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (samples.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: const ValueKey('dose-sample-pick'),
              initialValue: chosen?.id,
              decoration: const InputDecoration(labelText: 'Sample from your drug checking log (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('None')),
                for (final p in samples)
                  DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(switch (SampleSummary.of(tests, p.id).status) {
                      SampleStatus.flagged => '${p.name}  (flagged)',
                      SampleStatus.checked => '${p.name}  (tested)',
                      SampleStatus.untested => '${p.name}  (not tested)',
                    }),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return onChanged(value.copyWith(clearProduct: true));
                final p = samples.firstWhere((s) => s.id == id);
                onChanged(value.copyWith(productId: p.id, productName: p.name));
              },
            ),
          if (summary != null)
            Container(
              key: const ValueKey('dose-sample-status'),
              margin: const EdgeInsets.only(top: Gap.sm),
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(
                color: summary.status == SampleStatus.flagged ? scheme.errorContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.headline, style: text.titleSmall),
                  for (final t in summary.tests.take(3)) Text(describeTest(t), style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(summary.caution, style: text.bodySmall),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dose-test-sample'),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: Text(samples.isEmpty ? 'Test a sample first (reagent or strip)' : 'Test a sample'),
              onPressed: () => openTestEditor(context, substanceKey: substance.key),
            ),
          ),
        ],
      ),
    );
  }
}
