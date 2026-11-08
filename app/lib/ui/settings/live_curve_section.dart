import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../toast.dart';

/// The optional persistent notification with a graph of the current curve. Android only.
class LiveCurveSection extends ConsumerWidget {
  const LiveCurveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final on = ref.watch(liveCurveEnabledProvider).value ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live curve notification', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'A notification with a graph of your current estimated curve, with a coloured line for each substance that is still active and the BAC if alcohol is in the mix. '
          'It appears while something is active, goes away when everything has worn off, and has buttons for Same as last time, Add dose and Add note. '
          'When the phone is locked it shows the graph and BAC but no substance names; unlock to see which colour is which. Estimates, not measurements.',
          style: text.bodySmall,
        ),
        SwitchListTile(
          key: const ValueKey('live-curve'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the live curve'),
          subtitle: const Text('Redraws every minute, even with the app closed. Android may also hide it on the lock screen, depending on your lock screen notification settings.'),
          value: on,
          onChanged: (v) async {
            if (v && !await requestLiveCurvePermission()) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showToast(const SnackBar(content: Text('Allow notifications for Substance Journal in Android settings to use this.')), important: true);
              }
              return;
            }
            await ref.read(databaseProvider).setSetting('liveCurve', v ? 'true' : 'false');
          },
        ),
      ],
    );
  }
}
