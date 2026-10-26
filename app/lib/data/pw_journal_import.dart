import 'dart:convert';
import 'dart:io';

import 'custom_substances.dart';
import 'database.dart';
import 'reference_repository.dart';

/// Importer for PsychonautWiki Journal exports (the app's "Export" JSON file).
///
/// This reads the file format only; none of that app's code is used. The parser is lenient: it
/// accepts the field spellings seen across versions, skips what it cannot read and reports it.

class PwImportException implements Exception {
  const PwImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PwIngestion {
  const PwIngestion({
    required this.substanceName,
    required this.route,
    required this.time,
    this.endTime,
    this.dose,
    this.unit,
    this.isEstimate = false,
    this.stdDev,
    this.notes = '',
    this.stomach,
    this.consumer,
    this.customUnitId,
  });

  final String substanceName;
  final String route;
  final DateTime time;
  final DateTime? endTime;
  final double? dose;
  final String? unit;
  final bool isEstimate;
  final double? stdDev;
  final String notes;
  final String? stomach;

  /// The person who took it; null or blank means the owner of the journal.
  final String? consumer;
  final String? customUnitId;
}

class PwNote {
  const PwNote({required this.time, required this.text, this.colorName, this.onTimeline = true});
  final DateTime time;
  final String text;
  final String? colorName;
  final bool onTimeline;
}

class PwRating {
  const PwRating({required this.time, required this.shulgin});
  final DateTime? time;
  final String shulgin;
}

class PwExperience {
  const PwExperience({
    required this.title,
    required this.text,
    required this.sortDate,
    this.createdAt,
    this.isFavorite = false,
    this.locationName,
    this.latitude,
    this.longitude,
    this.ingestions = const [],
    this.notes = const [],
    this.ratings = const [],
  });

  final String title;
  final String text;
  final DateTime sortDate;
  final DateTime? createdAt;
  final bool isFavorite;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final List<PwIngestion> ingestions;
  final List<PwNote> notes;
  final List<PwRating> ratings;
}

class PwCustomSubstance {
  const PwCustomSubstance({required this.name, required this.units, this.description = ''});
  final String name;
  final String units;
  final String description;
}

class PwCustomUnit {
  const PwCustomUnit({
    required this.id,
    required this.substanceName,
    required this.route,
    required this.name,
    required this.unitSingular,
    this.unitPlural,
    this.dose,
    this.stdDev,
    required this.originalUnit,
    this.isEstimate = false,
    this.isArchived = false,
    this.note = '',
  });

  final String id;
  final String substanceName;
  final String route;
  final String name;
  final String unitSingular;
  final String? unitPlural;
  final double? dose;
  final double? stdDev;
  final String originalUnit;
  final bool isEstimate;
  final bool isArchived;
  final String note;
}

/// What was read from a PsychonautWiki Journal file, before anything is written.
class PwExport {
  const PwExport({
    required this.experiences,
    this.customSubstances = const [],
    this.customUnits = const [],
    this.problems = const [],
  });

  final List<PwExperience> experiences;
  final List<PwCustomSubstance> customSubstances;
  final List<PwCustomUnit> customUnits;
  final List<String> problems;

  int get ingestionCount => experiences.fold(0, (n, e) => n + e.ingestions.length);
  int get noteCount => experiences.fold(0, (n, e) => n + e.notes.length);
  int get ratingCount => experiences.fold(0, (n, e) => n + e.ratings.length);

  Set<String> get consumers => {
        for (final e in experiences)
          for (final i in e.ingestions)
            if (i.consumer != null && i.consumer!.trim().isNotEmpty && i.consumer!.trim().toLowerCase() != 'me') i.consumer!.trim(),
      };

  DateTime? get first => experiences.isEmpty ? null : experiences.map((e) => e.sortDate).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get last => experiences.isEmpty ? null : experiences.map((e) => e.sortDate).reduce((a, b) => a.isAfter(b) ? a : b);
}

// ---- parsing ----

Object? _first(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k) && m[k] != null) return m[k];
  }
  return null;
}

