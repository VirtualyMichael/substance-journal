import 'dart:convert';

import 'package:sj_core/sj_core.dart';

import '../ui/dose_text.dart';
import '../ui/journal/tolerance_card.dart' show toleranceTrend;
import 'alcohol_data.dart';
import 'cannabis_products.dart';
import 'database.dart';
import 'weekly_summary.dart';

/// What to leave out when the digest might leave this device (a cloud AI, a chat window).
class DigestOptions {
  const DigestOptions({this.hideNames = false, this.hideNotes = false, this.hideLocations = false});

  final bool hideNames;
  final bool hideNotes;
  final bool hideLocations;

  static const full = DigestOptions();
  static const private = DigestOptions(hideNames: true, hideNotes: true, hideLocations: true);
}

/// One experience in the digest index, so an AI can find the right sheet without opening them all.
class DigestEntry {
  const DigestEntry({required this.id, required this.path, required this.date, required this.title, required this.substances, required this.doses, required this.tokens});
  final String id;
  final String path;
  final DateTime date;
  final String title;
  final List<String> substances;
  final int doses;
  final int tokens;

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'date': _day(date), 'time': _hm(date), 'title': title, 'substances': substances, 'doses': doses, 'tokens': tokens};
}

String _pad2(int n) => n.toString().padLeft(2, '0');
String _day(DateTime t) => '${t.year}-${_pad2(t.month)}-${_pad2(t.day)}';
String _hm(DateTime t) => '${_pad2(t.hour)}:${_pad2(t.minute)}';
String _num(double v, [int digits = 1]) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(digits);
String _plural(num n, String word) => '${_num(n.toDouble())} ${n == 1 ? word : '${word}s'}';
int _tokens(String text) => (text.length / 4).ceil();

String _span(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '${h}h' : '${h}h ${_pad2(rest)}m';
}

