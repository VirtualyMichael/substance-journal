import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/active_now.dart';
import '../../data/database.dart';
import '../../data/reference_repository.dart';
import '../../providers.dart';
import '../add/dose_widgets.dart';
import '../design.dart';
import '../dose_text.dart';
import '../journal/active_now_card.dart';

/// One thing that can be logged with a tap.
class QuickItem {
  const QuickItem({required this.key, required this.title, required this.subtitle, required this.substance, this.route, this.storage, this.drink});

  final String key;
  final String title;
  final String subtitle;
  final Substance substance;
  final String? route;

  /// A non-alcohol dose, ready to store.
  final DoseStorage? storage;

  /// An alcohol drink preset (logged through the drink path).
  final Preset? drink;
}

/// Presets the person saved, to log again in one tap. Skips any that no longer make sense.
List<QuickItem> presetItems(Iterable<Preset> presets, ReferenceRepository reference) {
  final items = <QuickItem>[];
  for (final p in presets) {
    final substance = reference.byKey[p.substanceKey];
    final roa = substance?.nearestRoute(p.route);
    if (substance == null || roa == null) continue;
    try {
      final input = (jsonDecode(p.detailsJson) as Map<String, dynamic>)['input'] as Map<String, dynamic>?;
      if (input == null) continue;
      final dose = DoseInput(presetNonce: 0).withPreset(input);
      if (dose.validate(roa) != null) continue;
      final storage = dose.toStorage(roa);
      items.add(QuickItem(
        key: 'preset-${p.id}',
        title: p.name,
        subtitle: '${substance.name} · ${titleCase(roa.route)}',
        substance: substance,
        route: roa.route,
        storage: storage,
      ));
    } on Object {
      // A preset written by another version; leave it out.
    }
  }
  return items;
}

/// The last few different doses, newest first, so a repeat is one tap. Alcohol has its drink presets instead.
List<QuickItem> recentItems(Iterable<Ingestion> ingestions, ReferenceRepository reference, {int limit = 6, bool includeAlcohol = false}) {
  final sorted = [for (final i in ingestions) if (!i.deleted && (includeAlcohol || i.substanceKey != 'alcohol')) i]..sort((a, b) => b.time.compareTo(a.time));
  final seen = <String>{};
  final items = <QuickItem>[];
  for (final i in sorted) {
    final substance = reference.byKey[i.substanceKey];
    if (substance == null) continue;
    final k = '${i.substanceKey}|${i.route}|${i.dose}|${i.unit}|${i.productId}|${i.customUnitId}';
    if (!seen.add(k)) continue;
    Map<String, Object?> details = const {};
    try {
      details = (jsonDecode(i.detailsJson) as Map<String, dynamic>).cast<String, Object?>();
    } on Object {
      // Details written by another version: repeat the dose without them.
    }
    items.add(QuickItem(
      key: 'recent-${i.id}',
      title: '${substance.name} ${describeIngestionDose(i)}',
      subtitle: '${titleCase(i.route)} · last ${formatDateTime(i.time)}',
      substance: substance,
      route: i.route,
      storage: DoseStorage(
        dose: i.dose,
        unit: i.unit ?? '',
        isEstimate: i.doseIsEstimate,
        stdDev: i.doseStdDev,
        absorbedMg: i.absorbedMg,
        method: i.method,
        details: details,
        customUnitId: i.customUnitId,
        productId: i.productId,
      ),
    ));
    if (items.length >= limit) break;
  }
  return items;
}

/// Logs a stored dose right now, joining the person's current experience or starting one.
Future<(Ingestion, bool)> logQuickDose(AppDatabase db, {required String personId, required QuickItem item, required DateTime at}) async {
  var experience = await db.recentExperienceFor(personId, at);
  final created = experience == null;
  experience ??= await db.addExperience(personId: personId, sortDate: at);
  final s = item.storage!;
  final ingestion = await db.addIngestion(
    experience: experience,
    substanceKey: item.substance.key,
    route: item.route!,
    time: at,
    dose: s.dose,
    unit: s.unit,
    doseIsEstimate: s.isEstimate,
    doseStdDev: s.stdDev,
    absorbedMg: s.absorbedMg,
    method: s.method,
    details: s.details,
    customUnitId: s.customUnitId,
    productId: s.productId,
  );
  return (ingestion, created);
}

