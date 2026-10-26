import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../providers.dart';
import '../design.dart';
import '../timeline/timeline_chart.dart';
import '../timeline/timeline_data.dart';

/// Tolerance for one person: where it stands for each substance or group they have used lately,
/// and when it should be back to normal if they take a break. Only this person's use counts.
class TolerancePage extends ConsumerWidget {
  const TolerancePage({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final catalog = ref.watch(catalogProvider);
    final rows = ref.watch(personIngestionsProvider(personId)).value ?? const [];
    final tracks = toleranceTracks(
      events: [for (final i in rows) UseEvent(i.substanceKey, i.time)],
      byKey: catalog.byKey,
      now: now,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Tolerance and breaks')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                'Tolerance builds with use and fades when you stop. Substances that cross-tolerate share one line (for example, all '
                'classic psychedelics). This is a model from published tolerance times, not a measurement, and it counts only this person\'s use.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.md),
              if (tracks.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Text('Nothing to show: no recent use of anything that builds tolerance.', key: ValueKey('no-tolerance')),
                  ),
                ),
              for (final t in tracks) _TrackCard(track: t, now: now),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.now});

  final ToleranceTrack track;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = substanceColor(track.key);
    final baseline = track.baselineAt;
    final series = TimelineSeries(
      label: track.label,
      color: color,
      points: track.projection,
      ingestionId: 'tol-${track.key}',
    );
    return Card(
      key: ValueKey('tolerance-${track.key}'),
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(track.label, style: text.titleMedium)),
              Chip(label: Text(track.word, key: ValueKey('tolerance-word-${track.key}'))),
            ]),
            Text(track.substances.join(', '), style: text.bodySmall),
            const SizedBox(height: Gap.sm),
            Text(
              baseline == null
                  ? 'Back to baseline. Last used ${relativeTime(track.lastUse, now)}.'
                  : 'Last used ${relativeTime(track.lastUse, now)}. Back to baseline around ${formatDate(baseline)} '
                      '(${baseline.difference(now).inDays} days) if you take a break.',
              key: ValueKey('tolerance-summary-${track.key}'),
            ),
            const SizedBox(height: Gap.sm),
            TimelineChart(
              series: [series],
              now: now,
              height: 150,
              reference: null,
              yMinimum: 1.0,
              yLabel: (v) => v.toStringAsFixed(1),
              emptyText: '',
            ),
            Text('Tolerance score, past two weeks and the next two months assuming no more use.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