String? _string(Map<String, dynamic> m, List<String> keys) {
  final v = _first(m, keys);
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

double? _double(Map<String, dynamic> m, List<String> keys) {
  final v = _first(m, keys);
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

bool _bool(Map<String, dynamic> m, List<String> keys, {bool fallback = false}) {
  final v = _first(m, keys);
  return v is bool ? v : fallback;
}

/// Epoch milliseconds (what the app writes) or an ISO date string.
DateTime? _time(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) {
    final n = num.tryParse(v);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n.toInt());
    return DateTime.tryParse(v);
  }
  return null;
}

List<Map<String, dynamic>> _maps(Object? v) =>
    [if (v is List) for (final e in v) if (e is Map<String, dynamic>) e];

const _stomach = {
  'EMPTY': 'empty',
  'QUARTERFULL': 'quarter',
  'HALFFULL': 'half',
  'FULL': 'full',
  'VERYFULL': 'veryFull',
};

String? _stomachFrom(String? raw) {
  if (raw == null) return null;
  return _stomach[raw.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '')];
}

const _shulgin = {
  'MINUS': 'minus',
  'PLUSMINUS': 'plusMinus',
  'ONEPLUS': 'plus1',
  'TWOPLUS': 'plus2',
  'THREEPLUS': 'plus3',
  'FOURPLUS': 'plus4',
};

String? _shulginFrom(String? raw) {
  if (raw == null) return null;
  return _shulgin[raw.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '')];
}

/// The journal's note colours, as close to Material shades as the names allow.
const _noteColors = {
  'RED': 0xFFE57373,
  'ORANGE': 0xFFFFB74D,
  'YELLOW': 0xFFFFD54F,
  'GREEN': 0xFF81C784,
  'CYAN': 0xFF4DD0E1,
  'BLUE': 0xFF64B5F6,
  'PURPLE': 0xFFBA68C8,
  'PINK': 0xFFF06292,
  'BROWN': 0xFFA1887F,
};

int? noteColorFor(String? name) => name == null ? null : _noteColors[name.toUpperCase()];

PwIngestion _ingestionFrom(Map<String, dynamic> m) {
  final name = _string(m, const ['substanceName', 'substance']);
  if (name == null) throw const FormatException('substanceName is missing');
  final time = _time(_first(m, const ['time']));
  if (time == null) throw const FormatException('time is missing or not a date');
  final route = _string(m, const ['administrationRoute', 'route']);
  return PwIngestion(
    substanceName: name,
    route: (route ?? 'oral').toLowerCase(),
    time: time,
    endTime: _time(_first(m, const ['endTime'])),
    dose: _double(m, const ['dose']),
    unit: _string(m, const ['units', 'unit']),
    isEstimate: _bool(m, const ['isDoseAnEstimate', 'isEstimate']),
    stdDev: _double(m, const ['estimatedDoseStandardDeviation', 'estimatedDoseVariance']),
    notes: _string(m, const ['notes']) ?? '',
    stomach: _stomachFrom(_string(m, const ['stomachFullness'])),
    consumer: _string(m, const ['consumerName']),
    customUnitId: _string(m, const ['customUnitId']),
  );
}

PwExperience _experienceFrom(Map<String, dynamic> m, List<String> problems, int index) {
  final ingestions = <PwIngestion>[];
  final rows = _maps(m['ingestions']);
  for (var i = 0; i < rows.length; i++) {
    try {
      ingestions.add(_ingestionFrom(rows[i]));
    } on FormatException catch (e) {
      problems.add('Experience ${index + 1}, ingestion ${i + 1}: ${e.message}');
    }
  }
  final notes = <PwNote>[];
  for (final n in _maps(m['timedNotes'])) {
    final time = _time(n['time']);
    final text = _string(n, const ['note', 'text']);
    if (time == null || text == null) continue;
    notes.add(PwNote(
      time: time,
      text: text,
      colorName: _string(n, const ['color']),
      onTimeline: _bool(n, const ['isPartOfTimeline', 'showOnTimeline'], fallback: true),
    ));
  }
  final ratings = <PwRating>[];
  for (final r in _maps(_first(m, const ['ratings', 'shulginRatings']))) {
    final shulgin = _shulginFrom(_string(r, const ['option', 'rating']));
    if (shulgin != null) ratings.add(PwRating(time: _time(r['time']), shulgin: shulgin));
  }
  final location = m['location'];
  final loc = location is Map<String, dynamic> ? location : const <String, dynamic>{};
  final sortDate = _time(_first(m, const ['sortDate'])) ??
      _time(_first(m, const ['creationDate'])) ??
      (ingestions.isEmpty ? null : ingestions.map((i) => i.time).reduce((a, b) => a.isBefore(b) ? a : b));
  if (sortDate == null) throw const FormatException('no date');
  return PwExperience(
    title: _string(m, const ['title']) ?? '',
    text: _string(m, const ['text', 'description']) ?? '',
    sortDate: sortDate,
    createdAt: _time(_first(m, const ['creationDate'])),
    isFavorite: _bool(m, const ['isFavorite']),
    locationName: _string(loc, const ['name']),
    latitude: _double(loc, const ['latitude']),
    longitude: _double(loc, const ['longitude']),
    ingestions: ingestions,
    notes: notes,
    ratings: ratings,
  );
}

