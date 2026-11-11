import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../toast.dart';
import '../alcohol/alcohol_settings.dart';
import '../units/custom_units_page.dart';
import '../sync/sync_page.dart';
import 'backup_section.dart';
import 'clinician_report_section.dart';
import 'csv_export_section.dart';
import 'digest_section.dart';
import 'live_curve_section.dart';
import 'lock_section.dart';
import '../products/products_page.dart';
import '../safety/glossary_page.dart';
import '../safety/research_page.dart';
import '../testing/testing_page.dart';
import '../safety/safer_use_page.dart';
import 'reminders_section.dart';
import 'pw_import_flow.dart';
import 'background_section.dart';
import '../lock/lock_gate.dart';
import '../background/app_background.dart';

const List<Color> _accentChoices = [
  Color(0xFF4F7CAC),
  Color(0xFF6750A4),
  Color(0xFFD1495B),
  Color(0xFFE07A5F),
  Color(0xFFE0A100),
  Color(0xFF3D9970),
  Color(0xFF2EB5C4),
  Color(0xFF7A6FF0),
];

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


/// The groups Settings is split into. Each opens on its own, so no page is a long scroll.
enum SettingsCategory {
  people('People', Icons.people_outline),
  appearance('Appearance', Icons.palette_outlined),
  alcohol('Alcohol', Icons.local_bar_outlined),
  reminders('Reminders and notifications', Icons.notifications_outlined),
  sync('Sync', Icons.sync),
  security('Privacy and security', Icons.lock_outline),
  backup('Backup, export and import', Icons.save_alt_outlined),
  ai('Summary for an AI', Icons.smart_toy_outlined),
  data('Units, products and reference', Icons.menu_book_outlined),
  about('About', Icons.info_outline);

  const SettingsCategory(this.title, this.icon);
  final String title;
  final IconData icon;
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory _selected = SettingsCategory.people;

  String _summary(SettingsCategory c) {
    final people = ref.watch(peopleProvider).value ?? const <Person>[];
    final theme = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final lock = ref.watch(lockConfigProvider).value;
    final background = ref.watch(backgroundProvider).value;
    return switch (c) {
      SettingsCategory.people => people.isEmpty ? 'Who the journal is for' : people.map((p) => p.name).join(', '),
      SettingsCategory.appearance => '${theme.name[0].toUpperCase()}${theme.name.substring(1)} theme, ${background == null || !background.active ? 'no background' : 'background on'}',
      SettingsCategory.alcohol => 'Drinks, limits and estimates',
      SettingsCategory.reminders => 'Reminders and the live curve',
      SettingsCategory.sync => 'Phone and computer, automatic sync',
      SettingsCategory.security => (lock?.enabled ?? false) ? 'App lock on, journal encrypted' : 'App lock off, journal encrypted',
      SettingsCategory.backup => 'Backups, exports and imports',
      SettingsCategory.ai => 'A summary for an AI tool',
      SettingsCategory.data => 'Custom units, products, glossary, safer use',
      SettingsCategory.about => 'Sources and credits',
    };
  }

  Widget _list({required bool wide}) {
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        for (final c in SettingsCategory.values)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Card(
              clipBehavior: Clip.antiAlias,
              color: wide && _selected == c ? Theme.of(context).colorScheme.secondaryContainer : null,
              child: ListTile(
                key: ValueKey('settings-${c.name}'),
                leading: Icon(c.icon),
                title: Text(c.title),
                subtitle: Text(_summary(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: wide ? null : const Icon(Icons.chevron_right),
                onTap: () {
                  if (wide) {
                    setState(() => _selected = c);
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsCategoryPage(category: c, person: widget.person)));
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 900) {
          // On a wide screen the groups sit beside what they contain.
          return Row(
            children: [
              SizedBox(width: 340, child: _list(wide: true)),
              const VerticalDivider(width: 1),
              Expanded(child: SettingsCategoryBody(key: ValueKey('settings-body-${_selected.name}'), category: _selected, person: widget.person)),
            ],
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _list(wide: false)),
        );
      },
    );
  }
}

/// One group on its own screen (phones).
class SettingsCategoryPage extends StatelessWidget {
  const SettingsCategoryPage({super.key, required this.category, required this.person});

