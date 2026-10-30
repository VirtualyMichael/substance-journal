import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/alcohol_data.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../timeline/timeline_chart.dart';
import '../timeline/timeline_data.dart';
import 'alcohol_view_model.dart';
import 'drink_dialogs.dart';
import '../toast.dart';

const _alcoholColor = Color(0xFFE0A100);

String _bac(double v) => '${v.toStringAsFixed(3)}%';

/// Extra hover lines at [t] for alcohol: the estimated BAC, drinks so far, and when it should clear.
/// [bac] is the person's estimated BAC curve; used by the Alcohol mode chart and the journal's.
List<String> alcoholReadout(DateTime t, List<Ingestion> drinks, EstimateSettings settings, List<(DateTime, double)> bac) {
  final soFar = [for (final d in drinks) if (!d.time.isAfter(t) && t.difference(d.time) < const Duration(hours: 36)) d];
  final lines = <String>[];
  var current = 0.0;
  for (final (time, v) in bac) {
    if (!time.isAfter(t)) current = v;
  }
  if (bac.isNotEmpty && !t.isBefore(bac.first.$1) && !t.isAfter(bac.last.$1)) lines.add('Est. BAC ${_bac(current)}');
  if (soFar.isNotEmpty) {
    final std = soFar.fold<double>(0, (s, d) => s + standardDrinksOf(d, settings));
    lines.add('${soFar.length} drinks so far, ${std.toStringAsFixed(1)} standard');
  }
  var level = 0.0;
  for (final (time, v) in bac) {
    if (!time.isAfter(t)) level = v;
  }
  if (level > 0.005) {
    for (final (time, v) in bac) {
      if (time.isAfter(t) && v <= 0.005) {
        lines.add('Back to about 0 near ${formatClock(time)}');
        break;
      }
    }
    if (level >= 0.08) lines.add('Above 0.08%, the usual US driving limit');
  }
  return lines;
}

/// One day of drinking for one person: status, quick add (today only), BAC curve and drinks.
class AlcoholDayView extends ConsumerWidget {
  const AlcoholDayView({super.key, required this.person, this.day});

  final Person person;

  /// Null means today.
  final DateTime? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final settings = ref.watch(estimateSettingsProvider(person.id)).value ?? const EstimateSettings();
    final drinks = ref.watch(alcoholDrinksProvider(person.id));
    final isToday = day == null || dateOnly(day!) == dateOnly(now);
    final summary = summarizeAlcoholDay(allDrinks: drinks, settings: settings, now: now, day: day);
    final text = Theme.of(context).textTheme;