/// Asks "log this now?" (with a warning if the same compound is still working), then logs it with an undo.
Future<void> confirmAndLogQuick(BuildContext context, WidgetRef ref, Person person, QuickItem item) async {
  final now = ref.read(clockProvider)();
  final active = activeNow(
    ingestions: ref.read(personIngestionsProvider(person.id)).value ?? const <Ingestion>[],
    reference: ref.read(catalogProvider),
    now: now,
  ).where((a) => a.substance.key == item.substance.key).firstOrNull;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log ${item.title} now?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${item.subtitle} · for ${person.name} at ${clockTime(now)}'),
            if (active != null) ...[
              const SizedBox(height: Gap.sm),
              Container(
                key: const ValueKey('quick-active-warning'),
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  active.latest.fullEffectReached
                      ? 'You already have ${item.substance.name} working (taken ${now.difference(active.latest.ingestion.time).inMinutes} min ago). This adds to it.'
                      : 'Your last ${item.substance.name} dose has not fully arrived yet (expect about ${clockTime(active.latest.fullEffectAt)}). Taking more now is a common way to take too much.',
                ),
              ),
            ],
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                const SizedBox(width: Gap.sm),
                Expanded(child: FilledButton(key: const ValueKey('quick-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Log now'))),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  Future<void> Function() undo;
  if (item.drink != null) {
    final d = item.drink!;
    final abv = ((jsonDecode(d.detailsJson) as Map<String, dynamic>)['abv'] as num?)?.toDouble() ?? 0;
    final logged = await db.logDrink(personId: person.id, at: now, volume: d.amount, volumeUnit: d.unit, abvPercent: abv, name: d.name);
    undo = () => db.undoLoggedDrink(logged);
  } else {
    final (ingestion, created) = await logQuickDose(db, personId: person.id, item: item, at: now);
    undo = () async {
      await db.setIngestionDeleted(ingestion.id, true);
      if (created) await db.deleteExperience(ingestion.experienceId);
    };
  }
  messenger.showSnackBar(SnackBar(content: Text('Logged ${item.title}'), action: SnackBarAction(label: 'Undo', onPressed: undo)));
}

/// Favourites and recent doses, each one tap (plus a confirm) away. Also opened from the app icon's
/// long-press menu, the Quick Settings tile and the home-screen widget on Android.
class QuickLogPage extends ConsumerWidget {
  const QuickLogPage({super.key, required this.person});

  final Person person;

  Future<void> _log(BuildContext context, WidgetRef ref, QuickItem item) => confirmAndLogQuick(context, ref, person, item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(catalogProvider);
    final presets = presetItems(ref.watch(allDosePresetsProvider).value ?? const <Preset>[], reference);
    final seenDrinks = <String>{};
    final drinks = [
      for (final p in ref.watch(drinkPresetsProvider).value ?? const <Preset>[])
        // The same drink saved twice (for example after syncing two devices) is listed once.
        if (seenDrinks.add('${p.name}|${p.amount}|${p.unit}|${p.detailsJson}'))
          QuickItem(
            key: 'drink-${p.id}',
            title: p.name,
            subtitle: 'Alcohol · ${_drinkAmount(p.amount, p.unit)}',
            substance: reference.byKey['alcohol'] ?? reference.substances.first,
            drink: p,
          ),
    ];
    final recents = recentItems(ref.watch(personIngestionsProvider(person.id)).value ?? const <Ingestion>[], reference);
    final text = Theme.of(context).textTheme;

    Widget section(String title, List<QuickItem> items, {String? empty}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: Gap.md, bottom: 4), child: Text(title, style: text.titleSmall)),
            if (items.isEmpty && empty != null) Text(empty, style: text.bodySmall),
            for (final i in items)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  key: ValueKey('quick-${i.key}'),
                  leading: CircleAvatar(radius: 10, backgroundColor: substanceColor(i.substance.key)),
                  title: Text(i.title),
                  subtitle: Text(i.subtitle),
                  trailing: const Icon(Icons.bolt),
                  onTap: () => _log(context, ref, i),
                ),
              ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Quick log')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Gap.md),
                child: Text('Tap one to log it for ${person.name} right now. You confirm first, and can undo.', style: text.bodySmall),
              ),
              section('Your presets', presets, empty: 'Save a dose as a preset when you log it and it will appear here.'),
              section('Repeat a recent dose', recents, empty: 'Nothing logged yet.'),
              if (drinks.isNotEmpty) section('Drinks', drinks),
            ],
          ),
        ),
      ),
    );
  }
}

/// "1 shot", "2 shots", "12 oz".
String _drinkAmount(double amount, String unit) {
  final n = formatDose(amount, null);
  if (unit == 'shots' && amount == 1) return '$n shot';
  return '$n $unit';
}
