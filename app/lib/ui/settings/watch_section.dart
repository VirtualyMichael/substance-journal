import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/watch_bridge.dart';
import '../../providers.dart';
import '../design.dart';

/// Settings block for the Wear OS watch app (Pixel Watch and others): what the phone sends it and
/// whether it may log a dose by itself.
class WatchSection extends ConsumerWidget {
  const WatchSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(watchPrefsProvider).value ?? const WatchPrefs();
    final db = ref.read(databaseProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Watch', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Shows your live curve, blood alcohol estimate and recent doses on a paired Wear OS watch (the Substance Journal watch app must be installed on it). '
          'Names and doses are sent to the watch over Bluetooth, and stay on your phone and watch.',
          style: text.bodySmall,
        ),
        SwitchListTile(
          key: const ValueKey('watch-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show on my watch'),
          value: prefs.enabled,
          onChanged: (v) => db.saveWatchPrefs(prefs.copyWith(enabled: v, allowLog: v ? prefs.allowLog : false)),
        ),
        SwitchListTile(
          key: const ValueKey('watch-allow-log'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Let the watch log "Same as last time"'),
          subtitle: const Text('The dose is logged straight from the watch, even with the app closed and without the app lock.'),
          value: prefs.allowLog,
          onChanged: prefs.enabled ? (v) => db.saveWatchPrefs(prefs.copyWith(allowLog: v)) : null,
        ),
        const SizedBox(height: Gap.xs),
      ],
    );
  }
}