String _ago(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

String _slug(String id) => id.replaceAll('-', '').substring(0, 8);

/// File path of an experience's sheet inside the digest folder.
String experiencePath(Experience e) => 'experiences/${_day(e.sortDate)}_${_pad2(e.sortDate.hour)}${_pad2(e.sortDate.minute)}_${_slug(e.id)}.md';

class Digest {
  const Digest({required this.files, required this.index});

  /// Relative path -> text.
  final Map<String, String> files;
  final List<DigestEntry> index;
}

/// Turns one person's journal into small, layered text files for an AI with a limited context window:
/// `README.md` (how to read), `profile.md` (a page), `months/` (a page per month), `experiences/`
/// (one fact sheet per experience) and `index.json`. Everything is calculated here, with the same
/// curve, potency and tolerance models the app shows, so the AI explains numbers and never has to
/// work them out.
Digest buildDigest({
  required Person person,
  required List<Experience> experiences,
  required List<Ingestion> ingestions,
  required List<TimedNote> notes,
  required List<Rating> ratings,
  required List<Product> products,
  required Map<String, Substance> byKey,
  required DateTime now,
  EstimateSettings alcoholSettings = const EstimateSettings(),
  DigestOptions options = DigestOptions.full,
}) {
  final live = [for (final i in ingestions) if (!i.deleted) i]..sort((a, b) => a.time.compareTo(b.time));
  final exps = [for (final e in experiences) if (!e.deleted && e.personId == person.id) e]..sort((a, b) => b.sortDate.compareTo(a.sortDate));
  final productsById = {for (final p in products) p.id: p};
  final who = options.hideNames ? 'the person' : person.name;

  final files = <String, String>{};
  final index = <DigestEntry>[];
  final events = [for (final i in live) UseEvent(i.substanceKey, i.time)];

  for (final e in exps) {
    final mine = [for (final i in live) if (i.experienceId == e.id) i];
    if (mine.isEmpty) continue;
    final sheet = _experienceSheet(
      experience: e,
      doses: mine,
      notes: [for (final n in notes) if (n.experienceId == e.id && !n.deleted) n]..sort((a, b) => a.time.compareTo(b.time)),
      ratings: [for (final r in ratings) if (r.experienceId == e.id && !r.deleted) r],
      productsById: productsById,
      byKey: byKey,
      allEvents: events,
      allLive: live,
      who: who,
      settings: alcoholSettings,
      options: options,
    );
    final path = experiencePath(e);
    files[path] = sheet;
    index.add(DigestEntry(
      id: e.id,
      path: path,
      date: e.sortDate,
      title: e.title,
      substances: {for (final i in mine) byKey[i.substanceKey]?.name ?? i.substanceKey}.toList()..sort(),
      doses: mine.length,
      tokens: _tokens(sheet),
    ));
  }

  final months = <String, List<Ingestion>>{};
  for (final i in live) {
    months.putIfAbsent('${i.time.year}-${_pad2(i.time.month)}', () => []).add(i);
  }
  for (final entry in months.entries) {
    files['months/${entry.key}.md'] = _monthPage(entry.key, entry.value, index, byKey, productsById, who, now);
  }

  files['profile.md'] = _profile(who: who, live: live, index: index, products: products, byKey: byKey, events: events, now: now);
  files['README.md'] = _readme(who, index.length, months.length);
  files['index.json'] = jsonEncode({
    'generated': now.toIso8601String(),
    'experiences': [for (final e in index) e.toJson()],
  });
  return Digest(files: files, index: index);
}

String _readme(String who, int experiences, int months) => '''# Substance journal digest

Records for $who, written by the Substance Journal app. $experiences experiences over $months months.

Read in this order and stop when you have enough:
1. `profile.md` - one page: what is used, how often, last use, tolerance, last week.
2. `months/YYYY-MM.md` - one page per month: every day, totals, days without use.
3. `experiences/*.md` - one fact sheet per experience: every dose with potency, the estimated
   curve (onset, peak, end), notes and ratings with times, tolerance going in, overlaps.
4. `index.json` - a machine-readable list for tools. It is large: do not open it; find experiences from the month pages instead.

The numbers (potency, curve times, tolerance) are model estimates from published ranges, not
measurements. Quote them as estimates.
''';

String _profile({
  required String who,
  required List<Ingestion> live,
  required List<DigestEntry> index,
  required List<Product> products,
  required Map<String, Substance> byKey,
  required List<UseEvent> events,
  required DateTime now,
}) {
  final b = StringBuffer()..writeln('# Profile: $who')..writeln('Generated ${_day(now)} ${_hm(now)}.');
  if (live.isEmpty) {
    b.writeln('\nNo doses logged yet.');
    return b.toString();
  }
  b
    ..writeln('\nLogged ${_plural(live.length, 'dose')} in ${_plural(index.length, 'experience')}, ${_day(live.first.time)} to ${_day(live.last.time)}.')
    ..writeln('\n## By compound');
  final keys = {for (final i in live) i.substanceKey}.toList();
  final tracks = {for (final t in toleranceTracks(events: events, byKey: byKey, now: now)) t.key: t};
  final rows = <(int, String)>[];
  for (final key in keys) {
    final s = byKey[key];
    final doses = [for (final i in live) if (i.substanceKey == key) i];
    final last = doses.last.time;
    final recent = doses.where((i) => now.difference(i.time) < const Duration(days: 30)).length;
    final days = {for (final i in doses) _day(i.time)}.length;
    final track = s == null ? null : tracks[toleranceTrackKey(s)];
    final tol = track == null ? '' : ', tolerance ${track.word.toLowerCase()} and ${toleranceTrend(track, now).name}';
    rows.add((doses.length, '- ${s?.name ?? key}: ${_plural(doses.length, 'dose')} on ${_plural(days, 'day')}, last ${_day(last)} (${_ago(now.difference(last))}), $recent in the last 30 days$tol.'));
  }
  rows.sort((a, b) => b.$1.compareTo(a.$1));
  for (final r in rows) {
    b.writeln(r.$2);
  }

  final week = weekSummary(ingestions: live, products: products, now: now);
  b
    ..writeln('\n## Last 7 days (from ${_day(week.from)})')
    ..writeln('${_plural(week.doses, 'dose')} on ${_plural(week.daysWithUse, 'day')}, ${_plural(week.daysWithout, 'day')} without use. Before that: ${_plural(week.previousDoses, 'dose')}, ${_plural(week.previousDaysWithout, 'day')} without use.')
    ..writeln(week.bySubstance.isEmpty ? '' : '${week.bySubstance.map((e) => '${byKey[e.key]?.name ?? e.key} ${e.value}').join(', ')}.')
    ..writeln(week.spend == null ? 'Spend: not tracked (no cost saved on the products used).' : 'Spend: ${_num(week.spend!, 2)} on products with a saved cost.');

  b.writeln('\n## Most recent experiences');
  for (final e in index.take(6)) {
    b.writeln('- ${_day(e.date)} ${_hm(e.date)} ${e.title.isEmpty ? '' : '"${e.title}" '}${e.substances.join(', ')} (${_plural(e.doses, 'dose')}) -> `${e.path}`');
  }
  return b.toString();
}

String _monthPage(String month, List<Ingestion> doses, List<DigestEntry> index, Map<String, Substance> byKey, Map<String, Product> productsById, String who, DateTime now) {
  final b = StringBuffer()..writeln('# $month for $who');
  final first = DateTime(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)));
  final last = DateTime(first.year, first.month + 1, 0);
  final upTo = now.isBefore(last) && now.isAfter(first) ? now : last;
  final days = <String, List<Ingestion>>{};
  for (final i in doses) {
    days.putIfAbsent(_day(i.time), () => []).add(i);
  }
  final span = upTo.day;
  b.writeln('${_plural(doses.length, 'dose')} on ${days.length} of $span days (${span - days.length} without use).');

  final totals = <String, String>{};
  final keys = {for (final i in doses) i.substanceKey};
  for (final key in keys) {
    totals[key] = _totalText(key, [for (final i in doses) if (i.substanceKey == key) i], byKey);
  }
  b.writeln('\n## Totals');
  for (final e in totals.entries) {
    b.writeln('- ${byKey[e.key]?.name ?? e.key}: ${e.value}');
  }
  b.writeln('\n## Days');
  final dayKeys = days.keys.toList()..sort();
  for (final d in dayKeys) {
    final items = days[d]!;
    final parts = [
      for (final key in {for (final i in items) i.substanceKey})
        '${byKey[key]?.name ?? key} ${_totalText(key, [for (final i in items) if (i.substanceKey == key) i], byKey, brief: true)}',
    ];
    final exps = [for (final e in index) if (_day(e.date) == d) e.path];
    b.writeln('- $d: ${parts.join('; ')}${exps.isEmpty ? '' : ' -> ${exps.map((p) => '`$p`').join(', ')}'}');
  }
  return b.toString();
}

