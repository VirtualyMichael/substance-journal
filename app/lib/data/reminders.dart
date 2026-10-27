import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sj_core/sj_core.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'active_now.dart';
import 'alcohol_data.dart';
import 'database.dart';
import 'reference_repository.dart';

/// Something that can put a notification in front of you. A fake one stands in for tests.
abstract class ReminderNotifier {
  /// Whether it can fire at a future time even when the app is closed (phones can; desktops here cannot).
  bool get canSchedule;

  /// Asks the system for permission to notify. True when allowed.
  Future<bool> requestPermission();

  Future<void> show(int id, String title, String body);

  /// Replaces every earlier scheduled notification with [items].
  Future<void> scheduleAll(List<ScheduledReminder> items);
}

class ScheduledReminder {
  const ScheduledReminder(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

class LocalNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Check-ins and limit alerts',
      importance: Importance.defaultImportance,
    ),
    iOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  Future<bool> _init() => _ready ??= () async {
        try {
          tzdata.initializeTimeZones();
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              windows: WindowsInitializationSettings(
                appName: 'Substance Journal',
                appUserModelId: 'com.substancejournal.app',
                guid: '8c1f3a52-6b8e-4d2a-9f0e-5a7d2c9b1e44',
              ),
              iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
              linux: LinuxInitializationSettings(defaultActionName: 'Open'),
            ),
          );
          return true;
        } on Object {
          return false;
        }
      }();

  @override
  bool get canSchedule => Platform.isAndroid || Platform.isIOS;

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      }
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (!await _init()) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
    } on Object {
      // Notifications are a convenience; never break the app over one.
    }
  }

  @override
  Future<void> scheduleAll(List<ScheduledReminder> items) async {
    if (!await _init() || !canSchedule) return;
    try {
      await _plugin.cancelAll();
      for (final r in items) {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC), // an exact moment, so daylight saving cannot shift it
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
    } on Object {
      // Same as above.
    }
  }
}

/// What the user asked to be reminded about. Kept per device: reminders are about this phone or PC.
class ReminderPrefs {
  const ReminderPrefs({this.checkIn = false, this.hour = 21, this.minute = 0, this.limitAlerts = true, this.waitAlerts = false});

  final bool checkIn;
  final int hour;
  final int minute;
  final bool limitAlerts;

  /// A heads-up when a dose should have fully arrived, so there is no urge to redose early.
  final bool waitAlerts;

  ReminderPrefs copyWith({bool? checkIn, int? hour, int? minute, bool? limitAlerts, bool? waitAlerts}) => ReminderPrefs(
        checkIn: checkIn ?? this.checkIn,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        limitAlerts: limitAlerts ?? this.limitAlerts,
        waitAlerts: waitAlerts ?? this.waitAlerts,
      );

  String encode() => jsonEncode({'checkIn': checkIn, 'hour': hour, 'minute': minute, 'limitAlerts': limitAlerts, 'waitAlerts': waitAlerts});

  static ReminderPrefs decode(String? text) {
    if (text == null || text.isEmpty) return const ReminderPrefs();
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      int inRange(Object? v, int lo, int hi, int fallback) => v is int && v >= lo && v <= hi ? v : fallback;
      return ReminderPrefs(
        checkIn: j['checkIn'] == true,
        hour: inRange(j['hour'], 0, 23, 21),
        minute: inRange(j['minute'], 0, 59, 0),
        limitAlerts: j['limitAlerts'] != false,
        waitAlerts: j['waitAlerts'] == true,
      );
    } on Object {
      return const ReminderPrefs();
    }
  }
}

const _prefsKey = 'reminders';

/// Daily check-in and drinking-limit alerts.
///
/// Check-ins are scheduled a week ahead on phones (and topped up whenever the app opens) so they
/// arrive with the app closed; on a computer they appear while the app is open. Limit alerts fire
/// right after a drink is logged that takes you close to, or over, a limit you set.
class ReminderService {
  ReminderService(this.db, this.notifier, {this.reference, DateTime Function()? now, this.debounce = const Duration(seconds: 2)})
      : _now = now ?? DateTime.now;

  /// Needed for dose-timing alerts; without it only check-ins and limit alerts run.
  final ReferenceRepository? reference;
  final AppDatabase db;
  final ReminderNotifier notifier;
  final DateTime Function() _now;
  final Duration debounce;

  StreamSubscription<dynamic>? _prefsSub, _updates;
  final _timers = <Timer>[];
  Timer? _debounceTimer;
  ReminderPrefs _prefs = const ReminderPrefs();
  final _alerted = <String>{};
  bool _started = false;