/// Parses the text of an export. Throws [PwImportException] when it is not one.
PwExport parsePwJournalJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const PwImportException('That file is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic> || decoded['experiences'] is! List) {
    throw const PwImportException('This does not look like a PsychonautWiki Journal export (no "experiences" list).');
  }
  final problems = <String>[];
  final experiences = <PwExperience>[];
  final rows = _maps(decoded['experiences']);
  for (var i = 0; i < rows.length; i++) {
    try {
      experiences.add(_experienceFrom(rows[i], problems, i));
    } on FormatException catch (e) {
      problems.add('Experience ${i + 1}: ${e.message}');
    }
  }
  final customSubstances = [
    for (final c in _maps(decoded['customSubstances']))
      if (_string(c, const ['name']) != null)
        PwCustomSubstance(
          name: _string(c, const ['name'])!,
          units: _string(c, const ['units', 'unit']) ?? 'mg',
          description: _string(c, const ['description']) ?? '',
        ),
  ];
  final customUnits = [
    for (final u in _maps(decoded['customUnits']))
      if (_string(u, const ['id']) != null && _string(u, const ['name']) != null && _string(u, const ['substanceName']) != null)
        PwCustomUnit(
          id: _string(u, const ['id'])!,
          substanceName: _string(u, const ['substanceName'])!,
          route: (_string(u, const ['administrationRoute', 'route']) ?? 'oral').toLowerCase(),
          name: _string(u, const ['name'])!,
          unitSingular: _string(u, const ['unit', 'unitSingular']) ?? _string(u, const ['name'])!,
          unitPlural: _string(u, const ['unitPlural']),
          dose: _double(u, const ['dose']),
          stdDev: _double(u, const ['estimatedDoseStandardDeviation']),
          originalUnit: _string(u, const ['originalUnit']) ?? 'mg',
          isEstimate: _bool(u, const ['isEstimate']),
          isArchived: _bool(u, const ['isArchived']),
          note: _string(u, const ['note']) ?? '',
        ),
  ];
  return PwExport(experiences: experiences, customSubstances: customSubstances, customUnits: customUnits, problems: problems);
}

PwExport parsePwJournalFile(String path) {
  final file = File(path);
  if (!file.existsSync()) throw PwImportException('Could not find $path');
  return parsePwJournalJson(file.readAsStringSync());
}

// ---- importing ----

class PwImportResult {
  const PwImportResult({
    required this.experiencesImported,
    required this.experiencesSkipped,
    required this.ingestions,
    required this.notes,
    required this.ratings,
    required this.customCompoundsCreated,
    required this.customUnitsCreated,
    required this.peopleCreated,
    required this.problems,
  });

  final int experiencesImported;
  final int experiencesSkipped;
  final int ingestions;
  final int notes;
  final int ratings;
  final List<String> customCompoundsCreated;
  final int customUnitsCreated;
  final List<String> peopleCreated;
  final List<String> problems;
}

String _slug(String name) => name.trim().toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');

/// The reference-data key for a PsychonautWiki substance name, or null if we do not have it.
String? catalogKeyFor(String name, ReferenceRepository reference) {
  final lower = name.trim().toLowerCase();
  final slug = _slug(name);
  for (final s in reference.substances) {
    if (isCustomKey(s.key)) continue;
    if (s.name.toLowerCase() == lower || s.key == slug) return s.key;
  }
  for (final s in reference.substances) {
    if (isCustomKey(s.key)) continue;
    if (s.commonNames.any((n) => n.toLowerCase() == lower)) return s.key;
  }
  return null;
}

