import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../add/add_ingestion_page.dart';
import '../add/dose_widgets.dart';
import '../design.dart';
import '../timeline/timeline_chart.dart';
import '../timeline/timeline_data.dart';
import '../../data/alcohol_data.dart';
import '../alcohol/alcohol_day_view.dart' show alcoholReadout;
import '../dose_text.dart';
import 'dialogs.dart';
import 'edit_ingestion_dialog.dart';

class ExperiencePage extends ConsumerStatefulWidget {
  const ExperiencePage({super.key, required this.experienceId});

  final String experienceId;

  @override
  ConsumerState<ExperiencePage> createState() => _ExperiencePageState();
}

class _ExperiencePageState extends ConsumerState<ExperiencePage> {
  late final AppDatabase _db = ref.read(databaseProvider);
  final _notes = TextEditingController();
  Timer? _saveTimer;
  bool _notesLoaded = false;

  /// Substances switched off on the timeline, to see the others alone.
  final Set<String> _hidden = {};
  String _lastSavedNotes = '';

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_notesLoaded && _notes.text != _lastSavedNotes) {
      unawaited(_db.updateExperience(widget.experienceId, notes: _notes.text));
    }
    _notes.dispose();
    super.dispose();
  }

  void _scheduleNotesSave(String text) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _lastSavedNotes = text;
      unawaited(_db.updateExperience(widget.experienceId, notes: text));
    });
  }

  Future<void> _editTitle(Experience experience) async {
    final controller = TextEditingController(text: experience.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Experience title'),
        content: TextField(
          key: const ValueKey('title-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Saturday night'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('title-save'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) await _db.updateExperience(experience.id, title: result.trim());
  }

  Future<void> _deleteExperience(Experience experience) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this experience?'),
        content: const Text('Its ingestions, notes and ratings are removed too. You can undo right after.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteExperience(experience.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Experience deleted'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _db.setExperienceDeleted(experience.id, false)),
    ));
  }

  Future<void> _addIngestion(Experience experience) async {
    await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => AddIngestionPage(personId: experience.personId, experienceId: experience.id),
    ));
  }

  void _showAddMenu(Experience experience) {
    final now = ref.read(clockProvider)();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('add-ingestion'),
              leading: const Icon(Icons.medication_outlined),
              title: const Text('Add an ingestion'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addIngestion(experience);
              },
            ),
            ListTile(
              key: const ValueKey('add-note'),
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Add a timed note'),
              onTap: () {
                Navigator.pop(sheetContext);
                showAddNoteDialog(context, db: _db, experienceId: experience.id, now: now);
              },
            ),
            ListTile(
              key: const ValueKey('add-rating'),
              leading: const Icon(Icons.star_outline),
              title: const Text('Add a rating'),
              onTap: () {
                Navigator.pop(sheetContext);
                showAddRatingDialog(context, db: _db, experienceId: experience.id, now: now);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final experience = ref.watch(experienceProvider(widget.experienceId)).value;
    if (experience == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (!_notesLoaded) {
      _notes.text = experience.notes;
      _lastSavedNotes = experience.notes;
      _notesLoaded = true;
    }

    final reference = ref.watch(catalogProvider);
    final now = ref.watch(clockProvider)();
    final ingestions = ref.watch(experienceIngestionsProvider(widget.experienceId)).value ?? const <Ingestion>[];
    final timedNotes = ref.watch(timedNotesProvider(widget.experienceId)).value ?? const <TimedNote>[];
    final ratings = ref.watch(ratingsProvider(widget.experienceId)).value ?? const <Rating>[];

    final series = buildTimelineSeries(ingestions: ingestions, reference: reference, now: now);

    // Alcohol in a mixed journal still gets a blood-alcohol estimate when hovering the chart.
    final drinks = [for (final i in ingestions) if (i.substanceKey == 'alcohol') i];
    final settings = ref.watch(estimateSettingsProvider(experience.personId)).value ?? const EstimateSettings();
    final bac = drinks.isEmpty
        ? const <(DateTime, double)>[]
        : bacSeries(
            drinks,
            settings,
            from: drinks.map((d) => d.time).reduce((a, b) => a.isBefore(b) ? a : b).subtract(const Duration(minutes: 30)),
            to: drinks.map((d) => d.time).reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(hours: 14)),
          );
    final markers = [
      for (final n in timedNotes)
        if (n.showOnTimeline) TimelineMarker(time: n.time, color: Color(n.colorValue), label: n.note),
      for (final r in ratings)
        if (r.time case final DateTime t)
          TimelineMarker(time: t, color: Colors.amber, label: shulginLabel(r.shulgin), isRating: true),
    ];

    final title = experience.title.isEmpty ? formatDateTime(experience.sortDate) : experience.title;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const ValueKey('experience-title'),
          onTap: () => _editTitle(experience),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 18),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('favorite'),
            tooltip: experience.isFavorite ? 'Remove favorite' : 'Favorite',
            icon: Icon(experience.isFavorite ? Icons.star : Icons.star_border),
            onPressed: () => _db.updateExperience(experience.id, isFavorite: !experience.isFavorite),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('experience-menu'),
            onSelected: (v) {
              if (v == 'delete') _deleteExperience(experience);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete experience'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-fab'),
        heroTag: null,
        onPressed: () => _showAddMenu(experience),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'Estimated intensity over time, relative to a common dose. A guide, not a measurement.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: Gap.md),
                      TimelineChart(
                        series: [for (final s in series) if (!_hidden.contains(s.substanceKey)) s],
                        markers: markers,
                        now: now,
                        extraInfo: drinks.isEmpty ? null : (t) => alcoholReadout(t, drinks, settings, bac),
                      ),
                      const SizedBox(height: Gap.sm),
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: 4,
                        children: [
                          for (final s in series)
                            FilterChip(
                              key: ValueKey('toggle-${s.substanceKey}'),
                              avatar: CircleAvatar(radius: 6, backgroundColor: s.color),
                              label: Text(s.label, style: Theme.of(context).textTheme.bodySmall),
                              selected: !_hidden.contains(s.substanceKey),
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              onSelected: (on) => setState(() => on ? _hidden.remove(s.substanceKey) : _hidden.add(s.substanceKey ?? '')),
                            ),
                          if (series.length > 1)
                            ActionChip(
                              key: const ValueKey('toggle-all'),
                              label: Text(_hidden.isEmpty ? 'Hide all' : 'Show all', style: Theme.of(context).textTheme.bodySmall),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                if (_hidden.isEmpty) {
                                  _hidden.addAll([for (final s in series) s.substanceKey ?? '']);
                                } else {
                                  _hidden.clear();
                                }
                              }),
                            ),
                        ],
                      ),
                      if (series.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Tap a substance to show or hide its curve. All on shows how they overlap.', style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              _sectionTitle('Ingestions'),
              if (ingestions.isEmpty) const Padding(padding: EdgeInsets.all(Gap.md), child: Text('Nothing logged yet.')),
              for (final ingestion in ingestions) _IngestionTile(ingestion: ingestion, db: _db),
              const SizedBox(height: Gap.md),
              if (timedNotes.isNotEmpty) ...[
                _sectionTitle('Notes during the experience'),
                for (final n in timedNotes)
                  ListTile(
                    key: ValueKey('timed-note-${n.id}'),
                    leading: CircleAvatar(radius: 8, backgroundColor: Color(n.colorValue)),
                    title: Text(n.note),
                    subtitle: Text(formatClock(n.time)),
                    trailing: IconButton(
                      tooltip: 'Delete note',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _db.deleteTimedNote(n.id),
                    ),
                  ),
                const SizedBox(height: Gap.md),
              ],
              if (ratings.isNotEmpty) ...[
                _sectionTitle('Ratings'),
                for (final r in ratings) _RatingTile(rating: r, db: _db),
                const SizedBox(height: Gap.md),
              ],
              _sectionTitle('Notes'),
              TextField(
                key: const ValueKey('experience-notes'),
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'How did it go? Set, setting, anything to remember.'),
                onChanged: _scheduleNotesSave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _IngestionTile extends ConsumerWidget {
  const _IngestionTile({required this.ingestion, required this.db});

  final Ingestion ingestion;
  final AppDatabase db;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(catalogProvider);
    final substance = reference.byKey[ingestion.substanceKey];
    final roa = substance?.route(ingestion.route);
    final borrowed = roa == null ? substance?.nearestRoute(ingestion.route) : null;
    final scheme = Theme.of(context).colorScheme;

    final cls = (ingestion.dose != null && roa != null && ingestion.substanceKey != 'alcohol') ? classifyDose(roa, ingestion.dose!) : null;
    final parts = [
      formatClock(ingestion.time),
      if (ingestion.endTime != null) 'until ${formatClock(ingestion.endTime!)}',
      describeIngestionDose(ingestion),
      ingestion.route,
      if (borrowed != null) 'curve uses ${borrowed.route} timing',
    ];
    String? cannabisNote;
    if (ingestion.substanceKey == 'cannabis' && ingestion.absorbedMg != null) {
      final details = jsonDecode(ingestion.detailsJson) as Map<String, dynamic>;
      final product = (details['productThcMg'] as num?)?.toDouble();
      cannabisNote = '${product == null ? '' : '${product.toStringAsFixed(1)} mg THC consumed, '}'
          '~${ingestion.absorbedMg!.toStringAsFixed(1)} mg absorbed';
    }

    return Card(
      key: ValueKey('ingestion-${ingestion.id}'),
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: substanceColor(ingestion.substanceKey),
          radius: 14,
          child: Text((substance?.name ?? '?').characters.first, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        title: Text(substance?.name ?? ingestion.substanceKey),
        subtitle: Text([parts.join('  |  '), ?cannabisNote, if (ingestion.notes.isNotEmpty) ingestion.notes].join('\n')),
        isThreeLine: cannabisNote != null || ingestion.notes.isNotEmpty,
        onTap: () => showDialog<void>(context: context, builder: (_) => EditIngestionDialog(ingestion: ingestion)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cls != null)
              Chip(
                label: Text(doseClassLabel(cls)),
                backgroundColor: doseClassColor(scheme, cls),
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              key: ValueKey('delete-${ingestion.id}'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                db.setIngestionDeleted(ingestion.id, true);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${substance?.name ?? 'Ingestion'} deleted'),
                  action: SnackBarAction(label: 'Undo', onPressed: () => db.setIngestionDeleted(ingestion.id, false)),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.rating, required this.db});

  final Rating rating;
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final scores = (jsonDecode(rating.scoresJson) as Map<String, dynamic>).cast<String, num>();
    final labels = {for (final (k, l) in scoreFields) k: l};
    final summary = [
      if (rating.shulgin != null) 'Intensity ${shulginLabel(rating.shulgin)}',
      for (final e in scores.entries) '${labels[e.key] ?? e.key} ${e.value}/10',
    ].join('  |  ');
    return ListTile(
      key: ValueKey('rating-${rating.id}'),
      leading: const Icon(Icons.star, color: Colors.amber),
      title: Text(summary),
      subtitle: rating.time == null ? null : Text(formatClock(rating.time!)),
      trailing: IconButton(
        tooltip: 'Delete rating',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => db.deleteRating(rating.id),
      ),
    );
  }
}
