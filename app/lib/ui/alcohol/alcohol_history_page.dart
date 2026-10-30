import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import 'alcohol_day_view.dart';
import 'alcohol_view_model.dart';

/// Previous drinking days, newest first. Tap one for its curve and drinks.
class AlcoholHistoryPage extends ConsumerWidget {
  const AlcoholHistoryPage({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final settings = ref.watch(estimateSettingsProvider(person.id)).value ?? const EstimateSettings();
    final drinks = ref.watch(alcoholDrinksProvider(person.id));
    final days = drinkingDays(drinks, settings);

    if (days.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(Gap.lg), child: Text('No drinking days yet.', key: ValueKey('no-history'))));
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView.builder(
          padding: const EdgeInsets.all(Gap.md),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final d = days[index];
            final summary = summarizeAlcoholDay(allDrinks: drinks, settings: settings, now: now, day: d.day);
            return Card(
              key: ValueKey('history-${d.day.year}-${d.day.month}-${d.day.day}'),
              margin: const EdgeInsets.only(bottom: Gap.sm),
              child: ListTile(
                title: Text('${weekdays[d.day.weekday - 1]}, ${months[d.day.month - 1]} ${d.day.day}, ${d.day.year}'),
                subtitle: Text(
                  '${d.drinks} ${d.drinks == 1 ? 'drink' : 'drinks'}  |  ${d.standardDrinks.toStringAsFixed(1)} standard  |  '
                  'peak ${summary.peakBac.toStringAsFixed(3)}%',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(formatDate(d.day))),
                    body: AlcoholDayView(person: person, day: d.day),
                  ),
                )),
              ),
            );
          },
        ),
      ),
    );
  }
}
