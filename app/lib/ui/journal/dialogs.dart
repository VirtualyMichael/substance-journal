import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../design.dart';

const List<Color> noteColors = [
  Color(0xFF4F7CAC),
  Color(0xFFE07A5F),
  Color(0xFF3D9970),
  Color(0xFFB565A7),
  Color(0xFFE0A100),
];

/// Shulgin rating scale, weakest to strongest.
const List<(String, String, String)> shulginScale = [
  ('minus', '-', 'No effect'),
  ('plusMinus', '+/-', 'Threshold, barely noticeable'),
  ('plus1', '+', 'Light'),
  ('plus2', '++', 'Clear effects'),
  ('plus3', '+++', 'Peak, fully immersed'),
  ('plus4', '++++', 'Beyond ordinary experience'),
];

const List<(String, String)> scoreFields = [
  ('mood', 'Mood'),
  ('pain', 'Pain'),
  ('sleep', 'Sleep'),
  ('anxiety', 'Anxiety'),
  ('appetite', 'Appetite'),
  ('focus', 'Focus'),
];

String shulginLabel(String? key) => shulginScale.where((e) => e.$1 == key).firstOrNull?.$2 ?? '';

Future<void> showAddNoteDialog(
  BuildContext context, {
  required AppDatabase db,
  required String experienceId,
  required DateTime now,
}) async {
  final text = TextEditingController();
  var time = now;
  var color = noteColors.first;
  var onTimeline = true;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add a note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('note-text'),
                controller: text,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'What is happening?'),
              ),
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(formatClock(time)),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(time));
                  if (picked != null) {
                    setState(() => time = DateTime(time.year, time.month, time.day, picked.hour, picked.minute));
                  }
                },
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                children: [
                  for (final c in noteColors)
                    GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: c,
                        child: color == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show on timeline'),
                value: onTimeline,
                onChanged: (v) => setState(() => onTimeline = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('note-save'),
            onPressed: () async {
              final value = text.text.trim();
              if (value.isEmpty) return;
              await db.addTimedNote(
                experienceId: experienceId,
                time: time,
                note: value,
                colorValue: color.toARGB32(),
                showOnTimeline: onTimeline,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAddRatingDialog(
  BuildContext context, {
  required AppDatabase db,
  required String experienceId,
  required DateTime now,
}) async {
  String? shulgin;
  final scores = <String, int>{};
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Rate this experience'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Intensity (Shulgin scale)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                children: [
                  for (final (key, label, hint) in shulginScale)
                    Tooltip(
                      message: hint,
                      child: ChoiceChip(
                        key: ValueKey('shulgin-$key'),
                        label: Text(label),
                        selected: shulgin == key,
                        onSelected: (_) => setState(() => shulgin = shulgin == key ? null : key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text('How you feel (optional, 0 to 10)', style: Theme.of(context).textTheme.titleSmall),
              for (final (key, label) in scoreFields)
                Row(
                  children: [
                    SizedBox(width: 72, child: Text(label)),
                    Expanded(
                      child: Slider(
                        key: ValueKey('score-$key'),
                        value: (scores[key] ?? 0).toDouble(),
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: scores[key]?.toString() ?? 'not set',
                        onChanged: (v) => setState(() => scores[key] = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: scores.containsKey(key)
                          ? Row(children: [
                              Text('${scores[key]}'),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 16),
                                tooltip: 'Clear',
                                onPressed: () => setState(() => scores.remove(key)),
                              ),
                            ])
                          : const Text('-'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('rating-save'),
            onPressed: shulgin == null && scores.isEmpty
                ? null
                : () async {
                    await db.addRating(experienceId: experienceId, time: now, shulgin: shulgin, scores: scores);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
