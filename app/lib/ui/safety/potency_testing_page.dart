import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mushroom_reference.dart';
import '../design.dart';
import '../link_tile.dart';

/// "Get your batch tested": what a potency test can and cannot tell, how to read a certificate,
/// and a short list of services checked on their own websites. Neutral: no endorsement, no
/// sourcing, not legal advice. The content is assets/data/potency_testing.json.
class PotencyTestingPage extends ConsumerWidget {
  const PotencyTestingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final info = ref.watch(potencyTestingProvider).value ?? PotencyTestingInfo.empty;
    Widget bullet(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(s, style: text.bodyMedium)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Get your batch tested')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            key: const ValueKey('potency-testing-list'),
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Text(info.legal, key: const ValueKey('potency-testing-legal'), style: text.bodyMedium),
                ),
              ),
              const SizedBox(height: Gap.md),
              Text('What a test can tell you', style: text.titleMedium),
              const SizedBox(height: 4),
              for (final s in info.whatATestTells) bullet(s),
              const SizedBox(height: Gap.md),
              Text('Reading a lab certificate', style: text.titleMedium),
              const SizedBox(height: 4),
              for (final s in info.readingACertificate) bullet(s),
              const SizedBox(height: Gap.md),
              Text('Services', style: text.titleMedium),
              Text(
                'Checked on each service\'s own website on ${info.verified}. Rules, prices and legality change: check their current rules first. '
                'Listing is not an endorsement.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.sm),
              for (final s in info.services)
                Card(
                  key: ValueKey('testing-service-${s.name}'),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: text.titleSmall),
                      Text(s.kind, style: text.bodySmall),
                      const SizedBox(height: 4),
                      Text(s.tests, style: text.bodyMedium),
                      const SizedBox(height: 4),
                      Text(s.eligibility, style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                      LinkTile(s.url),
                      Text('Verified ${s.verified}', style: text.labelSmall),
                    ]),
                  ),
                ),
              if (info.checkedNotListed.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Text('Checked but not listed', style: text.titleMedium),
                Text('Drug-checking services where mushroom potency testing could not be confirmed:', style: text.bodySmall),
                const SizedBox(height: 4),
                for (final c in info.checkedNotListed) ...[
                  Text(c.name, style: text.titleSmall),
                  Text(c.reason, style: text.bodySmall),
                  LinkTile(c.url),
                  const SizedBox(height: Gap.sm),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
