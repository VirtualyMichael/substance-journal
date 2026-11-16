import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sj_core/sj_core.dart';

import 'active_now.dart';
import 'database.dart';
import 'reference_repository.dart';

/// The voice assistant link: while the person has switched it on (Settings > Voice assistant), the
/// app answers a small HTTP API on 127.0.0.1 so their own voice assistant (the Substance Journal MCP
/// server) can add doses, drinks and notes.
///
/// The database key never leaves the app. The assistant gets a random token, written to
/// `voice-assistant/link.json` in the app's data folder while the link is on and deleted when it goes
/// off; the app writes every entry itself, through the same database code as the screens, so
/// encryption, sync stamps and every live view behave as for an entry made by hand.
///
/// What the link can do is fixed here, not by the caller: insert one entry at a time (never edit or
/// delete anything), no later than now and no older than [AssistantCaps.maxBackdate], at most
/// [AssistantCaps.maxPerHour] assistant entries an hour, each request id once, and take back only
/// what this link itself added in the last [AssistantCaps.undoWindow] if nobody changed it since.

/// Version of link.json and of the `/v1` API.
const int assistantLinkVersion = 1;

/// The clock node assistant entries are stamped with (`...-mcp`), as the assistant's own server did.
const String assistantNode = 'mcp';

/// The app's version as shown to the assistant (keep in step with pubspec.yaml).
const String appVersionName = '2.0.1';

class AssistantCaps {
  const AssistantCaps({
    this.maxBackdate = const Duration(hours: 24),
    this.maxPerHour = 12,
    this.undoWindow = const Duration(minutes: 10),
    this.futureSlack = const Duration(minutes: 2),
    this.maxNoteChars = 500,
    this.maxBodyBytes = 64 * 1024,
    this.readTimeout = const Duration(seconds: 5),
    this.maxRecent = 20,
  });

  /// How far back an entry may be dated.
  final Duration maxBackdate;

  /// Doses, drinks and notes the assistant may add in any hour (counted from the journal itself).
  final int maxPerHour;

  /// How long the assistant may take back what it added.
  final Duration undoWindow;

  /// Clock difference tolerated for "now" (the assistant's computer clock is this one, but a request takes time).
  final Duration futureSlack;
  final int maxNoteChars;
  final int maxBodyBytes;
  final Duration readTimeout;

  /// Most entries `recent` returns: enough to check what was logged, not a way to read the journal.
  final int maxRecent;

  Map<String, Object> toJson() => {
        'max_backdate_hours': maxBackdate.inMinutes / 60,
        'max_entries_per_hour': maxPerHour,
        'undo_window_minutes': undoWindow.inMinutes,
        'max_note_chars': maxNoteChars,
        'max_body_bytes': maxBodyBytes,
        'max_recent': maxRecent,
        'future_allowed': false,
      };
}

/// An entry the assistant added, for the "Added by your voice assistant" message and its Undo.
class LinkAddition {
  const LinkAddition({required this.summary, required this.id, required this.table, required this.at});
  final String summary;
  final String id;

  /// `ingestions` or `timed_notes`.
  final String table;
  final DateTime at;
}

/// A refusal the assistant can read back as it is.
class LinkRefusal implements Exception {
  const LinkRefusal(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class _Created {
  _Created({required this.table, required this.id, required this.hlc, required this.createdAt, required this.experienceId, required this.experienceCreated, this.experienceHlc});
  final String table;
  final String id;
  final String hlc;
  final DateTime createdAt;
  final String experienceId;
  final bool experienceCreated;
  final String? experienceHlc;
}

final _requestId = RegExp(r'^[A-Za-z0-9_.:-]{1,100}$');

/// Compares in time that does not depend on where the strings differ.
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

String _newToken() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
}

String _iso(DateTime t) => t.toLocal().toIso8601String().split('.').first;

/// What the screens need from a link (a fake stands in for it in widget tests).
abstract interface class AssistantLinkHandle {
  Future<int> start();
  Future<void> stop();
  Stream<LinkAddition> get additions;
  Future<bool> undoFromApp(LinkAddition a);
}

class AssistantLink implements AssistantLinkHandle {
  AssistantLink({
    required this.db,
    required this.folder,
    required this.reference,
    DateTime Function()? now,
    this.caps = const AssistantCaps(),
    int? processId,
  })  : _now = now ?? DateTime.now,
        processId = processId ?? pid;

  final AppDatabase db;

