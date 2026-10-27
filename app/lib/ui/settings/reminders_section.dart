import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders.dart';
import '../../providers.dart';

/// Settings for the daily check-in and limit alerts on this device.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final prefs = ref.watch(reminderPrefsProvider).value ?? const ReminderPrefs();
    final service = ref.read(reminderServiceProvider);

    Future<void> change(ReminderPrefs next) async {
      if ((next.checkIn && !prefs.checkIn) || (next.limitAlerts && !prefs.limitAlerts) || (next.waitAlerts && !prefs.waitAlerts)) {
        await ref.read(notifierProvider).requestPermission();
      }
      await service.save(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reminders', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Notifications stay on this device and never leave it.', style: text.bodySmall),
        SwitchListTile(
          key: const ValueKey('limit-alerts'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Limit alerts'),
          subtitle: const Text('A heads-up when a drink gets you close to, or over, a limit you set.'),
          value: prefs.limitAlerts,
          onChanged: (v) => change(prefs.copyWith(limitAlerts: v)),
        ),
        SwitchListTile(
          key: const ValueKey('wait-alerts'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Tell me when a dose has fully arrived'),
          subtitle: const Text('So there is no urge to take more because it feels weak. Based on published timings.'),
          value: prefs.waitAlerts,
          onChanged: (v) => change(prefs.copyWith(waitAlerts: v)),
        ),
        SwitchListTile(
          key: const ValueKey('check-in-reminder'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Daily check-in'),
          subtitle: const Text('A nudge to log anything you missed.'),
          value: prefs.checkIn,
          onChanged: (v) => change(prefs.copyWith(checkIn: v)),
        ),
        if (prefs.checkIn)
          ListTile(
            key: const ValueKey('check-in-time'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Time'),
            trailing: Text(TimeOfDay(hour: prefs.hour, minute: prefs.minute).format(context)),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: prefs.hour, minute: prefs.minute));
              if (picked != null) await change(prefs.copyWith(hour: picked.hour, minute: picked.minute));
            },
          ),
      ],
    );
  }
}
