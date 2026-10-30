import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';
import 'design.dart';

/// Where messages that matter are also written, so they can be read again after they fade.
/// Set once at start-up; null in places that have no database (and in tests that do not care).
void Function(String message)? activitySink;

final _worthKeeping = RegExp(r'could not|couldn.t|failed|error|sync|import|restor|backup|saved to|not saved|removed|deleted', caseSensitive: false);

/// Messages shown briefly at the bottom of the screen. They go away on their own (a few seconds, a
/// little longer when there is an Undo), can be swiped away or closed, and the ones that matter are
/// also kept in the activity log (Settings, Recent messages).
extension Toasts on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(SnackBar bar, {bool? important}) {
    final content = bar.content;
    final message = content is Text ? (content.data ?? content.textSpan?.toPlainText() ?? '') : '';
    if ((important ?? _worthKeeping.hasMatch(message)) && message.isNotEmpty) activitySink?.call(message);
    clearSnackBars();
    return showSnackBar(
      SnackBar(
        content: bar.content,
        action: bar.action,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        persist: false,
        duration: Duration(seconds: bar.action == null ? 4 : 7),
      ),
    );
  }
}

/// A few days of messages worth keeping. Stored on this device only.
class ActivityEntry {
  const ActivityEntry(this.time, this.message);
  final DateTime time;
  final String message;
}

const _logKey = 'activityLog';
const _logLimit = 60;

extension ActivityLogStore on AppDatabase {
  Stream<List<ActivityEntry>> watchActivity() => watchSetting(_logKey).map(_decode);

  Future<void> logActivity(String message, DateTime at) async {
    final now = _decode(await getSetting(_logKey));
    final next = [ActivityEntry(at, message), ...now].take(_logLimit).toList();
    await setSetting(_logKey, jsonEncode([for (final e in next) {'t': e.time.millisecondsSinceEpoch, 'm': e.message}]));
  }

  Future<void> clearActivity() => setSetting(_logKey, '[]');

  static List<ActivityEntry> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      return [
        for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          ActivityEntry(DateTime.fromMillisecondsSinceEpoch(j['t'] as int), j['m'] as String),
      ];
    } on Object {
      return const [];
    }
  }
}

final activityProvider = StreamProvider<List<ActivityEntry>>((ref) => ref.watch(databaseProvider).watchActivity());

/// The messages that mattered, newest first, so nothing important is lost when a toast fades.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityProvider).value ?? const <ActivityEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent messages'),
        actions: [
          if (entries.isNotEmpty)
            TextButton(key: const ValueKey('activity-clear'), onPressed: () => ref.read(databaseProvider).clearActivity(), child: const Text('Clear')),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(Gap.lg), child: Text('Nothing yet. Sync results, backups, imports and errors are kept here after they fade.')))
          : ListView(
              children: [
                for (final e in entries)
                  ListTile(
                    dense: true,
                    title: Text(e.message),
                    subtitle: Text(formatDateTime(e.time)),
                  ),
              ],
            ),
    );
  }
}