/// "5 doses, 7.6 mg absorbed" or "9 drinks, about 5.2 standard drinks".
String _totalText(String key, List<Ingestion> doses, Map<String, Substance> byKey, {bool brief = false}) {
  if (key == 'alcohol') {
    final grams = doses.fold<double>(0, (s, i) => s + (i.dose ?? 0));
    final std = _num(grams / 14.0);
    return brief ? 'x${doses.length} ($std std drinks)' : '${_plural(doses.length, 'drink')}, about ${_plural(grams / 14.0, 'standard drink')} (${_num(grams, 0)} g ethanol).';
  }
  final absorbed = doses.fold<double>(0, (s, i) => s + (i.absorbedMg ?? 0));
  if (absorbed > 0) {
    return brief ? 'x${doses.length} (~${_num(absorbed)} mg absorbed)' : '${_plural(doses.length, 'dose')}, about ${_num(absorbed)} mg absorbed.';
  }
  final unit = doses.first.unit;
  final known = doses.where((i) => i.dose != null).toList();
  if (unit != null && known.isNotEmpty && known.every((i) => i.unit == unit)) {
    final sum = known.fold<double>(0, (s, i) => s + i.dose!);
    return brief ? 'x${doses.length} (${_num(sum)} $unit)' : '${_plural(doses.length, 'dose')}, ${_num(sum)} $unit in total.';
  }
  return brief ? 'x${doses.length}' : '${_plural(doses.length, 'dose')}.';
}

