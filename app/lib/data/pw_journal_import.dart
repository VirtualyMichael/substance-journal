import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;

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
    this.id = '',
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

  /// Position in the file (`experience-ingestion`), so one dose can be mapped on its own.
  final String id;
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

  PwIngestion withRoute(String route) => PwIngestion(
        id: id,
        substanceName: substanceName,
        route: route,
        time: time,
        endTime: endTime,
        dose: dose,
        unit: unit,
        isEstimate: isEstimate,
        stdDev: stdDev,
        notes: notes,
        stomach: stomach,
        consumer: consumer,
        customUnitId: customUnitId,
      );
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
    this.experienceKeys = const [],
    this.ingestionKeys = const [],
  });

  /// Field names found in the file (never values), to diagnose a file that reads wrongly.
  final List<String> experienceKeys;
  final List<String> ingestionKeys;

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

/// Field names of a record, for explaining a problem without showing any values.
String _keys(Map<String, dynamic> m) => (m.keys.toList()..sort()).join(', ');

/// The substance's name, wherever this export version keeps it: a plain field, a nested
/// object, or a reference to one of the file's custom substances.
String? _substanceName(Map<String, dynamic> m, Map<String, String> customNames) {
  final direct = _string(m, const ['substanceName', 'substance_name', 'customSubstanceName']);
  if (direct != null) return direct;
  for (final key in const ['substance', 'substanceCompanion']) {
    final v = m[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    if (v is Map<String, dynamic>) {
      final n = _string(v, const ['name', 'substanceName']);
      if (n != null) return n;
    }
  }
  final custom = _string(m, const ['customSubstanceId', 'customSubstance']);
  if (custom != null && customNames[custom] != null) return customNames[custom];
  return _string(m, const ['name']);
}

PwIngestion _ingestionFrom(Map<String, dynamic> m, String id, Map<String, String> customNames) {
  // Some versions wrap each dose as {"ingestion": {...}, ...companions}.
  final inner = m['ingestion'];
  if (inner is Map<String, dynamic>) m = {...m, ...inner};
  final name = _substanceName(m, customNames);
  if (name == null) throw FormatException('no substance name (fields: ${_keys(m)})');
  final time = _time(_first(m, const ['time', 'ingestionTime', 'date']));
  if (time == null) throw FormatException('time is missing or not a date (fields: ${_keys(m)})');
  final route = _string(m, const ['administrationRoute', 'route']);
  return PwIngestion(
    id: id,
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

PwExperience _experienceFrom(Map<String, dynamic> m, List<String> problems, int index, Map<String, String> customNames) {
  final ingestions = <PwIngestion>[];
  final rows = _maps(_first(m, const ['ingestions', 'ingestionsWithCompanions']));
  for (var i = 0; i < rows.length; i++) {
    try {
      ingestions.add(_ingestionFrom(rows[i], '$index-$i', customNames));
    } on FormatException catch (e) {
      problems.add('Experience ${index + 1}, ingestion ${i + 1}: ${e.message}');
    }
  }
  final notes = <PwNote>[];
  for (final n in _maps(_first(m, const ['timedNotes', 'timedNote', 'notesTimed']))) {
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
  for (final r in _maps(_first(m, const ['ratings', 'shulginRatings', 'shulginRating']))) {
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
  final customNames = {
    for (final c in _maps(decoded['customSubstances']))
      if (_string(c, const ['id']) != null && _string(c, const ['name']) != null) _string(c, const ['id'])!: _string(c, const ['name'])!,
  };
  final rows = _maps(decoded['experiences']);
  final experienceKeys = <String>{for (final r in rows) ...r.keys};
  final ingestionKeys = <String>{
    for (final r in rows)
      for (final i in _maps(_first(r, const ['ingestions', 'ingestionsWithCompanions']))) ...i.keys,
  };
  for (var i = 0; i < rows.length; i++) {
    try {
      experiences.add(_experienceFrom(rows[i], problems, i, customNames));
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
  return PwExport(
    experiences: experiences,
    customSubstances: customSubstances,
    customUnits: customUnits,
    problems: problems,
    experienceKeys: (experienceKeys.toList()..sort()),
    ingestionKeys: (ingestionKeys.toList()..sort()),
  );
}

PwExport parsePwJournalFile(String path) {
  final file = File(path);
  if (!file.existsSync()) throw PwImportException('Could not find $path');
  return parsePwJournalJson(file.readAsStringSync());
}

// ---- choosing what to import and how ----

/// What a PsychonautWiki substance should become: a reference compound, or a custom one.
class PwCompound {
  const PwCompound.reference(String this.key) : customName = null;
  const PwCompound.custom(String this.customName) : key = null;
  final String? key;
  final String? customName;

  Map<String, Object?> toJson() => {if (key != null) 'key': key, if (customName != null) 'custom': customName};
  static PwCompound? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    if (j['key'] is String) return PwCompound.reference(j['key'] as String);
    if (j['custom'] is String) return PwCompound.custom(j['custom'] as String);
    return null;
  }

  @override
  bool operator ==(Object other) => other is PwCompound && other.key == key && other.customName == customName;
  @override
  int get hashCode => Object.hash(key, customName);
}

/// A choice for a single dose that differs from its group.
class PwOverride {
  const PwOverride({this.compound, this.route});
  final PwCompound? compound;
  final String? route;
}

/// Routes a dose can be mapped to.
const List<String> pwRoutes = [
  'oral', 'sublingual', 'buccal', 'insufflated', 'smoked', 'inhaled', 'vaporized',
  'rectal', 'transdermal', 'subcutaneous', 'intramuscular', 'intravenous',
];

/// The user's decisions about an import: which experiences to bring over, which compound each
/// PsychonautWiki name becomes, which route each (name, route) pair becomes, and per-dose
/// exceptions. Starts from automatic matching; [saved] (from an earlier import) refines it.
class PwImportPlan {
  PwImportPlan(this.export, this.reference, {Map<String, Object?> saved = const {}}) {
    selected.addAll(List.generate(export.experiences.length, (i) => i));
    final names = saved['compounds'];
    if (names is Map<String, dynamic>) {
      for (final e in names.entries) {
        final c = PwCompound.fromJson(e.value);
        // A remembered reference compound must still exist.
        if (c != null && (c.key == null || reference.byKey.containsKey(c.key))) compoundByName[e.key] = c;
      }
    }
    final routes = saved['routes'];
    if (routes is Map<String, dynamic>) {
      for (final e in routes.entries) {
        if (e.value is String) routeByGroup[e.key] = e.value as String;
      }
    }
  }

  final PwExport export;
  final ReferenceRepository reference;
  final Set<int> selected = {};
  final Map<String, PwCompound> compoundByName = {};
  final Map<String, String> routeByGroup = {};
  final Map<String, PwOverride> overrides = {};

  /// Join one person's doses taken within [combineGap] of each other into a single experience.
  bool combine = true;
  Duration combineGap = const Duration(hours: 12);

  static String nameKey(String name) => name.trim().toLowerCase();
  static String groupKey(String name, String route) => '${nameKey(name)}|$route';

  PwCompound defaultCompound(String name) {
    final key = catalogKeyFor(name, reference);
    return key != null ? PwCompound.reference(key) : PwCompound.custom(name.trim());
  }

  PwCompound compoundFor(PwIngestion i) =>
      overrides[i.id]?.compound ?? compoundByName[nameKey(i.substanceName)] ?? defaultCompound(i.substanceName);

  String routeFor(PwIngestion i) => overrides[i.id]?.route ?? routeByGroup[groupKey(i.substanceName, i.route)] ?? i.route;

  /// Every ingestion in the experiences that are selected.
  Iterable<PwIngestion> get chosenIngestions => [
        for (final idx in selected) ...export.experiences[idx].ingestions,
      ];

  Map<String, Object?> toSaved() => {
        'compounds': {for (final e in compoundByName.entries) e.key: e.value.toJson()},
        'routes': routeByGroup,
      };
}

// ---- importing ----

class PwImportResult {
  const PwImportResult({
    required this.experiencesImported,
    required this.experiencesSkipped,
    required this.experiencesCreated,
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

  /// Experiences actually created (fewer than imported when nearby ones were combined).
  final int experiencesCreated;
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
Future<PwImportResult> importPwJournal(AppDatabase db, PwExport export, ReferenceRepository reference, {PwImportPlan? plan}) {
  final choices = plan ?? PwImportPlan(export, reference);
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

    Future<String> keyFor(PwCompound compound, String? unit) async {
      final reference = compound.key;
      if (reference != null) return reference;
      final name = compound.customName!;
      final cached = keyForName[name.toLowerCase()];
      if (cached != null) return cached;
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
      final key = await keyFor(choices.compoundByName[PwImportPlan.nameKey(u.substanceName)] ?? choices.defaultCompound(u.substanceName), u.originalUnit);
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
    String ingestionKey(String substanceKey, String route, DateTime time, double? dose) => _pwKey(substanceKey, route, time, dose);
    final existingCounts = <String, Map<String, int>>{};
    Future<Map<String, int>> countsFor(Person person) async {
      final cached = existingCounts[person.id];
      if (cached != null) return cached;
      final counts = <String, int>{};
      // Deleted ones count, and an edited one keeps the key it was imported under.
      for (final i in await db.ingestionsForPersonIncludingDeleted(person.id)) {
        final stored = i.detailsJson.isEmpty ? null : (jsonDecode(i.detailsJson) as Map<String, dynamic>)['importKey'];
        final key = stored is String ? stored : ingestionKey(i.substanceKey, i.route, i.time, i.dose);
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
    final pending = <_PendingExperience>[];
    final sorted = [
      for (final idx in choices.selected.toList()..sort()) export.experiences[idx],
    ]..sort((a, b) => a.sortDate.compareTo(b.sortDate));

    for (final e in sorted) {
      // Resolve each ingestion first so duplicates can be told apart from new ones.
      final resolved = <(PwIngestion, Person, String)>[];
      for (final i in e.ingestions) {
        final person = await personFor(i.consumer);
        resolved.add((i.withRoute(choices.routeFor(i)), person, await keyFor(choices.compoundFor(i), i.unit)));
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
      for (var n = 0; n < people.length; n++) {
        final personId = people[n];
        pending.add(_PendingExperience(
          personId: personId,
          sortDate: e.sortDate,
          title: e.title,
          text: e.text,
          isFavorite: e.isFavorite,
          locationName: e.locationName,
          latitude: e.latitude,
          longitude: e.longitude,
          createdAt: e.createdAt,
          doses: [...?groups[personId]],
          notes: n == 0 ? [...e.notes] : [],
          ratings: n == 0 ? [...e.ratings] : [],
        ));
      }
      imported++;
    }

    // Doses taken close together by the same person belong on one timeline.
    final toCreate = choices.combine ? _combine(pending, choices.combineGap) : pending;
    for (final p in toCreate) {
      // With combining on, doses close in time to something already in the journal (an alcohol night
      // logged in Alcohol mode, say) go into that experience rather than starting a second listing.
      final existing = choices.combine && p.doses.isNotEmpty ? await _nearbyExperience(db, p, choices.combineGap) : null;
      final experience = existing ?? await db.addExperience(
        personId: p.personId,
        sortDate: p.sortDate,
        title: p.title,
        notes: p.text,
        isFavorite: p.isFavorite,
        locationName: p.locationName,
        latitude: p.latitude,
        longitude: p.longitude,
        createdAt: p.createdAt,
      );
      if (existing != null && p.title.isNotEmpty && existing.title.isEmpty) await db.updateExperience(existing.id, title: p.title);
      for (final r in p.doses) {
        await _addIngestion(db, experience, r, unitIds);
        ingestionTotal++;
      }
      for (final n in p.notes) {
        await db.addTimedNote(
          experienceId: experience.id,
          time: n.time,
          note: n.text,
          colorValue: noteColorFor(n.colorName),
          showOnTimeline: n.onTimeline,
        );
        noteTotal++;
      }
      for (final r in p.ratings) {
        await db.addRating(experienceId: experience.id, time: r.time, shulgin: r.shulgin);
        ratingTotal++;
      }
    }

    return PwImportResult(
      experiencesImported: imported,
      experiencesSkipped: skipped,
      experiencesCreated: toCreate.length,
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

String _pwKey(String substanceKey, String route, DateTime time, double? dose) =>
    '$substanceKey|$route|${time.millisecondsSinceEpoch ~/ 1000}|${dose ?? ''}';

/// The person's existing experience whose doses are within [gap] of [p]'s, if any.
Future<Experience?> _nearbyExperience(AppDatabase db, _PendingExperience p, Duration gap) async {
  final rows = await db.ingestionsForPerson(p.personId);
  final spans = <String, (DateTime, DateTime)>{};
  for (final i in rows) {
    final s = spans[i.experienceId];
    spans[i.experienceId] = s == null ? (i.time, i.time) : (i.time.isBefore(s.$1) ? i.time : s.$1, i.time.isAfter(s.$2) ? i.time : s.$2);
  }
  String? best;
  Duration? bestGap;
  for (final e in spans.entries) {
    final before = p.first.difference(e.value.$2); // positive when the new doses start after the old ones end
    final after = e.value.$1.difference(p.last);
    final distance = before > Duration.zero ? before : (after > Duration.zero ? after : Duration.zero);
    if (distance <= gap && (bestGap == null || distance < bestGap)) {
      best = e.key;
      bestGap = distance;
    }
  }
  final id = best;
  if (id == null) return null;
  return (db.select(db.experiences)..where((t) => t.id.equals(id) & t.deleted.equals(false))).getSingleOrNull();
}

class _PendingExperience {
  _PendingExperience({
    required this.personId,
    required this.sortDate,
    required this.title,
    required this.text,
    required this.isFavorite,
    this.locationName,
    this.latitude,
    this.longitude,
    this.createdAt,
    required this.doses,
    required this.notes,
    required this.ratings,
  });

  final String personId;
  DateTime sortDate;
  String title;
  String text;
  bool isFavorite;
  String? locationName;
  double? latitude;
  double? longitude;
  DateTime? createdAt;
  final List<(PwIngestion, Person, String)> doses;
  final List<PwNote> notes;
  final List<PwRating> ratings;

  DateTime get first => doses.isEmpty ? sortDate : doses.map((d) => d.$1.time).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get last => doses.isEmpty ? sortDate : doses.map((d) => d.$1.time).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Chains each person's experiences whose doses are at most [gap] apart into one.
/// Experiences with no doses stay as they are.
List<_PendingExperience> _combine(List<_PendingExperience> all, Duration gap) {
  final result = <_PendingExperience>[];
  final byPerson = <String, List<_PendingExperience>>{};
  for (final p in all) {
    if (p.doses.isEmpty) {
      result.add(p);
    } else {
      byPerson.putIfAbsent(p.personId, () => []).add(p);
    }
  }
  for (final list in byPerson.values) {
    list.sort((a, b) => a.first.compareTo(b.first));
    _PendingExperience? current;
    for (final p in list) {
      if (current != null && p.first.difference(current.last) <= gap) {
        current.doses.addAll(p.doses);
        current.notes.addAll(p.notes);
        current.ratings.addAll(p.ratings);
        if (current.title.isEmpty) current.title = p.title;
        if (p.text.isNotEmpty && !current.text.contains(p.text)) {
          current.text = current.text.isEmpty ? p.text : '${current.text}\n\n${p.text}';
        }
        current.isFavorite = current.isFavorite || p.isFavorite;
        current.locationName ??= p.locationName;
        current.latitude ??= p.latitude;
        current.longitude ??= p.longitude;
        if (p.sortDate.isBefore(current.sortDate)) current.sortDate = p.sortDate;
      } else {
        current = p;
        result.add(p);
      }
    }
  }
  return result;
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
    details: {'importKey': _pwKey(r.$3, i.route, i.time, i.dose)},
  );
}
