import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sj_core/sj_core.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/reminders.dart';

class FakeNotifier implements ReminderNotifier {
  FakeNotifier({this.canSchedule = false});
  @override
  final bool canSchedule;
  final shown = <(String, String)>[];
  List<ScheduledReminder> scheduled = [];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(int id, String title, String body) async => shown.add((title, body));
  @override
  Future<void> scheduleAll(List<ScheduledReminder> items) async => scheduled = items;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeNotifier notifier;
  late ReminderService service;
  late String personId;

  setUp(() async {
    db = AppDatabase.memory(deviceId: 'd');
    notifier = FakeNotifier();
    service = ReminderService(db, notifier);
    personId = (await db.ensureDefaultPerson()).id;
    await db.setLimits(personId, const DrinkLimits(daily: 4));
  });
  tearDown(() => db.close());

  Future<void> beer(DateTime at) => db.logDrink(personId: personId, at: at, volume: 12, volumeUnit: 'oz', abvPercent: 5);

  test('alerts when a drink takes you close to the daily limit, then over, once each', () async {
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await beer(now.subtract(Duration(minutes: 30 - i)));
    }
    await service.checkLimits();
    expect(notifier.shown, isEmpty); // 3 of 4: not close enough yet

    await beer(now.subtract(const Duration(minutes: 5)));
    await service.checkLimits(); // 4 of 4: nothing left
    await service.checkLimits(); // asking again says nothing new
    expect(notifier.shown.single.$1, 'Close to your limit');

    await beer(now);
    await service.checkLimits();
    await service.checkLimits();
    expect(notifier.shown.map((e) => e.$1), ['Close to your limit', 'Over your limit']);
  });

  test('history that is not being drunk right now causes no alert, and neither does switching alerts off', () async {
    final old = DateTime.now().subtract(const Duration(days: 2));
    for (var i = 0; i < 6; i++) {
      await beer(old.add(Duration(minutes: i)));
    }
    await service.checkLimits();
    expect(notifier.shown, isEmpty);

    for (var i = 0; i < 6; i++) {
      await beer(DateTime.now().subtract(Duration(minutes: i)));
    }
    await service.save(const ReminderPrefs(limitAlerts: false));
    await service.start();
    await service.checkLimits();
    expect(notifier.shown, isEmpty);
    service.stop();
  });

  test('a phone schedules a week of check-ins at the chosen time; turning it off clears them', () async {
    final phone = FakeNotifier(canSchedule: true);
    final svc = ReminderService(db, phone, now: () => DateTime(2026, 7, 1, 22));
    await svc.save(const ReminderPrefs(checkIn: true, hour: 21, minute: 30));
    await svc.start();
    expect(phone.scheduled, hasLength(7));
    expect(phone.scheduled.first.at, DateTime(2026, 7, 2, 21, 30)); // 21:30 has passed today
    expect(phone.scheduled.last.at, DateTime(2026, 7, 8, 21, 30));

    await svc.save(const ReminderPrefs(checkIn: false));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(phone.scheduled, isEmpty);
    svc.stop();
  });

  test('preferences round trip and ignore nonsense', () {
    const prefs = ReminderPrefs(checkIn: true, hour: 8, minute: 15, limitAlerts: false);
    final back = ReminderPrefs.decode(prefs.encode());
    expect((back.checkIn, back.hour, back.minute, back.limitAlerts), (true, 8, 15, false));
    final bad = ReminderPrefs.decode('{"hour": 99, "minute": "x"}');
    expect((bad.hour, bad.minute, bad.checkIn, bad.limitAlerts), (21, 0, false, true));
    expect(ReminderPrefs.decode('not json').checkIn, isFalse);
  });
}