    final series = summary.bacSeries.isEmpty
        ? const <TimelineSeries>[]
        : [TimelineSeries(label: 'BAC', color: _alcoholColor, points: summary.bacSeries, ingestionId: 'bac')];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
          children: [
            _StatusCard(
              summary: summary,
              isToday: isToday,
              settings: settings,
              day: day ?? now,
              limits: isToday
                  ? limitStatus(
                      limits: ref.watch(limitsProvider(person.id)).value ?? const DrinkLimits(),
                      standardByDay: dailyStandardDrinks(drinks, settings),
                      now: now,
                    )
                  : null,
            ),
            const SizedBox(height: Gap.md),
            if (isToday) ...[
              QuickAddBar(person: person, settings: settings),
              const SizedBox(height: Gap.md),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimated blood alcohol', style: text.titleMedium),
                    Text(
                      'A model of how your body absorbs and clears alcohol, using the body settings in Settings. '
                      'It is a guide, not a measurement.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: Gap.md),
                    TimelineChart(
                      key: const ValueKey('bac-chart'),
                      series: series,
                      now: now,
                      reference: null,
                      yMinimum: 0.08,
                      yLabel: _bac,
                      extraInfo: (t) => alcoholReadout(t, drinks, settings, summary.bacSeries),
                      emptyText: isToday ? 'No drinks in the last 36 hours' : 'No drinks on this day',
                      height: 240,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            Text(isToday ? "Today's drinks" : 'Drinks on ${formatDate(day!)}', style: text.titleMedium),
            const SizedBox(height: Gap.sm),
            if (summary.drinksOfDay.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.md),
                child: Text(isToday ? 'Nothing logged today.' : 'Nothing logged.', key: const ValueKey('no-drinks')),
              ),
            for (final d in summary.drinksOfDay) DrinkTile(drink: d, person: person, settings: settings),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.summary, required this.isToday, required this.settings, required this.day, this.limits});

  final LimitStatus? limits;

  final AlcoholDaySummary summary;
  final bool isToday;
  final EstimateSettings settings;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget stat(String label, String value, {Key? key}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelMedium),
              const SizedBox(height: 2),
              Text(value, key: key, style: text.headlineSmall),
            ],
          ),
        );
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isToday) stat('Est. BAC now', _bac(summary.bacNow ?? 0), key: const ValueKey('bac-now')) else stat('Peak BAC', _bac(summary.peakBac), key: const ValueKey('bac-peak')),
                stat('Standard drinks', summary.standardDrinks.toStringAsFixed(1), key: const ValueKey('std-drinks')),
                if (isToday)
                  stat(
                    'Clear by',
                    summary.clearTime != null ? formatClock(summary.clearTime!) : ((summary.inBodyNow ?? 0) > 0.05 ? 'later' : 'clear'),
                    key: const ValueKey('clear-by'),
                  ),
              ],
            ),
            if (limits != null && limits!.limits.hasAny) ...[
              const SizedBox(height: Gap.sm),
              Column(
                key: const ValueKey('limits-status'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in limits!.lines) Text(line, style: text.bodyMedium),
                  if (limits!.limits.daily != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (limits!.today / limits!.limits.daily!).clamp(0.0, 1.0),
                      color: limits!.overDaily ? scheme.error : null,
                      minHeight: 6,
                    ),
                  ],
                  if (limits!.warning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(limits!.warning!, key: const ValueKey('limit-warning'), style: text.bodyMedium?.copyWith(color: scheme.error)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Gap.sm),
            Text(
              'Estimates only. Do not use them to decide whether it is safe or legal to drive.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown of every preset plus one-tap buttons for the most used.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key, required this.person, required this.settings});

  final Person person;
  final EstimateSettings settings;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  String? _selected;

  Future<void> _log(Preset preset) async {
    final db = ref.read(databaseProvider);
    final now = ref.read(clockProvider)();
    final drink = presetDrink(preset);
    final logged = await db.logDrink(
      personId: widget.person.id,
      at: now,
      volume: drink.volume,
      volumeUnit: drink.unit,
      abvPercent: drink.abv,
      name: preset.name,
      shotOz: widget.settings.standardDrinkVolumeOz,
    );
    if (!mounted) return;
    // Say so when this drink takes the day or week past a limit the person set.
    final limits = ref.read(limitsProvider(widget.person.id)).value ?? const DrinkLimits();
    final status = limitStatus(
      limits: limits,
      standardByDay: dailyStandardDrinks([...ref.read(alcoholDrinksProvider(widget.person.id)), logged.ingestion], widget.settings),
      now: now,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showToast(SnackBar(
        content: Text('Added ${preset.name}${status.warning == null ? '' : '. ${status.warning}'}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => db.undoLoggedDrink(logged)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(drinkPresetsProvider).value ?? const <Preset>[];
    final drinks = ref.watch(alcoholDrinksProvider(widget.person.id));
    final now = ref.watch(nowProvider);
    final top = topPresets(presets, drinks, now);
    final selected = presets.where((p) => p.id == _selected).firstOrNull ?? presets.firstOrNull;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick add', style: text.titleMedium),
            const SizedBox(height: Gap.sm),
            if (presets.isEmpty)
              const Text('No drink presets yet. Add some in Settings.')
            else ...[
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final p in top)
                    ActionChip(
                      key: ValueKey('quick-${p.id}'),
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(p.name),
                      onPressed: () => _log(p),
                    ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('preset-dropdown'),
                      initialValue: selected?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Any saved drink'),
                      items: [for (final p in presets) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _selected = v),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  FilledButton(
                    key: const ValueKey('quick-add-selected'),
                    onPressed: selected == null ? null : () => _log(selected),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Gap.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('custom-drink'),
                icon: const Icon(Icons.local_bar_outlined),
                label: const Text('Custom drink'),
                onPressed: () async {
                  final db = ref.read(databaseProvider);
                  final messenger = ScaffoldMessenger.of(context);
                  final logged = await showDrinkDialog(
                    context,
                    db: db,
                    personId: widget.person.id,
                    now: ref.read(clockProvider)(),
                    settings: widget.settings,
                  );
                  if (logged != null) {
                    messenger
                      ..hideCurrentSnackBar()
                      ..showToast(SnackBar(
                        content: const Text('Drink added'),
                        action: SnackBarAction(label: 'Undo', onPressed: () => db.undoLoggedDrink(logged)),
                      ));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DrinkTile extends ConsumerWidget {
  const DrinkTile({super.key, required this.drink, required this.person, required this.settings});

  final Ingestion drink;
  final Person person;
  final EstimateSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final standard = standardDrinksOf(drink, settings);
    final d = DrinkDetails.of(drink);
    final detail = d.hasVolume && d.name.isNotEmpty ? '  |  ${describeVolume(d)}' : '';
    return Card(
      key: ValueKey('drink-${drink.id}'),
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: _alcoholColor, radius: 16, child: Icon(Icons.local_bar, size: 18, color: Colors.white)),
        title: Text(describeDrink(drink)),
        subtitle: Text('${formatClock(drink.time)}  |  ${standard.toStringAsFixed(1)} standard drinks$detail'),
        onTap: () => showDrinkDialog(
          context,
          db: db,
          personId: person.id,
          now: ref.read(clockProvider)(),
          settings: settings,
          existing: drink,
        ),
        trailing: IconButton(
          key: ValueKey('delete-drink-${drink.id}'),
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            db.setIngestionDeleted(drink.id, true);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showToast(SnackBar(
                content: const Text('Drink deleted'),
                action: SnackBarAction(label: 'Undo', onPressed: () => db.setIngestionDeleted(drink.id, false)),
              ));
          },
        ),
      ),
    );
  }
}

String describeVolume(DrinkDetails d) {
  String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${n(d.volume!)} ${d.volumeUnit} ${n(d.abv!)}%';
}