  /// `voice-assistant` in the app's data folder (beside the journal).
  final Directory folder;

  /// The reference compounds plus the person's own, read fresh for every request.
  final ReferenceRepository Function() reference;
  final DateTime Function() _now;
  final AssistantCaps caps;
  final int processId;

  HttpServer? _server;
  String? _token;
  DateTime? _started;
  Future<void> _busy = Future.value();
  final _created = <String, _Created>{};
  final _byRequest = <String, Map<String, Object?>>{};
  final _additions = StreamController<LinkAddition>.broadcast();

  File get linkFile => File(p.join(folder.path, 'link.json'));
  bool get running => _server != null;
  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;

  /// The current token (tests and the link file only; never shown on screen).
  String? get token => _token;

  /// Every entry added through the link, as it is added.
  @override
  Stream<LinkAddition> get additions => _additions.stream;

  /// Starts listening on a free port of 127.0.0.1 with a new token, and writes link.json. Returns the port.
  @override
  Future<int> start() async {
    if (_server != null) return _server!.port;
    await removeStaleLinkFile(folder);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 10);
    server.autoCompress = false;
    _server = server;
    _token = _newToken();
    _started = _now();
    server.listen(_handle, onError: (Object _) {});
    try {
      await _writeLinkFile();
    } on Object {
      await stop();
      rethrow;
    }
    return server.port;
  }

  /// Stops answering and deletes link.json. What was added stays; the token is forgotten.
  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _created.clear();
    _byRequest.clear();
    await server?.close(force: true);
    try {
      if (linkFile.existsSync()) linkFile.deleteSync();
    } on Object {
      // Already gone, or the folder is locked; a stale file names a port nobody answers.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _additions.close();
  }

  /// Deletes a link.json left by an earlier run (the app was closed without turning the link off).
  static Future<void> removeStaleLinkFile(Directory folder) async {
    final f = File(p.join(folder.path, 'link.json'));
    try {
      if (f.existsSync()) f.deleteSync();
    } on Object {
      // Locked: it will be replaced when the link is next turned on.
    }
  }

