import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';
import 'calendar/calendar_page.dart';
import 'compounds/compounds_page.dart';
import 'design.dart';
import 'journal/journal_page.dart';
import 'settings/settings_page.dart';

enum _Destination { journal, calendar, compounds, settings }

/// Navigation frame: a bottom bar on phones, a rail on wide windows. Shows the current
/// person's pages and a switcher to change who is on screen.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  _Destination _destination = _Destination.journal;

  static const _items = [
    (_Destination.journal, Icons.menu_book_outlined, Icons.menu_book, 'Journal'),
    (_Destination.calendar, Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
    (_Destination.compounds, Icons.science_outlined, Icons.science, 'Compounds'),
    (_Destination.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(currentPersonProvider);
    if (person == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final index = _destination.index;

    final body = switch (_destination) {
      // Keyed by person so no widget state (search text, scroll) leaks between people.
      _Destination.journal => JournalPage(key: ValueKey('journal-${person.id}'), person: person),
      _Destination.calendar => CalendarPage(key: ValueKey('calendar-${person.id}'), person: person),
      _Destination.compounds => CompoundsPage(key: ValueKey('compounds-${person.id}'), personId: person.id),
      _Destination.settings => SettingsPage(key: ValueKey('settings-${person.id}'), person: person),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_items[index].$4),
        actions: [PersonSwitcher(current: person), const SizedBox(width: Gap.sm)],
      ),
      floatingActionButton: _destination == _Destination.journal
          ? FloatingActionButton.extended(
              key: const ValueKey('journal-add'),
              heroTag: null,
              onPressed: () => startAddIngestion(context, person.id),
              icon: const Icon(Icons.add),
              label: const Text('Add ingestion'),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _destination = _Destination.values[i]),
              destinations: [
                for (final (_, icon, selected, label) in _items)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
              ],
            ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _destination = _Destination.values[i]),
                  destinations: [
                    for (final (_, icon, selected, label) in _items)
                      NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}

/// Chip in the app bar showing whose journal is open, with a menu to switch.
class PersonSwitcher extends ConsumerWidget {
  const PersonSwitcher({super.key, required this.current});

  final Person current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider).value ?? const <Person>[];
    return PopupMenuButton<String>(
      key: const ValueKey('person-switcher'),
      tooltip: 'Switch person',
      onSelected: (id) => ref.read(databaseProvider).setCurrentPerson(id),
      itemBuilder: (_) => [
        for (final p in people)
          CheckedPopupMenuItem<String>(
            key: ValueKey('switch-${p.id}'),
            value: p.id,
            checked: p.id == current.id,
            child: Text(p.name),
          ),
      ],
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: Color(current.colorValue),
          child: Text(current.name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        label: Text(current.name),
        deleteIcon: const Icon(Icons.arrow_drop_down),
        onDeleted: null,
      ),
    );
  }
}