String _phases(RouteOfAdministration roa) {
  final parts = <String>[];
  for (final d in roa.durations) {
    final lo = d.minMinutes;
    final hi = d.maxMinutes;
    if (lo == null && hi == null) continue;
    final text = lo != null && hi != null && lo != hi ? '${_num(lo, 0)}-${_num(hi, 0)} min' : '${_num((lo ?? hi)!, 0)} min';
    parts.add('${d.phase} $text');
  }
  return parts.join(', ');
}

String _experienceSheet({
  required Experience experience,
  required List<Ingestion> doses,
  required List<TimedNote> notes,
  required List<Rating> ratings,
  required Map<String, Product> productsById,
  required Map<String, Substance> byKey,
  required List<UseEvent> allEvents,
  required List<Ingestion> allLive,
  required String who,
  required EstimateSettings settings,
  required DigestOptions options,
}) {
  const maxDoses = 60;
  final first = doses.first.time;
  final lastDose = doses.last.endTime ?? doses.last.time;
  final b = StringBuffer();
  final title = experience.title.isEmpty ? 'Untitled' : experience.title;
  b
    ..writeln('# Experience: $title, ${_day(first)} ${_hm(first)}')
    ..writeln('Person: $who | ${_plural(doses.length, 'dose')} | first ${_hm(first)}, last ${_hm(lastDose)} (${_span(lastDose.difference(first))} apart)'
        '${options.hideLocations || experience.locationName == null ? '' : ' | Place: ${experience.locationName}'}');
  if (experience.notes.isNotEmpty) b.writeln('Note: ${options.hideNotes ? '[omitted]' : experience.notes}');

  b.writeln('\n## Doses');
  for (final i in doses.take(maxDoses)) {
    final s = byKey[i.substanceKey];
    final roa = s?.route(i.route) ?? s?.nearestRoute(i.route);
    final cls = (i.dose != null && roa != null && i.substanceKey != 'alcohol') ? classifyDose(roa, i.dose!) : null;
    final line = StringBuffer('- ${_hm(i.time)} (+${_span(i.time.difference(first))}) ${s?.name ?? i.substanceKey}, ${i.route}, ${describeIngestionDose(i)}');
    if (cls != null) line.write(' [${_classWord(cls)} for this route]');
    if (i.substanceKey == 'cannabis') {
      final d = _json(i.detailsJson);
      final thc = (d['productThcMg'] as num?)?.toDouble();
      if (thc != null) line.write('; ${_num(thc)} mg THC in what was used');
      if (i.absorbedMg != null) line.write('; ~${_num(i.absorbedMg!)} mg absorbed');
      final p = i.productId == null ? null : productsById[i.productId];
      if (p != null) {
        final pd = ProductDetails.of(p);
        line.write('; product: ${p.name}'
            '${p.thcPercent == null ? '' : ' ${_num(p.thcPercent!)}% THC'}'
            '${p.cbdPercent == null ? '' : ' ${_num(p.cbdPercent!)}% CBD'}'
            '${pd.strainType.isEmpty ? '' : ', ${pd.strainType}'}${pd.terpenes.isEmpty ? '' : ', terpenes ${pd.terpenes}'}');
      }
    }
    if (i.stomachFullness != null) line.write('; stomach ${i.stomachFullness}');
    if (i.endTime != null) line.write('; taken over ${_span(i.endTime!.difference(i.time))}');
    if (i.notes.isNotEmpty) line.write('; note: ${options.hideNotes ? '[omitted]' : i.notes}');
    b.writeln(line);
  }
  if (doses.length > maxDoses) b.writeln('- ... and ${doses.length - maxDoses} more doses (see the month page for totals).');

  // Curves: one estimate per compound, plus where they overlap.
  b.writeln('\n## Estimated curve (model, not measured)');
  final windows = <String, (DateTime, DateTime)>{};
  final byKeyDoses = <String, List<Ingestion>>{};
  for (final i in doses) {
    byKeyDoses.putIfAbsent(i.substanceKey, () => []).add(i);
  }
  for (final entry in byKeyDoses.entries) {
    final s = byKey[entry.key];
    if (s == null) {
      b.writeln('- ${entry.key}: not in the reference data, no curve.');
      continue;
    }
    if (entry.key == 'alcohol') {
      final drinks = [for (final i in entry.value) alcoholDrinkFrom(i, settings)];
      final pool = effectSeries(drinks, first, settings);
      if (pool.isEmpty) continue;
      var peakAt = pool.first.$1;
      var peak = 0.0;
      for (final (t, v) in pool) {
        if (v > peak) {
          peak = v;
          peakAt = t;
        }
      }
      final clear = estimatedClearTime(pool);
      final std = entry.value.fold<double>(0, (s, i) => s + (i.dose ?? 0)) / 14.0;
      b.writeln('- Alcohol: ${_plural(std, 'standard drink')}; est. peak BAC ${estimateBac(peak, settings).toStringAsFixed(3)}% around ${_hm(peakAt)}; '
          '${clear == null ? 'no clear time within the window' : 'est. below 0.05 standard drinks in the body by ${_hm(clear)}${clear.day != first.day ? ' next day' : ''}'}.');
      windows['Alcohol'] = (first, clear ?? pool.last.$1);
      continue;
    }
    final curve = <CurveIngestion>[];
    for (final i in entry.value) {
      final roa = s.nearestRoute(i.route);
      if (roa == null) continue;
      curve.add(CurveIngestion(substanceKey: s.key, roaId: roa.id, amount: i.dose ?? roa.doseCommon?.min ?? 1.0, occurredAt: i.time));
    }
    final points = sessionEffectSeries(curve, byKey, now: experience.sortDate.add(const Duration(days: 2)));
    if (points.isEmpty) continue;
    var peak = 0.0;
    var peakAt = points.first.$1;
    for (final (t, v) in points) {
      if (v > peak) {
        peak = v;
        peakAt = t;
      }
    }
    final limit = peak * 0.1;
    final noticeable = points.where((p) => p.$2 >= limit).toList();
    final from = noticeable.first.$1;
    final to = noticeable.last.$1;
    windows[s.name] = (from, to);
    final roa = s.nearestRoute(entry.value.first.route);
    b.writeln('- ${s.name}: noticeable from about ${_hm(from)}, peaks about ${_hm(peakAt)} (relative intensity ${_num(peak)}; 1.0 = a common dose), mostly gone by ${_hm(to)}${to.day != from.day ? ' next day' : ''}.'
        '${roa == null || _phases(roa).isEmpty ? '' : ' Reference timing for ${roa.route}: ${_phases(roa)}.'}');
  }
  final names = windows.keys.toList();
  for (var a = 0; a < names.length; a++) {
    for (var c = a + 1; c < names.length; c++) {
      final x = windows[names[a]]!;
      final y = windows[names[c]]!;
      final start = x.$1.isAfter(y.$1) ? x.$1 : y.$1;
      final end = x.$2.isBefore(y.$2) ? x.$2 : y.$2;
      if (end.difference(start).inMinutes >= 15) {
        b.writeln('- Overlap: ${names[a]} and ${names[c]} were both active ${_hm(start)}-${_hm(end)} (${_span(end.difference(start))}). Check the app\'s interaction notes for this pair.');
      }
    }
  }

  // Tolerance and recent use going in.
  final used = <String>{};
  final usedNames = <String, Set<String>>{};
  for (final i in doses) {
    final s = byKey[i.substanceKey];
    if (s != null && s.hasTolerance) {
      used.add(toleranceTrackKey(s));
      usedNames.putIfAbsent(toleranceTrackKey(s), () => {}).add(s.name);
    }
  }
  final before = [for (final e in allEvents) if (e.at.isBefore(first.subtract(const Duration(minutes: 1)))) e];
  final tracks = toleranceTracks(events: before, byKey: byKey, now: first);
  final tolerance = [for (final t in tracks) if (used.contains(t.key)) t];
  b.writeln('\n## Going in');
  for (final key in used) {
    final t = tolerance.where((t) => t.key == key).firstOrNull;
    final label = (usedNames[key]!.toList()..sort()).join(' / ');
    if (t == null) {
      b.writeln('- $label: no use in the 120 days before (tolerance none).');
    } else {
      b.writeln('- $label: tolerance ${t.word.toLowerCase()}, last used ${_span(first.difference(t.lastUse))} before.');
    }
  }
  final week = <String, int>{};
  for (final i in allLive) {
    if (i.experienceId == experience.id) continue;
    if (i.time.isBefore(first) && first.difference(i.time) <= const Duration(days: 7)) {
      final name = byKey[i.substanceKey]?.name ?? i.substanceKey;
      week[name] = (week[name] ?? 0) + 1;
    }
  }
  b.writeln(week.isEmpty ? '- Nothing else logged in the 7 days before.' : '- Other doses in the 7 days before: ${week.entries.map((e) => '${e.key} ${e.value}').join(', ')}.');

  if (notes.isNotEmpty) {
    b.writeln('\n## Notes during');
    for (final n in notes) {
      b.writeln('- ${_hm(n.time)} (+${_span(n.time.difference(first))}${n.time.isBefore(first) ? ' before first dose' : ''}): ${options.hideNotes ? '[omitted]' : n.note}');
    }
  }
  if (ratings.isNotEmpty) {
    b.writeln('\n## Ratings');
    for (final r in ratings) {
      final scores = _json(r.scoresJson);
      final text = scores.entries.map((e) => '${e.key} ${e.value}').join(', ');
      b.writeln('- ${r.time == null ? 'overall' : _hm(r.time!)}: ${[if (r.shulgin != null) 'Shulgin ${r.shulgin}', if (text.isNotEmpty) text].join('; ')}');
    }
  }
  return b.toString();
}