  Future<void> _writeLinkFile() async {
    folder.createSync(recursive: true);
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['700', folder.path]);
    }
    final body = jsonEncode({
      'version': assistantLinkVersion,
      'port': _server!.port,
      'token': _token,
      'pid': processId,
      'started': _iso(_started!),
    });
    // Fresh file each time: write beside it, then move it into place.
    final tmp = File(p.join(folder.path, 'link.json.tmp'));
    if (tmp.existsSync()) tmp.deleteSync();
    tmp.writeAsStringSync(body, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', tmp.path]);
    }
    if (linkFile.existsSync()) linkFile.deleteSync();
    tmp.renameSync(linkFile.path);
  }

  // ---- HTTP ----------------------------------------------------------------------------------------

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !remote.isLoopback) {
        return await _close(request, HttpStatus.forbidden, {'error': 'Only this computer may use the link.'});
      }
      final host = (request.headers.host ?? '').toLowerCase();
      if (host != '127.0.0.1' && host != 'localhost') {
        return await _close(request, HttpStatus.forbidden, {'error': 'Wrong host.'});
      }
      final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final token = _token;
      if (token == null || !auth.startsWith('Bearer ') || !constantTimeEquals(auth.substring(7).trim(), token)) {
        return await _close(request, HttpStatus.unauthorized, {'error': 'Not linked. Turn on Settings > Voice assistant in the app.'});
      }
      if (request.contentLength > caps.maxBodyBytes) {
        return await _reject(request, HttpStatus.requestEntityTooLarge, 'Too large');
      }
      final path = request.uri.path;
      Map<String, Object?> body = const {};
      if (request.method == 'POST') {
        final text = await _readBody(request);
        if (text == null) return await _reject(request, HttpStatus.requestEntityTooLarge, 'Too large');
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map<String, Object?>) throw const FormatException();
          body = decoded;
        } on FormatException {
          return await _close(request, HttpStatus.badRequest, {'error': 'The body must be a JSON object.'});
        }
      } else if (request.method != 'GET') {
        return await _close(request, HttpStatus.methodNotAllowed, {'error': 'GET or POST only.'});
      }
      // One request at a time, so "was this request id used" and the hourly count are never raced.
      final done = Completer<void>();
      final previous = _busy;
      _busy = done.future;
      await previous;
      try {
        final (status, reply) = await _route(request.method, path, request.uri.queryParameters, body);
        await _close(request, status, reply);
      } finally {
        done.complete();
      }
    } on TimeoutException {
      await _reject(request, HttpStatus.requestTimeout, 'Too slow');
    } on Object catch (e) {
      try {
        await _close(request, HttpStatus.internalServerError, {'error': 'The app could not do that: ${e.runtimeType}.'});
      } on Object {
        await res.close().catchError((Object _) {});
      }
    }
  }

  Future<String?> _readBody(HttpRequest request) async {
    // The whole body must arrive within the read timeout. The subscription is only paused (not
    // cancelled) when giving up, so the connection is still there to answer on.
    final bytes = BytesBuilder(copy: false);
    final done = Completer<String?>();
    late final StreamSubscription<List<int>> sub;
    final timer = Timer(caps.readTimeout, () {
      if (done.isCompleted) return;
      sub.pause();
      done.completeError(TimeoutException('slow body'));
    });
    sub = request.listen(
      (chunk) {
        if (done.isCompleted) return;
        bytes.add(chunk);
        if (bytes.length > caps.maxBodyBytes) {
          sub.pause();
          done.complete(null);
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(utf8.decode(bytes.takeBytes(), allowMalformed: true));
      },
      cancelOnError: true,
    );
    try {
      return await done.future;
    } finally {
      timer.cancel();
    }
  }

  /// Answers and hangs up without reading the rest of the body, which may be endless.
  Future<void> _reject(HttpRequest request, int status, String reason) async {
    try {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write('HTTP/1.1 $status $reason\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
      await socket.flush();
      socket.destroy();
    } on Object {
      // The caller has gone.
    }
  }

  Future<void> _close(HttpRequest request, int status, Map<String, Object?> body) async {
    final res = request.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.persistentConnection = false;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<(int, Map<String, Object?>)> _route(String method, String path, Map<String, String> query, Map<String, Object?> body) async {
    try {
      return switch ((method, path)) {
        ('GET', '/v1/status') => (HttpStatus.ok, await status()),
        ('POST', '/v1/entries') => (HttpStatus.ok, await addEntry(body)),
        ('POST', '/v1/undo') => (HttpStatus.ok, await undo(body['ids'])),
        ('GET', '/v1/recent') => (HttpStatus.ok, await recent(person: query['person'], limit: int.tryParse(query['limit'] ?? ''))),
        ('GET', '/v1/active') => (HttpStatus.ok, await active(person: query['person'])),
        _ => (HttpStatus.notFound, <String, Object?>{'error': 'No such endpoint.'}),
      };
    } on LinkRefusal catch (e) {
      return (e.status, <String, Object?>{'error': e.message});
    }
  }

  // ---- what the endpoints do (public so tests can call them without HTTP too) --------------------

  Future<List<Person>> _people() async {
    final people = await db.activePeople();
    people.sort((a, b) => a.isDefault == b.isDefault ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : (a.isDefault ? -1 : 1));
    return people;
  }

  Future<Person> _person(Object? name) async {
    final people = await _people();
    if (people.isEmpty) throw const LinkRefusal(HttpStatus.conflict, 'The journal has no people yet.');
    final n = name is String ? name.trim().toLowerCase() : '';
    if (n.isEmpty) return people.first;
    for (final x in people) {
      if (x.name.toLowerCase() == n) return x;
    }
    throw LinkRefusal(HttpStatus.notFound, 'No person called ${name is String ? name.trim() : ''}. People: ${people.map((x) => x.name).join(', ')}.');
  }

  Future<Map<String, Object?>> status() async {
    final people = await _people();
    final presets = await (db.select(db.presets)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    final byKey = reference().byKey;
    return {
      'app': 'Substance Journal',
      'version': appVersionName,
      'link_version': assistantLinkVersion,
      'pid': processId,
      'people': [for (final x in people) {'name': x.name, 'default': x.isDefault}],
      'presets': {
        'dose': [
          for (final x in presets)
            if (x.substanceKey != 'alcohol')
              {'name': x.name, 'substance': x.substanceKey, 'substance_name': byKey[x.substanceKey]?.name ?? x.substanceKey, 'route': x.route, 'amount': x.amount, 'unit': x.unit},
        ],
        'drink': [
          for (final x in presets)
            if (x.substanceKey == 'alcohol') {'name': x.name, 'volume': x.amount, 'unit': x.unit, 'abv': _abv(x.detailsJson)},
        ],
      },
      'caps': caps.toJson(),
      'entries_last_hour': await entriesLastHour(),
    };
  }

  double _abv(String details) {
    try {
      final v = (jsonDecode(details) as Map)['abv'];
      return v is num ? v.toDouble() : 0;
    } on Object {
      return 0;
    }
  }

  /// Assistant entries (doses, drinks and notes stamped `-mcp`) made in the last hour, whoever made them.
  Future<int> entriesLastHour() async {
    final cutoff = '${(db.nowMillis - const Duration(hours: 1).inMilliseconds).toString().padLeft(15, '0')}-';
    final row = await db.customSelect(
      "SELECT (SELECT count(*) FROM ingestions WHERE hlc >= ? AND hlc LIKE '%-mcp') + (SELECT count(*) FROM timed_notes WHERE hlc >= ? AND hlc LIKE '%-mcp') AS n",
      variables: [Variable.withString(cutoff), Variable.withString(cutoff)],
      readsFrom: {db.ingestions, db.timedNotes},
    ).getSingle();
    return row.read<int>('n');
  }

  String _text(Map<String, Object?> body, String key, {int max = 80, bool required = true}) {
    final v = body[key];
    final s = v is String ? v.trim() : '';
    if (required && s.isEmpty) throw LinkRefusal(HttpStatus.badRequest, 'Missing $key.');
    if (s.length > max) throw LinkRefusal(HttpStatus.badRequest, '$key is too long.');
    return s;
  }

  double _number(Map<String, Object?> body, String key, {required double max, bool allowZero = false}) {
    final v = body[key];
    if (v is! num || !v.isFinite || v < 0 || (!allowZero && v == 0) || v > max) {
      throw LinkRefusal(HttpStatus.badRequest, '$key must be a number${allowZero ? '' : ' more than zero'} up to ${max.toStringAsFixed(0)}.');
    }
    return v.toDouble();
  }

  /// Adds one entry. Body: `{request_id, kind: dose|drink|preset|note, person, at, substance, route,
  /// dose, unit, notes, drink, volume, volume_unit, abv, preset, text}`.
  Future<Map<String, Object?>> addEntry(Map<String, Object?> body) async {
    final requestId = body['request_id'];
    if (requestId is! String || !_requestId.hasMatch(requestId)) {
      throw const LinkRefusal(HttpStatus.badRequest, 'request_id must be 1 to 100 letters, digits or ._:-');
    }
    final seen = _byRequest[requestId] ?? await _fromJournal(requestId);
    if (seen != null) return {...seen, 'duplicate': true};

    final kind = body['kind'];
    if (kind is! String || !const {'dose', 'drink', 'preset', 'note'}.contains(kind)) {
      throw const LinkRefusal(HttpStatus.badRequest, 'kind must be dose, drink, preset or note.');
    }
    final person = await _person(body['person']);
    final now = _now();
    final atText = body['at'];
    final parsed = atText is String ? DateTime.tryParse(atText) : null;
    if (parsed == null) throw const LinkRefusal(HttpStatus.badRequest, 'at must be a date and time (ISO 8601, local time).');
    final at = parsed.toLocal();
    if (at.isAfter(now.add(caps.futureSlack))) {
      throw const LinkRefusal(HttpStatus.unprocessableEntity, 'That time is in the future. The assistant can only log what already happened.');
    }
    if (at.isBefore(now.subtract(caps.maxBackdate))) {
      throw LinkRefusal(HttpStatus.unprocessableEntity, 'That is more than ${caps.maxBackdate.inHours} hours ago. Add older entries in the app.');
    }
    final used = await entriesLastHour();
    if (used >= caps.maxPerHour) {
      throw LinkRefusal(HttpStatus.tooManyRequests, 'The assistant can add at most ${caps.maxPerHour} entries an hour, as a safety limit. Add more in the app.');
    }

    final Map<String, Object?> reply;
    if (kind == 'note') {
      final text = _text(body, 'text', max: caps.maxNoteChars);
      reply = await _addNote(person, at, text, requestId);
    } else {
      reply = await _addIngestion(kind, person, at, body, requestId);
    }
    _byRequest[requestId] = reply;
    if (_byRequest.length > 500) _byRequest.remove(_byRequest.keys.first);
    _additions.add(LinkAddition(summary: reply['summary']! as String, id: reply['id']! as String, table: reply['table']! as String, at: at));
    return {...reply, 'duplicate': false};
  }

  /// A request already saved in an earlier run of the link (drinks and doses keep their request id).
  Future<Map<String, Object?>?> _fromJournal(String requestId) async {
    final found = await db.customSelect(
      'SELECT id FROM ingestions WHERE instr(details_json, ?) > 0 LIMIT 1',
      variables: [Variable.withString('"requestId":"$requestId"')],
      readsFrom: {db.ingestions},
    ).getSingleOrNull();
    if (found == null) return null;
    final row = await (db.select(db.ingestions)..where((t) => t.id.equals(found.read<String>('id')))).getSingle();
    return {'ok': true, 'id': row.id, 'hlc': row.hlc, 'table': 'ingestions', 'experience_id': row.experienceId, 'summary': 'already saved', 'at': _iso(row.time)};
  }

  Future<Map<String, Object?>> _addNote(Person person, DateTime at, String text, String requestId) async {
    return db.stampedAs(assistantNode, () => db.transaction(() async {
          final exp = await db.recentExperienceFor(person.id, at);
          if (exp == null) {
            throw const LinkRefusal(HttpStatus.conflict, 'There is no session in the 12 hours around then to put the note on. Log a dose first.');
          }
          final note = await db.addTimedNote(experienceId: exp.id, time: at, note: text);
          _created[note.id] = _Created(table: 'timed_notes', id: note.id, hlc: note.hlc, createdAt: _now(), experienceId: exp.id, experienceCreated: false);
          return <String, Object?>{
            'ok': true,
            'id': note.id,
            'hlc': note.hlc,
            'table': 'timed_notes',
            'experience_id': exp.id,
            'experience_created': false,
            'at': _iso(at),
            'summary': 'note "$text" for ${person.name}',
          };
        }));
  }

  Future<Map<String, Object?>> _addIngestion(String kind, Person person, DateTime at, Map<String, Object?> body, String requestId) async {
    final notes = _text(body, 'notes', max: caps.maxNoteChars, required: false);
    final details = <String, Object?>{};
    final String substance;
    final String route;
    final double dose;
    final String unit;
    final String summary;
    if (kind == 'drink') {
      final name = _text(body, 'drink', max: 80);
      final volume = _number(body, 'volume', max: 5000);
      final volumeUnit = _text(body, 'volume_unit', max: 10);
      if (!drinkVolumeUnits.contains(volumeUnit)) {
        throw LinkRefusal(HttpStatus.badRequest, 'volume_unit must be one of ${drinkVolumeUnits.join(', ')}.');
      }
      final abv = _number(body, 'abv', max: 100, allowZero: true);
      substance = 'alcohol';
      route = 'oral';
      dose = drinkGrams(volume, volumeUnit, abv);
      unit = 'g';
      details.addAll({'drink': name, 'volume': volume, 'volumeUnit': volumeUnit, 'abv': abv});
      summary = '$name for ${person.name}';
    } else {
      substance = _text(body, 'substance', max: 80);
      route = _text(body, 'route', max: 40);
      dose = _number(body, 'dose', max: 1000000);
      unit = _text(body, 'unit', max: 20);
      if (substance == 'alcohol') throw const LinkRefusal(HttpStatus.badRequest, 'Log alcohol as a drink.');
      final known = reference().byKey[substance];
      if (known == null) throw LinkRefusal(HttpStatus.badRequest, 'The app does not know the compound "$substance".');
      final preset = kind == 'preset' ? _text(body, 'preset', max: 80) : '';
      if (preset.isNotEmpty) details['preset'] = preset;
      summary = '${preset.isNotEmpty ? '$preset: ' : ''}${_amount(dose)} $unit of ${known.name}, $route, for ${person.name}';
    }
    return db.stampedAs(assistantNode, () => db.transaction(() async {
          var exp = await db.recentExperienceFor(person.id, at);
          final created = exp == null;
          exp ??= await db.addExperience(personId: person.id, sortDate: at, createdAt: _now());
          final row = await db.addIngestion(
            experience: exp,
            substanceKey: substance,
            route: route,
            time: at,
            dose: dose,
            unit: unit,
            notes: notes,
            details: {...details, 'source': 'mcp', 'addedBy': 'voice assistant', 'experienceCreated': created, 'requestId': requestId},
          );
          _created[row.id] = _Created(
            table: 'ingestions',
            id: row.id,
            hlc: row.hlc,
            createdAt: _now(),
            experienceId: exp.id,
            experienceCreated: created,
            experienceHlc: created ? exp.hlc : null,
          );
          return <String, Object?>{
            'ok': true,
            'id': row.id,
            'hlc': row.hlc,
            'table': 'ingestions',
            'experience_id': exp.id,
            'experience_created': created,
            'dose': dose,
            'unit': unit,
            'at': _iso(at),
            'summary': summary,
          };
        }));
  }

  String _amount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Takes back entries this link added in the last [AssistantCaps.undoWindow] that nobody has changed
  /// since. Anything else in [ids] is left alone and reported. A session the link started goes too
  /// once nothing is left in it.
  Future<Map<String, Object?>> undo(Object? ids) async {
    if (ids is! List || ids.isEmpty || ids.length > 50 || ids.any((x) => x is! String)) {
      throw const LinkRefusal(HttpStatus.badRequest, 'ids must be a list of 1 to 50 entry ids.');
    }
    final now = _now();
    final removed = <String>[];
    final skipped = <Map<String, String>>[];
    final sessions = <_Created>[];
    await db.stampedAs(assistantNode, () => db.transaction(() async {
          for (final id in ids.cast<String>()) {
            final c = _created[id];
            if (c == null) {
              skipped.add({'id': id, 'reason': 'not added through this link'});
              continue;
            }
            if (now.difference(c.createdAt) > caps.undoWindow) {
              skipped.add({'id': id, 'reason': 'added more than ${caps.undoWindow.inMinutes} minutes ago'});
              continue;
            }
            final (hlc, deleted) = await _rowState(c);
            if (hlc == null || deleted) {
              skipped.add({'id': id, 'reason': 'already gone'});
            } else if (hlc != c.hlc) {
              skipped.add({'id': id, 'reason': 'changed in the app, so it was left alone'});
            } else {
              if (c.table == 'ingestions') {
                await db.setIngestionDeleted(id, true);
              } else {
                await db.deleteTimedNote(id);
              }
              removed.add(id);
              _created.remove(id);
              if (c.experienceCreated) sessions.add(c);
            }
          }
          for (final s in sessions) {
            await _dropEmptySession(s.experienceId, s.experienceHlc);
          }
        }));
    return {'removed': removed, 'skipped': skipped};
  }

  Future<(String?, bool)> _rowState(_Created c) async {
    if (c.table == 'ingestions') {
      final r = await (db.select(db.ingestions)..where((t) => t.id.equals(c.id))).getSingleOrNull();
      return (r?.hlc, r?.deleted ?? true);
    }
    final r = await (db.select(db.timedNotes)..where((t) => t.id.equals(c.id))).getSingleOrNull();
    return (r?.hlc, r?.deleted ?? true);
  }

  Future<void> _dropEmptySession(String experienceId, String? expectedHlc) async {
    final live = await (db.select(db.ingestions)..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))).get();
    final notes = await (db.select(db.timedNotes)..where((t) => t.experienceId.equals(experienceId) & t.deleted.equals(false))).get();
    if (live.isNotEmpty || notes.isNotEmpty) return;
    final q = db.update(db.experiences)..where((t) => t.id.equals(experienceId) & t.deleted.equals(false));
    if (expectedHlc != null) q.where((t) => t.hlc.equals(expectedHlc));
    await q.write(ExperiencesCompanion(deleted: const Value(true), hlc: Value(db.nextHlc())));
  }

  /// The person pressed Undo on "Added by your voice assistant": their own action, so no window and a normal stamp.
  @override
  Future<bool> undoFromApp(LinkAddition a) async {
    final c = _created.remove(a.id);
    var done = false;
    await db.transaction(() async {
      if (a.table == 'ingestions') {
        final r = await (db.select(db.ingestions)..where((t) => t.id.equals(a.id))).getSingleOrNull();
        if (r != null && !r.deleted) {
          await db.setIngestionDeleted(a.id, true);
          done = true;
        }
      } else {
        final r = await (db.select(db.timedNotes)..where((t) => t.id.equals(a.id))).getSingleOrNull();
        if (r != null && !r.deleted) {
          await db.deleteTimedNote(a.id);
          done = true;
        }
      }
      if (done && c != null && c.experienceCreated) await _dropEmptySession(c.experienceId, null);
    });
    return done;
  }

  /// The latest few doses, drinks and notes for one person, newest first.
  Future<Map<String, Object?>> recent({String? person, int? limit}) async {
    final who = await _person(person);
    final n = (limit ?? 5).clamp(1, caps.maxRecent);
    final doses = await (db.select(db.ingestions)
          ..where((t) => t.personId.equals(who.id) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.time)])
          ..limit(n))
        .get();
    final noteRows = await (db.select(db.timedNotes).join([innerJoin(db.experiences, db.experiences.id.equalsExp(db.timedNotes.experienceId))])
          ..where(db.experiences.personId.equals(who.id) & db.timedNotes.deleted.equals(false) & db.experiences.deleted.equals(false))
          ..orderBy([OrderingTerm.desc(db.timedNotes.time)])
          ..limit(n))
        .map((r) => r.readTable(db.timedNotes))
        .get();
    final byKey = reference().byKey;
    final items = <(DateTime, Map<String, Object?>)>[
      for (final i in doses) (i.time, _ingestionJson(i, byKey)),
      for (final x in noteRows)
        (x.time, {'id': x.id, 'kind': 'note', 'at': _iso(x.time), 'note': x.note, 'by_assistant': x.hlc.endsWith('-$assistantNode')}),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return {'person': who.name, 'default': who.isDefault, 'items': [for (final x in items.take(n)) x.$2]};
  }

  Map<String, Object?> _ingestionJson(Ingestion i, Map<String, Substance> byKey) {
    Map<String, Object?> details;
    try {
      details = (jsonDecode(i.detailsJson) as Map).cast<String, Object?>();
    } on Object {
      details = const {};
    }
    final drink = i.substanceKey == 'alcohol';
    return {
      'id': i.id,
      'kind': drink ? 'drink' : 'dose',
      'at': _iso(i.time),
      'substance': i.substanceKey,
      'name': byKey[i.substanceKey]?.name ?? i.substanceKey,
      'route': i.route,
      'dose': i.dose,
      'unit': i.unit,
      if (drink) 'drink': details['drink'],
      if (drink) 'standard_drinks': double.parse(standardDrinksFromGrams(i.dose ?? 0).toStringAsFixed(2)),
      'by_assistant': details['source'] == 'mcp' || i.hlc.endsWith('-$assistantNode'),
    };
  }

  /// What is still working for one person (the app's own Active now), and the last day's drinks.
  Future<Map<String, Object?>> active({String? person}) async {
    final who = await _person(person);
    final now = _now();
    final rows = await (db.select(db.ingestions)
          ..where((t) => t.personId.equals(who.id) & t.deleted.equals(false) & t.time.isBiggerOrEqualValue(now.subtract(const Duration(hours: 48))))
          ..orderBy([(t) => OrderingTerm.asc(t.time)]))
        .get();
    final list = activeNow(ingestions: rows, reference: reference(), now: now);
    final midnight = DateTime(now.year, now.month, now.day);
    final drinks = [
      for (final r in rows)
        if (r.substanceKey == 'alcohol' && !r.time.isAfter(now) && r.time.isAfter(now.subtract(const Duration(hours: 24)))) r,
    ];
    final today = drinks.where((r) => !r.time.isBefore(midnight)).fold<double>(0, (s, r) => s + standardDrinksFromGrams(r.dose ?? 0));
    return {
      'person': who.name,
      'default': who.isDefault,
      'now': _iso(now),
      'substances': [
        for (final s in list)
          {
            'substance': s.substance.key,
            'name': s.substance.name,
            'route': s.latest.ingestion.route,
            'phase': s.latest.phase.name,
            'phase_label': s.latest.phase.label,
            'doses': s.doses.length,
            'last_at': _iso(s.latest.ingestion.time),
            'last_dose': s.latest.ingestion.dose,
            'unit': s.latest.ingestion.unit,
            'full_effect_at': _iso(s.latest.fullEffectAt),
            'peak_ends_at': _iso(s.latest.peakEndsAt),
            'main_effects_end_at': _iso(s.latest.mainEffectsEndAt),
            'linger_ends_at': _iso(s.latest.lingerEndsAt),
          },
      ],
      'alcohol': {
        'standard_drinks_today': double.parse(today.toStringAsFixed(2)),
        'drinks_last_24h': [
          for (final r in drinks) {'at': _iso(r.time), 'grams': r.dose, 'standard_drinks': double.parse(standardDrinksFromGrams(r.dose ?? 0).toStringAsFixed(2))},
        ],
      },
    };
  }
}