  final SettingsCategory category;
  final Person person;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(category.title)),
        body: SettingsCategoryBody(category: category, person: person),
      );
}

class SettingsCategoryBody extends ConsumerWidget {
  const SettingsCategoryBody({super.key, required this.category, required this.person});

  final SettingsCategory category;
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final people = ref.watch(peopleProvider).value ?? const <Person>[];
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final prefs = ref.watch(compoundPrefsProvider(person.id)).value ?? const CompoundPrefs();
    final reference = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;

    final List<Widget> children = switch (category) {
      SettingsCategory.people => [
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
      ],
      SettingsCategory.appearance => [
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
            const SizedBox(height: Gap.md),
            Text('Accent colour', style: text.titleSmall),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final c in _accentChoices)
                  Semantics(
                    button: true,
                    selected: ref.watch(accentColorProvider).value?.toARGB32() == c.toARGB32(),
                    label: 'Accent colour',
                    child: InkWell(
                      key: ValueKey('accent-${c.toARGB32().toRadixString(16)}'),
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        await db.setSetting('accentColor', '${c.toARGB32()}');
                        await db.setSetting('rainbowAccent', 'false');
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: c,
                        child: (ref.watch(accentColorProvider).value?.toARGB32() ?? 0xFF4F7CAC) == c.toARGB32() && !(ref.watch(rainbowAccentProvider).value ?? false)
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('rainbow-accent'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Rainbow accent'),
              subtitle: const Text('Slowly drifts through colours. Uses a little more battery.'),
              value: ref.watch(rainbowAccentProvider).value ?? false,
              onChanged: (v) => db.setSetting('rainbowAccent', v ? 'true' : 'false'),
            ),
            const SizedBox(height: Gap.lg),
            const BackgroundSection(),
      ],
      SettingsCategory.alcohol => [AlcoholSettingsSection(person: person)],
      SettingsCategory.reminders => [const RemindersSection(), const SizedBox(height: Gap.lg), const LiveCurveSection()],
      SettingsCategory.sync => [
            Text('Sync', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Devices on the same Wi-Fi with the app open update each other within seconds of a change. For anything else use QR codes, a file, or text. No account or server.',
              style: text.bodySmall,
            ),
            const _AutoSyncStatus(),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-activity'),
              icon: const Icon(Icons.history),
              label: const Text('Recent messages'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityPage())),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-sync'),
              icon: const Icon(Icons.sync),
              label: const Text('Sync devices'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncPage())),
            ),
      ],
      SettingsCategory.security => [const LockSection()],
      SettingsCategory.backup => [
            const BackupSection(),
            const SizedBox(height: Gap.lg),
            ClinicianReportSection(person: person),
            const SizedBox(height: Gap.lg),
            CsvExportSection(person: person),
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
      ],
      SettingsCategory.ai => [DigestSection(person: person)],
      SettingsCategory.data => [
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
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('manage-products'),
              icon: const Icon(Icons.grass),
              label: const Text('Cannabis products'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductsPage())),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-testing'),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Drug checking log'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TestingPage())),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-glossary-settings'),
              icon: const Icon(Icons.abc),
              label: const Text('Glossary'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryPage())),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-research'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Research and resources'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResearchPage())),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('open-safer-use'),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('Safer use'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SaferUsePage())),
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
      ],
      SettingsCategory.about => [
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
    };

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(Gap.md), children: children),
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

/// "Last synced 2 min ago", from the automatic sync running in this app.
class _AutoSyncStatus extends ConsumerWidget {
  const _AutoSyncStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(autoSyncProvider);
    if (auto == null) return const SizedBox.shrink();
    return ValueListenableBuilder<DateTime?>(
      valueListenable: auto.lastSynced,
      builder: (context, at, _) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          at == null ? 'Not synced yet since the app opened.' : 'Last synced ${relativeTime(at, DateTime.now())}.',
          key: const ValueKey('auto-sync-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
