import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/widgets.dart';

import 'database.dart';
import 'lan_sync.dart';
import 'sync.dart';

/// Keeps paired devices in step without a button.
///
/// - **Straight away:** anything written on this device (a dose, a note, a rating, a preset...) is
///   sent to every paired device that is reachable about a second and a half later, and the same
///   happens on the other side, so a dose logged on the phone appears on the computer at once.
/// - **When a device is not reachable:** the change is remembered and retried every few seconds for
///   a while, then every minute, so it lands as soon as the other app is opened.
/// - **Also:** a few seconds after the app opens, whenever it comes back to the front, and every
///   minute while it is open, so nothing is missed.
///
/// It only ever talks to devices you paired with, over the local network. A change that arrived
/// from another device is never sent back to it. Turn it off with "Sync automatically".
class AutoSync with WidgetsBindingObserver {
  AutoSync(
    this.db,
    this.sync,
    this.client, {
    this.interval = const Duration(minutes: 1),
    this.debounce = const Duration(milliseconds: 1500),
    this.startDelay = const Duration(seconds: 3),
    this.retryEvery = const Duration(seconds: 10),
    this.maxQuickRetries = 30,
  });

  final AppDatabase db;
  final SyncService sync;
  final LanSyncClient client;

  /// How often it checks with every device regardless of changes.
  final Duration interval;

  /// How long after a change before it is sent (so a burst of edits goes together).
  final Duration debounce;
  final Duration startDelay;

  /// Between attempts while a device could not be reached, for [maxQuickRetries] attempts.
  final Duration retryEvery;
  final int maxQuickRetries;

  Timer? _periodic;
  Timer? _debounceTimer;
  Timer? _first;
  Timer? _retry;
  StreamSubscription<Set<TableUpdate>>? _updates;
  bool _running = false;
  bool _again = false;
  bool _started = false;
  int _retries = 0;

  /// When the last pass finished, and how many changes it brought in. For showing "synced just now".
  final ValueNotifier<DateTime?> lastSynced = ValueNotifier(null);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _first = Timer(startDelay, () => run());
    _periodic = Timer.periodic(interval, (_) => run());
    _updates = db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.people,
          db.experiences,
          db.ingestions,
          db.timedNotes,
          db.ratings,
          db.customSubstances,
          db.customUnits,
          db.products,
          db.reagentTests,
          db.presets,
          db.recipes,
          db.settings,
        ]))
        .listen((_) => _changed());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    for (final t in [_first, _periodic, _debounceTimer, _retry]) {
      t?.cancel();
    }
    _updates?.cancel();
  }

  void _changed() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => run(onlyIfPending: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 1), () => run());
    }
  }

  /// One pass over the paired devices. Safe to call at any time; a call during a pass asks for
  /// another pass straight after it. With [onlyIfPending] a device is only contacted when there is
  /// something to send it. Returns how many changes came in.
  Future<int> run({bool onlyIfPending = false}) async {
    if (_running) {
      _again = true;
      return 0;
    }
    if (await db.getSetting('autoSync') == 'false') return 0;
    final peers = [for (final p in await sync.peers()) if (!p.pending) p];
    if (peers.isEmpty) return 0;
    _running = true;
    var merged = 0;
    var unreachable = false;
    try {
      for (final peer in peers) {
        try {
          if (onlyIfPending && await sync.pendingChangeCount(peer.deviceId) == 0) continue;
          merged += (await client.syncWith(peer.deviceId)).received;
        } on Object {
          unreachable = true; // not on this network, or its app is closed: try again soon
        }
      }
    } finally {
      _running = false;
    }
    if (!unreachable) {
      _retries = 0;
      lastSynced.value = DateTime.now();
    } else if (_started && _retries < maxQuickRetries) {
      _retries++;
      _retry?.cancel();
      _retry = Timer(retryEvery, () => run(onlyIfPending: true));
    }
    if (_again && _started) {
      _again = false;
      unawaited(run(onlyIfPending: true));
    }
    return merged;
  }
}
