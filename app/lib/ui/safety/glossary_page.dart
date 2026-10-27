import 'package:flutter/material.dart';

import '../../data/glossary.dart';
import '../design.dart';

/// What the words in the app mean, in plain language. Searchable, grouped by topic.
class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = _query.text;
    final matches = [for (final e in glossary) if (e.matches(q)) e];
    // With a search typed, show the answers already open.
    final open = q.trim().isNotEmpty && matches.length <= 4;

    return Scaffold(
      appBar: AppBar(title: const Text('Glossary')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              TextField(
                key: const ValueKey('glossary-search'),
                controller: _query,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search a word', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.md),
              if (matches.isEmpty)
                Padding(padding: const EdgeInsets.all(Gap.md), child: Text('Nothing matches "$q".', key: const ValueKey('glossary-empty'), style: text.bodyMedium)),
              for (final group in glossaryGroups)
                if (matches.any((e) => e.group == group)) ...[
                  Padding(padding: const EdgeInsets.only(top: Gap.md, bottom: 4), child: Text(group, style: text.titleMedium)),
                  for (final e in matches.where((e) => e.group == group))
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ExpansionTile(
                        key: ValueKey('term-${e.term}-${open ? 'open' : 'closed'}'),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        initiallyExpanded: open,
                        title: Text(e.term),
                        childrenPadding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(e.definition)],
                      ),
                    ),
                ],
              const SizedBox(height: Gap.md),
              Text(
                'General plain-language explanations, not medical advice. How things affect you depends on you, the substance and the situation.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
