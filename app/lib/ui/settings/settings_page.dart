import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../alcohol/alcohol_settings.dart';
import '../units/custom_units_page.dart';
import 'pw_import_flow.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, required this.person});

  final Person person;

  Future<String?> _askName(BuildContext context, {String title = 'Name', String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('person-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('person-save'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final name = result?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final people = ref.watch(peopleProvider).value ?? const <Person>[];
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final prefs = ref.watch(compoundPrefsProvider(person.id)).value ?? const CompoundPrefs();
    final reference = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            Text('People', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Each person has their own journal, tolerance, history and warnings. Nothing is combined between people.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            for (final p in people)
              Card(
                key: ValueKey('person-${p.id}'),
                margin: const EdgeInsets.only(bottom: Gap.sm),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(p.colorValue),
                    child: Text(p.name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p.name),
                  subtitle: Text(p.id == person.id ? 'Showing now' : (p.isDefault ? 'Default' : '')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final name = await _askName(context, title: 'Rename', initial: p.name);
                          if (name != null) await db.renamePerson(p.id, name);
                        },
                      ),
                      if (!p.isDefault)
                        IconButton(
                          key: ValueKey('delete-person-${p.id}'),
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Delete ${p.name}?'),
                                content: const Text("All of this person's experiences and ingestions are removed."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  FilledButton(
                                    key: const ValueKey('confirm-delete-person'),
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              if (p.id == person.id) {
                                final fallback = people.firstWhere((x) => x.isDefault);
                                await db.setCurrentPerson(fallback.id);
                              }
                              await db.deletePerson(p.id);
                            }
                          },
                        ),
                    ],
                  ),
                  onTap: () => db.setCurrentPerson(p.id),
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('add-person'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add a person'),
              onPressed: () async {
                final name = await _askName(context, title: 'New person');
                if (name == null) return;
                final created = await db.addPerson(name, colorValue: _personColors[people.length % _personColors.length].toARGB32());
                await db.setCurrentPerson(created.id);
              },
            ),
            const SizedBox(height: Gap.lg),
            Text('Appearance', style: text.titleMedium),
            const SizedBox(height: Gap.sm),
            SegmentedButton<ThemeMode>(
              key: const ValueKey('theme-mode'),
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => db.setSetting('themeMode', s.first.name),
            ),
            const SizedBox(height: Gap.lg),
            AlcoholSettingsSection(person: person),
            const SizedBox(height: Gap.lg),
            Text('Custom units', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Save things like "1 pill = 120 mg" so you can log "2 pills".', style: text.bodySmall),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('manage-units'),
              icon: const Icon(Icons.medication_outlined),
              label: const Text('Manage custom units'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomUnitsPage())),
            ),
            const SizedBox(height: Gap.lg),
            Text('Import from PsychonautWiki Journal', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Export your journal from the PsychonautWiki Journal app, then choose the file here. '
              'Experiences, ingestions, notes, ratings, custom units and consumers come across; importing the same file twice adds nothing.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('import-pw-file'),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Choose an export...'),
              onPressed: () => runPwImport(context, ref),
            ),
            const SizedBox(height: Gap.lg),
            Text('Hidden compounds', style: text.titleMedium),
            const SizedBox(height: 4),
            if (prefs.hidden.isEmpty)
              Text("None. Hide compounds you never use from the compound list's menu.", style: text.bodySmall)
            else
              Wrap(
                spacing: Gap.sm,
                children: [
                  for (final key in prefs.hidden)
                    InputChip(
                      key: ValueKey('hidden-$key'),
                      label: Text(reference.byKey[key]?.name ?? key),
                      onDeleted: () => db.setHidden(person.id, key, false),
                      deleteButtonTooltipMessage: 'Show again',
                    ),
                ],
              ),
            const SizedBox(height: Gap.lg),
            Text('About', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Substance Journal keeps everything on your devices. Dose and duration reference data comes from '
              'PsychonautWiki, TripSit and Erowid; estimates are a guide, not medical advice. The nine core compounds were '
              'checked against several sources; the rest of the catalog is copied from PsychonautWiki (CC BY-SA 4.0, '
              'psychonautwiki.org) and has not been independently checked.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

const List<Color> _personColors = [
  Color(0xFF6750A4),
  Color(0xFFE07A5F),
  Color(0xFF3D9970),
  Color(0xFFD1495B),
  Color(0xFF2EB5C4),
  Color(0xFFE0A100),
];