  static const _checkInId = 100;
  static const _waitId = 300;
  static const _limitId = 200;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _prefs = ReminderPrefs.decode(await db.getSetting(_prefsKey));
    await refresh();
    _prefsSub = db.watchSetting(_prefsKey).listen((v) {
      _prefs = ReminderPrefs.decode(v);
      refresh();
    });
    _updates = db.tableUpdates(TableUpdateQuery.onAllTables([db.ingestions])).listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        checkLimits();
        refresh();
      });
    });
  }

  void stop() {
    _started = false;
    _prefsSub?.cancel();
    _updates?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _debounceTimer?.cancel();
  }

  Future<ReminderPrefs> prefs() async => ReminderPrefs.decode(await db.getSetting(_prefsKey));

  Future<void> save(ReminderPrefs prefs) => db.setSetting(_prefsKey, prefs.encode());

  /// The next [count] times the check-in is due, starting after now.
  List<DateTime> upcomingCheckIns({int count = 7}) {
    final now = _now();
    var day = DateTime(now.year, now.month, now.day, _prefs.hour, _prefs.minute);
    if (!day.isAfter(now)) day = DateTime(now.year, now.month, now.day + 1, _prefs.hour, _prefs.minute);
    return [for (var i = 0; i < count; i++) DateTime(day.year, day.month, day.day + i, _prefs.hour, _prefs.minute)];
  }

  /// "Fully arrived" alerts for doses still coming up: one per substance, at the time the longest
  /// published onset and come-up end. Nothing is sent for doses already at full strength.
  Future<List<ScheduledReminder>> _waitReminders() async {
    final ref = reference;
    if (!_prefs.waitAlerts || ref == null) return const [];
    final person = await _person();
    if (person == null) return const [];
    final now = _now();
    final recent = [for (final i in await db.ingestionsForPerson(person)) if (now.difference(i.time) < const Duration(hours: 12)) i];
    final items = <ScheduledReminder>[];
    var n = 0;
    for (final a in activeNow(ingestions: recent, reference: ref, now: now)) {
      final d = a.latest;
      if (d.fullEffectReached || !d.fullEffectAt.isAfter(now)) continue;
      items.add(ScheduledReminder(
        _waitId + n++,
        d.fullEffectAt,
        '${a.substance.name} should be fully in',
        'If you feel little, wait longer. Taking more too soon is a common way to take too much.',
      ));
    }
    return items;
  }

  Future<void> _queue = Future.value();

  /// Applies the current settings: (re)schedules or clears check-ins and dose-timing alerts. Runs one
  /// at a time and always reads the latest settings, so a slow earlier pass cannot undo a newer one.
  Future<void> refresh() {
    final next = _queue.then((_) => _refreshNow());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _refreshNow() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    const title = 'Daily check-in';
    const body = 'How did today go? Log anything you missed.';
    final checkIns = _prefs.checkIn ? upcomingCheckIns() : const <DateTime>[];
    final items = <ScheduledReminder>[
      for (final (i, at) in checkIns.indexed) ScheduledReminder(_checkInId + i, at, title, body),
      ...await _waitReminders(),
    ];
    if (notifier.canSchedule) {
      await notifier.scheduleAll(items);
      return;
    }
    await notifier.scheduleAll(const []);
    // A computer cannot wake itself, so alerts fire while the app is open. Only the next check-in is armed.
    final now = _now();
    final armed = [
      if (checkIns.isNotEmpty) items.first,
      ...items.where((r) => r.id >= _waitId),
    ];
    for (final r in armed) {
      final wait = r.at.difference(now);
      if (wait.isNegative) continue;
      _timers.add(Timer(wait, () async {
        await notifier.show(r.id, r.title, r.body);
        if (r.id < _waitId) await refresh();
      }));
    }
  }

  /// Looks at the current person's drinking against their limits and speaks up when it matters.
  Future<void> checkLimits() async {
    if (!_prefs.limitAlerts) return;
    final person = await _person();
    if (person == null) return;
    final limits = await db.getLimits(person);
    if (!limits.hasAny) return;
    final drinks = [for (final i in await db.ingestionsForPerson(person)) if (i.substanceKey == 'alcohol') i];
    if (drinks.isEmpty) return;
    final now = _now();
    // Only react to drinking happening now, not to history that was imported or synced in.
    if (now.difference(drinks.map((d) => d.time).reduce((a, b) => a.isAfter(b) ? a : b)).abs() > const Duration(hours: 6)) return;
    final settings = await db.getEstimateSettings(person);
    final status = limitStatus(limits: limits, standardByDay: dailyStandardDrinks(drinks, settings), now: now);
    final day = '${now.year}-${now.month}-${now.day}';
    if (status.anyOver) {
      if (_alerted.add('$person|$day|over')) await notifier.show(_limitId, 'Over your limit', status.warning ?? 'You are over a limit you set.');
      return;
    }
    final room = status.roomToday;
    final cap = [if (limits.daily != null) limits.daily!, if (limits.weekly != null) limits.weekly!];
    if (room != null && cap.isNotEmpty) {
      final smallest = cap.reduce((a, b) => a < b ? a : b);
      if (room <= smallest * 0.2 && _alerted.add('$person|$day|near')) {
        final left = room == room.roundToDouble() ? room.toStringAsFixed(0) : room.toStringAsFixed(1);
        await notifier.show(_limitId, 'Close to your limit', '$left standard drinks left before your limit.');
      }
    }
  }

  Future<String?> _person() async => await db.getSetting('currentPersonId') ?? (await db.ensureDefaultPerson()).id;
}
