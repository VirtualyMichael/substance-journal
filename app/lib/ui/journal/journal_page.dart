import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../add/add_ingestion_page.dart';
import '../design.dart';
import 'experience_page.dart';

/// Opens the add flow and, once saved, the experience it went into.
Future<void> startAddIngestion(BuildContext context, String personId, {String? substanceKey}) async {
  final experienceId = await Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => AddIngestionPage(personId: personId, initialSubstanceKey: substanceKey),
  ));
  if (experienceId != null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperiencePage(experienceId: experienceId)));
  }
}

class JournalPage extends ConsumerWidget {
  const JournalPage({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experiences = ref.watch(experiencesProvider(person.id)).value;
    final ingestions = ref.watch(personIngestionsProvider(person.id)).value ?? const <Ingestion>[];
    final reference = ref.watch(catalogProvider);

    if (experiences == null) return const Center(child: CircularProgressIndicator());

    final byExperience = <String, List<Ingestion>>{};
    for (final i in ingestions) {
      byExperience.putIfAbsent(i.experienceId, () => []).add(i);
    }

    if (experiences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: Gap.md),
              Text("${person.name}'s journal is empty", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.sm),
              const Text('Log your first ingestion to start an experience.'),
              const SizedBox(height: Gap.md),
              FilledButton.icon(
                key: const ValueKey('empty-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add ingestion'),
                onPressed: () => startAddIngestion(context, person.id),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    String? lastMonth;
    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    for (final e in experiences) {
      final month = '${monthNames[e.sortDate.month - 1]} ${e.sortDate.year}';
      if (month != lastMonth) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
          child: Text(month, style: Theme.of(context).textTheme.titleSmall),
        ));
        lastMonth = month;
      }
      final items = byExperience[e.id] ?? const <Ingestion>[];
      final keys = <String>[];
      for (final i in items) {
        if (!keys.contains(i.substanceKey)) keys.add(i.substanceKey);
      }
      children.add(Card(
        key: ValueKey('experience-${e.id}'),
        margin: const EdgeInsets.only(bottom: Gap.sm),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
          title: Text(e.title.isEmpty ? formatDateTime(e.sortDate) : e.title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in keys)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(backgroundColor: substanceColor(k), radius: 6),
                    label: Text(reference.byKey[k]?.name ?? k),
                  ),
                Text(
                  '${items.length} ${items.length == 1 ? 'ingestion' : 'ingestions'}'
                  '${e.title.isEmpty ? '' : '  |  ${formatDateTime(e.sortDate)}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          trailing: e.isFavorite ? const Icon(Icons.star, color: Colors.amber) : const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperiencePage(experienceId: e.id))),
        ),
      ));
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, 96),
          children: children,
        ),
      ),
    );
  }
}
