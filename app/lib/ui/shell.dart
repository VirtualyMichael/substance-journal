import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';
import 'alcohol/alcohol_analytics_page.dart';
import 'alcohol/alcohol_day_view.dart';
import 'alcohol/alcohol_history_page.dart';
import 'alcohol/recipes_page.dart';
import 'calendar/calendar_page.dart';
import 'compounds/compounds_page.dart';
import 'design.dart';
import 'insights/insights_page.dart';
import 'journal/journal_page.dart';
import 'settings/settings_page.dart';

enum _Destination { journal, calendar, compounds, insights, settings, today, history, analytics, recipes }

typedef _Item = (_Destination, IconData, IconData, String);

const List<_Item> _fullItems = [
  (_Destination.journal, Icons.menu_book_outlined, Icons.menu_book, 'Journal'),
  (_Destination.calendar, Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
  (_Destination.compounds, Icons.science_outlined, Icons.science, 'Compounds'),
  (_Destination.insights, Icons.insights_outlined, Icons.insights, 'Insights'),
  (_Destination.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
];

const List<_Item> _alcoholItems = [
  (_Destination.today, Icons.local_bar_outlined, Icons.local_bar, 'Today'),
  (_Destination.history, Icons.history, Icons.history, 'History'),
  (_Destination.recipes, Icons.menu_book_outlined, Icons.menu_book, 'Recipes'),
  (_Destination.analytics, Icons.insights_outlined, Icons.insights, 'Analytics'),
  (_Destination.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
];

/// Navigation frame: a bottom bar on phones, a rail on wide windows. Shows the current
/// person's pages and a switcher to change who is on screen. In Alcohol mode the same frame
/// holds the drink-tracker pages instead of the full journal.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool? _lastMode;

  @override
  void initState() {
    super.initState();
    // Start answering Wi-Fi sync requests from paired devices for as long as the app is open.
    ref.read(lanServerProvider);
  }

  Future<void> _setMode(bool on) async {
    final db = ref.read(databaseProvider);
    if (on) await db.ensureDefaultDrinkPresets();
    await db.setSetting('alcoholMode', on ? 'true' : 'false');
  }

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(currentPersonProvider);
    if (person == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final alcoholMode = ref.watch(alcoholModeProvider).value ?? false;
    // Switching mode swaps the whole set of pages, so start again at the first one.
    if (_lastMode != null && _lastMode != alcoholMode) _index = 0;
    _lastMode = alcoholMode;

    final items = alcoholMode ? _alcoholItems : _fullItems;
    final index = _index.clamp(0, items.length - 1);
    final destination = items[index].$1;
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    final body = switch (destination) {
      // Keyed by person so no widget state (search text, scroll) leaks between people.
      _Destination.journal => JournalPage(key: ValueKey('journal-${person.id}'), person: person),
      _Destination.calendar => CalendarPage(key: ValueKey('calendar-${person.id}'), person: person),
      _Destination.compounds => CompoundsPage(key: ValueKey('compounds-${person.id}'), personId: person.id),
      _Destination.insights => InsightsPage(key: ValueKey('insights-${person.id}'), person: person),
      _Destination.settings => SettingsPage(key: ValueKey('settings-${person.id}'), person: person),
      _Destination.today => AlcoholDayView(key: ValueKey('today-${person.id}'), person: person),
      _Destination.history => AlcoholHistoryPage(key: ValueKey('history-${person.id}'), person: person),
      _Destination.analytics => AlcoholAnalyticsPage(key: ValueKey('analytics-${person.id}'), person: person),
      _Destination.recipes => const RecipesPage(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(items[index].$4),
        actions: [
          IconButton(
            key: const ValueKey('mode-toggle'),
            tooltip: alcoholMode ? 'Back to the full journal' : 'Alcohol mode',
            icon: Icon(alcoholMode ? Icons.apps : Icons.local_bar_outlined),
            onPressed: () => _setMode(!alcoholMode),
          ),
          PersonSwitcher(current: person),
          const SizedBox(width: Gap.sm),
        ],
      ),
      floatingActionButton: destination == _Destination.journal
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
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final (_, icon, selected, label) in items)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
              ],
            ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final (_, icon, selected, label) in items)
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
