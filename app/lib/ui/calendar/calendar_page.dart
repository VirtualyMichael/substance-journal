import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../journal/experience_page.dart';
import 'calendar_data.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A month calendar of experiences. A day with more than one person on it carries a badge
/// showing how far through each of them is, as whole-number percentages.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, required this.person});

  /// Whose journal is open: their own experiences get substance dots on every day.
  final Person person;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month = DateTime(ref.read(clockProvider)().year, ref.read(clockProvider)().month);

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final people = ref.watch(peopleProvider).value ?? const <Person>[];
    final experiences = ref.watch(allExperiencesProvider).value ?? const <Experience>[];
    final ingestions = ref.watch(allIngestionsProvider).value ?? const <Ingestion>[];
    final catalog = ref.watch(catalogProvider);

    final grid = monthGrid(_month);
    final days = buildCalendar(
      people: people,
      experiences: experiences,
      ingestions: ingestions,
      reference: catalog,
      now: now,
      from: grid.first,
      to: grid.last,
    );
    final today = dayOnly(now);
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final cellHeight = wide ? 92.0 : 76.0;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('month-prev'),
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    key: const ValueKey('month-title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('month-next'),
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shift(1),
                ),
                TextButton(
                  key: const ValueKey('month-today'),
                  onPressed: () => setState(() => _month = DateTime(now.year, now.month)),
                  child: const Text('Today'),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                for (final d in _weekdays)
                  Expanded(
                    child: Center(child: Text(d, style: Theme.of(context).textTheme.labelMedium)),
                  ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            for (var row = 0; row < grid.length ~/ 7; row++)
              SizedBox(
                height: cellHeight,
                child: Row(
                  children: [
                    for (final day in grid.sublist(row * 7, row * 7 + 7))
                      Expanded(
                        child: _DayCell(
                          day: day,
                          inMonth: day.month == _month.month,
                          isToday: day == today,
                          currentPersonId: widget.person.id,
                          entries: days[day] ?? const [],
                          onTap: () => _openDay(context, day, days[day] ?? const []),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Icon(Icons.groups_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Days with more than one person show how far through each is, right now.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDay(BuildContext context, DateTime day, List<DayPerson> entries) {
    if (entries.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _DaySheet(
        day: day,
        entries: entries,
        onOpen: (entry) async {
          Navigator.of(sheetContext).pop();
          if (entry.person.id != widget.person.id) {
            await ref.read(databaseProvider).setCurrentPerson(entry.person.id);
          }
          if (context.mounted) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperiencePage(experienceId: entry.experienceId)));
          }
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.currentPersonId,
    required this.entries,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final String currentPersonId;
  final List<DayPerson> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final multi = entries.length >= 2;
    final mine = entries.where((e) => e.person.id == currentPersonId).toList();
    final dotKeys = <String>{for (final e in mine) ...e.substanceKeys}.take(4).toList();

    final label = StringBuffer('${_monthNames[day.month - 1]} ${day.day}');
    if (entries.isEmpty) {
      label.write(', nothing logged');
    } else if (multi) {
      label.write(', ${entries.length} people: ${entries.map((e) => '${e.person.name} ${e.percent} percent').join(', ')}');
    } else {
      label.write(', ${entries.single.person.name}');
    }

    return Semantics(
      button: entries.isNotEmpty,
      label: label.toString(),
      child: InkWell(
        key: ValueKey('day-${day.year}-${day.month}-${day.day}'),
        onTap: entries.isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          decoration: BoxDecoration(
            color: entries.isEmpty ? null : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday ? scheme.primary : (entries.isEmpty ? Colors.transparent : scheme.outlineVariant),
              width: isToday ? 2 : 1,
            ),
          ),
          child: Opacity(
            opacity: inMonth ? 1 : 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? scheme.primary : null,
                      ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final k in dotKeys)
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: substanceColor(k), shape: BoxShape.circle)),
                  ],
                ),
                const Spacer(),
                if (multi) _PersonBadge(entries: entries),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The multi-person icon with each person's progress: "50%  20%".
class _PersonBadge extends StatelessWidget {
  const _PersonBadge({required this.entries});

  final List<DayPerson> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = entries.take(3).toList();
    return Container(
      key: const ValueKey('person-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups, size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final e in shown) ...[
                    TextSpan(text: '●', style: TextStyle(color: Color(e.person.colorValue))),
                    TextSpan(text: '${e.percent}% '),
                  ],
                  if (entries.length > shown.length) TextSpan(text: '+${entries.length - shown.length}'),
                ],
              ),
              key: const ValueKey('badge-text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, required this.entries, required this.onOpen});

  final DateTime day;
  final List<DayPerson> entries;
  final void Function(DayPerson entry) onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatDate(day), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Gap.sm),
            for (final e in entries)
              ListTile(
                key: ValueKey('day-entry-${e.person.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(e.person.colorValue),
                  child: Text(e.person.name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white)),
                ),
                title: Text(e.title.isEmpty ? e.person.name : '${e.person.name}: ${e.title}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: e.percent / 100, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                      const SizedBox(height: 4),
                      Text(
                        e.percent >= 100 ? 'Finished' : (e.percent <= 0 ? 'Not started' : '${e.percent}% through'),
                        key: ValueKey('percent-${e.person.id}'),
                      ),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(e),
              ),
          ],
        ),
      ),
    );
  }
}
