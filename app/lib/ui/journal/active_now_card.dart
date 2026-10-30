import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/active_now.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../alcohol/alcohol_view_model.dart';
import '../design.dart';
import 'experience_page.dart';

String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _ago(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '${h}h ago' : '${h}h ${rest}m ago';
}

/// What is still working right now, with when it should be fully in, coming down and over. Built
/// from published timings, so it is a guide: real effects vary with the person, dose and food.
class ActiveNowCard extends ConsumerStatefulWidget {
  const ActiveNowCard({super.key, required this.personId, required this.ingestions});

  final String personId;
  final List<Ingestion> ingestions;

  @override
  ConsumerState<ActiveNowCard> createState() => _ActiveNowCardState();
}

class _ActiveNowCardState extends ConsumerState<ActiveNowCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final active = activeNow(ingestions: widget.ingestions, reference: ref.watch(catalogProvider), now: now);

    // Alcohol has its own estimate (blood alcohol), so it gets a line of its own rather than a timing phase.
    final settings = ref.watch(estimateSettingsProvider(widget.personId)).value;
    final drinks = [for (final i in widget.ingestions) if (i.substanceKey == 'alcohol' && !i.deleted) i];
    final alcohol = settings == null || drinks.isEmpty ? null : summarizeAlcoholDay(allDrinks: drinks, settings: settings, now: now);
    final bac = alcohol?.bacNow ?? 0;
    final alcoholActive = alcohol != null && ((alcohol.inBodyNow ?? 0) > 0.005 || bac > 0.001);

    if (active.isEmpty && !alcoholActive) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // The latest of every "it should be gone by" estimate. A guide for planning, never a clearance.
    final times = [for (final a in active) a.latest.lingerEndsAt, if (alcoholActive && alcohol.clearTime != null) alcohol.clearTime!];
    final avoidDrivingUntil = times.isEmpty ? null : times.reduce((a, b) => a.isAfter(b) ? a : b);

    return Card(
      key: const ValueKey('active-now'),
      margin: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active now', style: text.titleMedium),
            const SizedBox(height: 4),
            for (final a in active) ...[
              _SubstanceRow(active: a, now: now),
              if (a != active.last || alcoholActive) const Divider(height: Gap.lg),
            ],
            if (alcoholActive)
              Column(
                key: const ValueKey('active-alcohol'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(radius: 6, backgroundColor: substanceColor('alcohol')),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Alcohol', style: text.titleSmall)),
                    Text('about ${bac.toStringAsFixed(3)}% BAC', style: text.labelLarge),
                  ]),
                  Text(
                    alcohol.clearTime != null ? 'Estimated to clear around ${clockTime(alcohol.clearTime!)}.' : 'Estimated to clear later than a day from now.',
                  ),
                ],
              ),
            if (avoidDrivingUntil != null) ...[
              const SizedBox(height: Gap.md),
              Container(
                key: const ValueKey('driving-note'),
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.directions_car_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Plan not to drive or use machinery until after about ${clockTime(avoidDrivingUntil)}, and only if you feel completely clear and have slept. '
                        'Impairment can outlast how you feel, and this is an estimate, never a clearance.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Gap.sm),
            Text(
              'Times come from published timings and use the longest ones, so treat them as a guide. Real effects vary with the person, dose and food.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubstanceRow extends StatelessWidget {
  const _SubstanceRow({required this.active, required this.now});

  final ActiveSubstance active;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final d = active.latest;
    final text = Theme.of(context).textTheme;
    final start = d.ingestion.time;
    final total = d.mainEffectsEndAt.difference(start).inMinutes;
    final progress = total <= 0 ? 1.0 : (now.difference(start).inMinutes / total).clamp(0.0, 1.0);
    final doses = active.doses.length;
    final lines = <String>[
      if (!d.fullEffectReached) 'Fully arrives by about ${clockTime(d.fullEffectAt)}.',
      if (d.phase.index <= DosePhase.peak.index) 'Starts coming down around ${clockTime(d.peakEndsAt)}.',
      if (d.phase != DosePhase.lingering) 'Main effects over around ${clockTime(d.mainEffectsEndAt)}.' else 'Main effects are over; lighter after-effects fade by about ${clockTime(d.lingerEndsAt)}.',
    ];

    return InkWell(
      key: ValueKey('active-${active.substance.key}'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperiencePage(experienceId: d.ingestion.experienceId))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: substanceColor(active.substance.key)),
                const SizedBox(width: 8),
                Expanded(child: Text(active.substance.name, style: text.titleSmall)),
                Text(d.phase.label, key: ValueKey('phase-${active.substance.key}'), style: text.labelLarge),
              ],
            ),
            Text('Taken ${_ago(now.difference(start))}${doses > 1 ? ', $doses doses so far' : ''}', style: text.bodySmall),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 6),
            for (final l in lines) Text(l),
            if (!d.fullEffectReached)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Hold off on more until then. Taking more because it feels weak is a common way to take too much.',
                  key: ValueKey('wait-${active.substance.key}'),
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              )
            else if (d.phase.index <= DosePhase.comedown.index)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('A repeat dose now adds to what is still active.', style: text.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