const _personColors = [0xFFE07A5F, 0xFF3D9970, 0xFFD1495B, 0xFF2EB5C4, 0xFFE0A100, 0xFF7A6FF0];

/// Writes a PsychonautWiki Journal export into the journal, all or nothing.
///
/// - Substances are matched to the catalog by name. Ones we do not know (the app's custom
///   substances, or newer wiki pages) become custom compounds with your units.
/// - Consumers: no name or "Me" is the default person; any other name becomes (or matches) a person.
/// - Custom units are added unless one with the same compound, route and name already exists.
/// - An experience whose ingestions are all already in the journal is skipped whole, so importing
///   the same file twice adds nothing.
Future<PwImportResult> importPwJournal(AppDatabase db, PwExport export, ReferenceRepository reference) {
  return db.transaction(() async {
    final people = await db.activePeople();
    if (people.isEmpty) throw StateError('No people');
    final defaultPerson = people.firstWhere((p) => p.isDefault, orElse: () => people.first);
    final byName = {for (final p in people) p.name.toLowerCase(): p};
    final peopleCreated = <String>[];

    Future<Person> personFor(String? consumer) async {
      final name = consumer?.trim() ?? '';
      if (name.isEmpty || name.toLowerCase() == 'me') return defaultPerson;
      final existing = byName[name.toLowerCase()];
      if (existing != null) return existing;
      final person = await db.addPerson(name, colorValue: _personColors[peopleCreated.length % _personColors.length]);
      byName[name.toLowerCase()] = person;
      peopleCreated.add(name);
      return person;
    }

    // Custom compounds: reuse one with the same name, else create.
    final existingCustom = {
      for (final c in await db.watchCustomSubstances().first)
        if (!c.deleted) c.name.toLowerCase(): c,
    };
    final customCreated = <String>[];
    final unitFor = {for (final c in export.customSubstances) c.name.toLowerCase(): c};
    final keyForName = <String, String>{};

    Future<String> keyFor(String name, String? unit) async {
      final cached = keyForName[name.toLowerCase()];
      if (cached != null) return cached;
      final catalog = catalogKeyFor(name, reference);
      if (catalog != null) return keyForName[name.toLowerCase()] = catalog;
      var row = existingCustom[name.toLowerCase()];
      if (row == null) {
        final declared = unitFor[name.toLowerCase()];
        row = await db.addCustomSubstance(
          name: name,
          units: declared?.units ?? unit ?? 'mg',
          description: declared?.description ?? '',
        );
        existingCustom[name.toLowerCase()] = row;
        customCreated.add(name);
      }
      return keyForName[name.toLowerCase()] = '$customKeyPrefix${row.id}';
    }

    // Custom units, remembering the new id of each exported one.
    final haveUnits = {
      for (final u in await db.watchCustomUnits().first) '${u.substanceKey}|${u.route}|${u.name.toLowerCase()}': u.id,
    };
    final unitIds = <String, String>{};
    var unitsCreated = 0;
    for (final u in export.customUnits) {
      if (u.dose == null) continue;
      final key = await keyFor(u.substanceName, u.originalUnit);
      final lookup = '$key|${u.route}|${u.name.toLowerCase()}';
      final existing = haveUnits[lookup];
      if (existing != null) {
        unitIds[u.id] = existing;
        continue;
      }
      final row = await db.addCustomUnit(
        substanceKey: key,
        route: u.route,
        name: u.name,
        unitSingular: u.unitSingular,
        unitPlural: u.unitPlural,
        doseOfOneUnit: u.dose!,
        doseStdDev: u.stdDev,
        originalUnit: u.originalUnit,
        isEstimate: u.isEstimate,
        note: u.note,
      );
      if (u.isArchived) await db.updateCustomUnit(row.id, isArchived: true);
      haveUnits[lookup] = row.id;
      unitIds[u.id] = row.id;
      unitsCreated++;
    }

    // What each person already has, counted, so a repeat import adds nothing.
    String ingestionKey(String substanceKey, String route, DateTime time, double? dose) =>
        '$substanceKey|$route|${time.millisecondsSinceEpoch ~/ 1000}|${dose ?? ''}';
    final existingCounts = <String, Map<String, int>>{};
    Future<Map<String, int>> countsFor(Person person) async {
      final cached = existingCounts[person.id];
      if (cached != null) return cached;
      final counts = <String, int>{};
      for (final i in await db.ingestionsForPerson(person.id)) {
        final key = ingestionKey(i.substanceKey, i.route, i.time, i.dose);
        counts[key] = (counts[key] ?? 0) + 1;
      }
      return existingCounts[person.id] = counts;
    }

    final owner = defaultPerson;
    var imported = 0;
    var skipped = 0;
    var ingestionTotal = 0;
    var noteTotal = 0;
    var ratingTotal = 0;
    final sorted = [...export.experiences]..sort((a, b) => a.sortDate.compareTo(b.sortDate));

    for (final e in sorted) {
      // Resolve each ingestion first so duplicates can be told apart from new ones.
      final resolved = <(PwIngestion, Person, String)>[];
      for (final i in e.ingestions) {
        final person = await personFor(i.consumer);
        resolved.add((i, person, await keyFor(i.substanceName, i.unit)));
      }
      final fresh = <(PwIngestion, Person, String)>[];
      for (final r in resolved) {
        final counts = await countsFor(r.$2);
        final key = ingestionKey(r.$3, r.$1.route, r.$1.time, r.$1.dose);
        final already = counts[key] ?? 0;
        if (already > 0) {
          counts[key] = already - 1;
        } else {
          fresh.add(r);
        }
      }
      if (resolved.isNotEmpty && fresh.isEmpty) {
        skipped++;
        continue;
      }

      // An experience belongs to one person, so doses by different consumers go to one
      // experience each. Notes and ratings stay with the first (the owner's, if they took part).
      final groups = <String, List<(PwIngestion, Person, String)>>{};
      for (final r in fresh) {
        groups.putIfAbsent(r.$2.id, () => []).add(r);
      }
      final people = groups.isEmpty ? [owner.id] : groups.keys.toList();
      if (groups.containsKey(owner.id)) {
        people
          ..remove(owner.id)
          ..insert(0, owner.id);
      }
      Experience? primary;
      for (final personId in people) {
        final experience = await db.addExperience(
          personId: personId,
          sortDate: e.sortDate,
          title: e.title,
          notes: e.text,
          isFavorite: e.isFavorite,
          locationName: e.locationName,
          latitude: e.latitude,
          longitude: e.longitude,
          createdAt: e.createdAt,
        );
        primary ??= experience;
        for (final r in groups[personId] ?? const []) {
          await _addIngestion(db, experience, r, unitIds);
          ingestionTotal++;
        }
      }
      for (final n in e.notes) {
        await db.addTimedNote(
          experienceId: primary!.id,
          time: n.time,
          note: n.text,
          colorValue: noteColorFor(n.colorName),
          showOnTimeline: n.onTimeline,
        );
        noteTotal++;
      }
      for (final r in e.ratings) {
        await db.addRating(experienceId: primary!.id, time: r.time, shulgin: r.shulgin);
        ratingTotal++;
      }
      imported++;
    }

    return PwImportResult(
      experiencesImported: imported,
      experiencesSkipped: skipped,
      ingestions: ingestionTotal,
      notes: noteTotal,
      ratings: ratingTotal,
      customCompoundsCreated: customCreated,
      customUnitsCreated: unitsCreated,
      peopleCreated: peopleCreated,
      problems: export.problems,
    );
  });
}

Future<void> _addIngestion(AppDatabase db, Experience experience, (PwIngestion, Person, String) r, Map<String, String> unitIds) async {
  final i = r.$1;
  await db.addIngestion(
    experience: experience,
    substanceKey: r.$3,
    route: i.route,
    time: i.time,
    endTime: i.endTime,
    dose: i.dose,
    unit: i.unit,
    doseIsEstimate: i.isEstimate,
    doseStdDev: i.stdDev,
    stomachFullness: i.route == 'oral' ? i.stomach : null,
    notes: i.notes,
    customUnitId: i.customUnitId == null ? null : unitIds[i.customUnitId],
  );
}
