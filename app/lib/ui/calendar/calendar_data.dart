import '../../data/database.dart';
import '../../data/reference_repository.dart';
import '../timeline/timeline_data.dart';

/// One person's experience touching a calendar day.
class DayPerson {
  const DayPerson({
    required this.person,
    required this.experienceId,
    required this.title,
    required this.percent,
    required this.substanceKeys,
  });

  final Person person;
  final String experienceId;
  final String title;

  /// How far through the experience this person is right now, a whole number from 0 to 100.
  final int percent;

  /// Distinct substances in the experience, in the order they were taken.
  final List<String> substanceKeys;

  bool get inProgress => percent > 0 && percent < 100;
}

DateTime dayOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Who is on which day, with each person's progress.
///
/// This is the one view that looks across people, but it never combines them: every person's
/// percent comes from their own experience's curves alone, so adding someone else's ingestion
/// can not change anybody's number.
///
/// An experience counts on every day its curves touch, so a night that runs past midnight
/// appears on both days. If one person has several experiences on a day, the one in progress
/// is shown (else the one that started last).
Map<DateTime, List<DayPerson>> buildCalendar({
  required List<Person> people,
  required List<Experience> experiences,
  required List<Ingestion> ingestions,
  required ReferenceRepository reference,
  required DateTime now,
  required DateTime from,
  required DateTime to,
}) {
  final peopleById = {for (final p in people) p.id: p};
  final byExperience = <String, List<Ingestion>>{};
  for (final i in ingestions) {
    byExperience.putIfAbsent(i.experienceId, () => []).add(i);
  }
  final firstDay = dayOnly(from);
  final lastDay = dayOnly(to);

  // person id -> day -> chosen DayPerson (with its start, to pick between experiences)
  final chosen = <String, Map<DateTime, (DayPerson, DateTime)>>{};

  for (final experience in experiences) {
    final person = peopleById[experience.personId];
    final items = byExperience[experience.id];
    if (person == null || items == null || items.isEmpty) continue;

    final series = buildTimelineSeries(ingestions: items, reference: reference, now: now);
    DateTime start;
    DateTime end;
    if (series.isEmpty) {
      start = items.map((i) => i.time).reduce((a, b) => a.isBefore(b) ? a : b);
      end = items.map((i) => i.time).reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(hours: 2));
    } else {
      start = series.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
      end = series.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);
    }

    final keys = <String>[];
    for (final i in items..sort((a, b) => a.time.compareTo(b.time))) {
      if (!keys.contains(i.substanceKey)) keys.add(i.substanceKey);
    }
    final entry = DayPerson(
      person: person,
      experienceId: experience.id,
      title: experience.title,
      percent: series.isEmpty ? _percentBetween(start, end, now) : experienceProgressPercent(series: series, now: now),
      substanceKeys: keys,
    );

    var day = dayOnly(start);
    final lastTouched = dayOnly(end);
    while (!day.isAfter(lastTouched)) {
      if (!day.isBefore(firstDay) && !day.isAfter(lastDay)) {
        final perDay = chosen.putIfAbsent(person.id, () => {});
        final existing = perDay[day];
        if (existing == null || _prefer(entry, start, existing.$1, existing.$2)) perDay[day] = (entry, start);
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }

  final result = <DateTime, List<DayPerson>>{};
  for (final perDay in chosen.values) {
    perDay.forEach((day, pair) => result.putIfAbsent(day, () => []).add(pair.$1));
  }
  for (final list in result.values) {
    list.sort((a, b) => a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase()));
  }
  return result;
}

/// Progress of [now] between [start] and [end] as a whole number, for experiences whose
/// substances have no curve (the span is then just the first dose plus two hours).
int _percentBetween(DateTime start, DateTime end, DateTime now) {
  final total = end.difference(start).inMicroseconds;
  if (total <= 0 || !now.isBefore(end)) return 100;
  if (!now.isAfter(start)) return 0;
  return (now.difference(start).inMicroseconds * 100 / total).round().clamp(0, 100);
}

bool _prefer(DayPerson candidate, DateTime candidateStart, DayPerson existing, DateTime existingStart) {
  if (candidate.inProgress != existing.inProgress) return candidate.inProgress;
  return candidateStart.isAfter(existingStart);
}

/// The days of [month] as a grid starting on Monday, padded with the neighbouring months'
/// days so every row has seven cells.
List<DateTime> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final lead = first.weekday - DateTime.monday; // Monday = 1
  final start = DateTime(first.year, first.month, 1 - lead);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final cells = ((lead + daysInMonth + 6) ~/ 7) * 7;
  return [for (var i = 0; i < cells; i++) DateTime(start.year, start.month, start.day + i)];
}
