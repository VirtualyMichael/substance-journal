import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/widgets.dart';

import 'database.dart';
import 'lan_sync.dart';
import 'sync.dart';

/// Keeps paired devices in step without a button: a few seconds after the app opens or comes back
/// to the front, every few minutes while it is open, and shortly after something is logged.
///
/// It only ever talks to devices you paired with, over the local network, and a device that is
/// not there is skipped quietly. Turn it off with the "Sync automatically" switch.
class AutoSync with WidgetsBindingObserver {
  AutoSync(
    this.db,
    this.sync,
    this.client, {
    this.interval = const Duration(minutes: 5),
    this.debounce = const Duration(seconds: 8),
    this.startDelay = const Duration(seconds: 4),
    this.quietAfterSync = const Duration(seconds: 20),
  });

  final AppDatabase db;
  final SyncService sync;
  final LanSyncClient client;
  final Duration interval;
  final Duration debounce;
  final Duration startDelay;

  /// Changes made by a sync itself must not trigger another one.
  final Duration quietAfterSync;

  Timer? _periodic;
  Timer? _debounceTimer;
  Timer? _first;
  StreamSubscription<Set<TableUpdate>>? _updates;
  bool _running = false;
  DateTime? _lastEnd;
  bool _started = false;

  static const _watched = {'ingestions', 'experiences', 'timed_notes', 'ratings'};

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _first = Timer(startDelay, run);
    _periodic = Timer.periodic(interval, (_) => run());
    _updates = db.tableUpdates(TableUpdateQuery.onAllTables([db.ingestions, db.experiences, db.timedNotes, db.ratings])).listen((updates) {
      if (!updates.any((u) => _watched.contains(u.table))) return;
      final ended = _lastEnd;
      if (_running || (ended != null && DateTime.now().difference(ended) < quietAfterSync)) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, run);
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _first?.cancel();
    _periodic?.cancel();
    _debounceTimer?.cancel();
    _updates?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), run);
    }
  }

  /// One pass over the paired devices. Safe to call at any time; overlapping calls do nothing.
  Future<int> run() async {
    if (_running) return 0;
    if (await db.getSetting('autoSync') == 'false') return 0;
    final peers = [for (final p in await sync.peers()) if (!p.pending) p];
    if (peers.isEmpty) return 0;
    _running = true;
    var merged = 0;
    try {
      for (final peer in peers) {
        try {
          merged += (await client.syncWith(peer.deviceId)).received;
        } on Object {
          // Not on this network right now. Try again next time.
        }
      }
    } finally {
      _running = false;
      _lastEnd = DateTime.now();
    }
    return merged;
  }
}