String _classWord(DoseClass c) => switch (c) {
      DoseClass.belowThreshold => 'below threshold',
      DoseClass.threshold => 'threshold',
      DoseClass.light => 'light',
      DoseClass.common => 'common',
      DoseClass.strong => 'strong',
      DoseClass.heavy => 'heavy',
    };

Map<String, dynamic> _json(String text) {
  try {
    final v = jsonDecode(text);
    return v is Map<String, dynamic> ? v : const {};
  } on Object {
    return const {};
  }
}

/// How much of the digest to put into one block of text for pasting into an AI.
enum SummarySize { small, medium, large }

/// The profile, plus (medium) the latest month, plus (large) the five latest experience sheets.
/// Roughly 0.5k, 1.5k and 4-8k tokens.
String composeSummary(Digest digest, SummarySize size) {
  final parts = <String>[digest.files['profile.md'] ?? ''];
  if (size != SummarySize.small) {
    final months = digest.files.keys.where((k) => k.startsWith('months/')).toList()..sort();
    if (months.isNotEmpty) parts.add(digest.files[months.last]!);
  }
  if (size == SummarySize.large) {
    for (final e in digest.index.take(5)) {
      parts.add(digest.files[e.path]!);
    }
  }
  return parts.join('\n---\n');
}

int estimateTokens(String text) => _tokens(text);
