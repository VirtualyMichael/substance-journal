import 'package:flutter/material.dart';

import '../../data/research_links.dart';
import '../design.dart';
import '../link_tile.dart';
import 'glossary_page.dart';

/// Where to read more before taking something: the reference sites this app is built on, plus
/// testing and support services. Links open in the browser.
class ResearchPage extends StatelessWidget {
  const ResearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Research and resources')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                'No single source is complete or always right. Read more than one, and treat anything you cannot confirm as unknown. '
                'Opening a link leaves the app and uses your browser.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                key: const ValueKey('open-glossary'),
                icon: const Icon(Icons.abc),
                label: const Text('Glossary: what the words mean'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryPage())),
              ),
              const SizedBox(height: Gap.md),
              for (final (group, links) in researchHub) ...[
                Text(group, style: text.titleMedium),
                const SizedBox(height: 4),
                for (final l in links) LinkTile(l.url, label: l.title, description: l.description),
                const SizedBox(height: Gap.md),
              ],
              Text(
                'Information on these sites belongs to their authors. This app links to it and does not copy it.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
