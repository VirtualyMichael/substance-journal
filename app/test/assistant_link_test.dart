import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:substance_journal_app/data/assistant_link.dart';
import 'package:substance_journal_app/data/database.dart';

import 'helpers.dart';

/// The voice assistant link against an in-memory journal and a throwaway folder, over real loopback HTTP.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding fakes HTTP; these tests talk to a real local server
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final reference = loadReference();

  late int nowMs;
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(nowMs);
  late AppDatabase db;
  late Directory tmp;
  late AssistantLink link;
  late Person me;

  AssistantLink makeLink({AssistantCaps caps = const AssistantCaps()}) => AssistantLink(
        db: db,
        folder: Directory(p.join(tmp.path, 'voice-assistant')),
        reference: () => reference,
        now: now,
        caps: caps,
        processId: 4242,
      );

  setUp(() async {
    nowMs = DateTime(2026, 7, 3, 21).millisecondsSinceEpoch;
    db = AppDatabase.memory(nowMillis: () => nowMs);
    me = await db.ensureDefaultPerson();
    await db.addPerson('Alex');
    await db.ensureDefaultDrinkPresets();
    await db.addDosePreset(substanceKey: 'lsd', route: 'sublingual', name: 'Usual tab', amount: 80, unit: 'µg', input: const {});
    tmp = Directory.systemTemp.createTempSync('sj_link_');
    link = makeLink();
    await link.start();
  });

  tearDown(() async {
    await link.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String? token, String? rawBody, AssistantLink? via}) async {
    final l = via ?? link;
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${l.port}$path'));
      final t = token ?? l.token;
      if (t != '') req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      if (body != null || rawBody != null) {
        req.headers.contentType = ContentType.json;
        req.write(rawBody ?? jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      return (res.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  String at({int minutesAgo = 0}) => now().subtract(Duration(minutes: minutesAgo)).toIso8601String();

  Map<String, Object?> dose(String id, {int minutesAgo = 0, String person = ''}) => {
        'request_id': id,
        'kind': 'dose',
        'person': person,
        'at': at(minutesAgo: minutesAgo),
        'substance': 'lsd',
        'route': 'sublingual',
        'dose': 100,
        'unit': 'µg',
        'notes': 'blue tab',
      };

  group('the link file', () {
    test('is written fresh when the link starts and removed when it stops', () async {
      final f = File(p.join(tmp.path, 'voice-assistant', 'link.json'));
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(j.keys.toSet(), {'version', 'port', 'token', 'pid', 'started'});
      expect(j['version'], 1);
      expect(j['port'], link.port);
      expect(j['pid'], 4242);
      expect(j['token'], link.token);
      expect(base64Url.decode(base64Url.normalize(j['token'] as String)).length, 32);
      final first = j['token'];
      await link.stop();
      expect(f.existsSync(), isFalse);

      f.writeAsStringSync('{"version":1,"port":1,"token":"old","pid":1}'); // left by a run that crashed
      await link.start();
      final again = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(again['token'], isNot(first)); // a new token every time
      expect(again['token'], isNot('old'));
      expect(again['port'], link.port);
      expect(File(p.join(tmp.path, 'voice-assistant', 'link.json.tmp')).existsSync(), isFalse);
    });

    test('a stopped link answers nothing and its old token is useless', () async {
      final port = link.port!;
      final token = link.token!;
      await link.stop();
      final client = HttpClient();
      await expectLater(() async {
        final req = await client.get('127.0.0.1', port, '/v1/status');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        await req.close();
      }(), throwsA(isA<SocketException>()));
      client.close(force: true);
    });
  });

  group('who may call it', () {
    test('a request without the token, or with a wrong one, is refused', () async {
      expect((await call('GET', '/v1/status', token: '')).$1, 401);
      expect((await call('GET', '/v1/status', token: 'wrong')).$1, 401);
      expect((await call('GET', '/v1/status', token: '${link.token}x')).$1, 401);
      expect((await call('POST', '/v1/entries', token: 'wrong', body: dose('a'))).$1, 401);
      expect(await db.ingestionsForPerson(me.id), isEmpty);
      expect((await call('GET', '/v1/status')).$1, 200);
    });

    test('it listens on loopback only', () async {
      expect(link.address!.isLoopback, isTrue);
      expect(link.address!.address, '127.0.0.1');
      final others = [
        for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
          for (final a in i.addresses)
            if (!a.isLoopback) a,
      ];
      for (final a in others) {
        await expectLater(Socket.connect(a, link.port!, timeout: const Duration(seconds: 2)), throwsA(isA<SocketException>()), reason: '$a');
      }
    });

    test('a body over 64 KB is refused, announced or not', () async {
      // Announced: refused from the headers, before any of it is read.
      final socket = await Socket.connect('127.0.0.1', link.port!);
      socket.write('POST /v1/entries HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${link.token}\r\nContent-Length: 70000\r\n\r\n');
      expect(await utf8.decodeStream(socket).timeout(const Duration(seconds: 5)), startsWith('HTTP/1.1 413'));
      socket.destroy();
      // Not announced (chunked): cut off as it arrives. The client may see the 413 or just the hang-up.
      final big = jsonEncode({...dose('big'), 'notes': 'x' * (70 * 1024)});
      final client = HttpClient();
      try {
        final req = await client.post('127.0.0.1', link.port!, '/v1/entries');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${link.token}');
        req.headers.chunkedTransferEncoding = true;
        req.write(big);
        final res = await req.close();
        expect(res.statusCode, 413);
      } on IOException {
        // Hung up on while still sending: also a refusal.
      } finally {
        client.close(force: true);
      }
      expect(await db.ingestionsForPerson(me.id), isEmpty);
    });

    test('a request that never sends its body times out', () async {
      await link.stop();
      link = makeLink(caps: const AssistantCaps(readTimeout: Duration(milliseconds: 300)));
      await link.start();
      final socket = await Socket.connect('127.0.0.1', link.port!);
      socket.write('POST /v1/entries HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${link.token}\r\nContent-Length: 50\r\n\r\n{');
      final reply = await utf8.decodeStream(socket).timeout(const Duration(seconds: 5));
      socket.destroy();
      expect(reply, contains('408'));
    });

    test('anything but JSON objects and the known endpoints is turned away', () async {
      expect((await call('POST', '/v1/entries', rawBody: '[1,2]')).$1, 400);
      expect((await call('POST', '/v1/entries', rawBody: 'not json')).$1, 400);
      expect((await call('GET', '/v1/everything')).$1, 404);
      expect((await call('DELETE', '/v1/entries')).$1, 405);
    });
  });

  group('adding', () {
    test('a dose goes in through the app\'s own database code, stamped as the assistant, and is seen by live queries', () async {
      final seen = <int>[];
      final sub = db.watchIngestionsForPerson(me.id).listen((rows) => seen.add(rows.length));
      final (status, reply) = await call('POST', '/v1/entries', body: dose('r1', minutesAgo: 5));
      expect(status, 200, reason: '$reply');
      expect(reply['duplicate'], false);
      expect(reply['experience_created'], true);
      final rows = await db.ingestionsForPerson(me.id);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect((r.substanceKey, r.route, r.dose, r.unit, r.notes), ('lsd', 'sublingual', 100.0, 'µg', 'blue tab'));
      expect(r.time, now().subtract(const Duration(minutes: 5)).copyWith(millisecond: 0, microsecond: 0));
      expect(r.hlc, endsWith('-mcp'));
      final details = jsonDecode(r.detailsJson) as Map<String, dynamic>;
      expect(details['source'], 'mcp');
      expect(details['addedBy'], 'voice assistant');
      expect(details['experienceCreated'], true);
      expect(details['requestId'], 'r1');
      final exp = await db.watchExperiences(me.id).first;
      expect(exp.single.id, r.experienceId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.last, 1);
      await sub.cancel();

      // A normal edit afterwards is stamped by this device again.
      await db.updateIngestion(r.id, notes: 'edited');
      final edited = (await db.ingestionsForPerson(me.id)).single;
      expect(edited.hlc, endsWith('-test-device'));
    });

    test('drinks are worked out by the app from the preset\'s volume and ABV, presets and notes too', () async {
      final (s1, drink) = await call('POST', '/v1/entries', body: {
        'request_id': 'd1',
        'kind': 'drink',
        'person': 'alex',
        'at': at(minutesAgo: 30),
        'drink': 'Beer - 12 oz 5%',
        'volume': 12,
        'volume_unit': 'oz',
        'abv': 5,
      });
      expect(s1, 200, reason: '$drink');
      final alex = (await db.activePeople()).firstWhere((x) => x.name == 'Alex');
      final row = (await db.ingestionsForPerson(alex.id)).single;
      expect(row.substanceKey, 'alcohol');
      expect(row.unit, 'g');
      expect(row.dose, closeTo(14.016, 0.001));
      expect((jsonDecode(row.detailsJson) as Map)['drink'], 'Beer - 12 oz 5%');

      final (s2, preset) = await call('POST', '/v1/entries', body: {...dose('p1'), 'kind': 'preset', 'preset': 'Usual tab', 'dose': 80});
      expect(s2, 200, reason: '$preset');
      expect(preset['summary'], startsWith('Usual tab: 80 µg of LSD'));

      final (s3, note) = await call('POST', '/v1/entries', body: {'request_id': 'n1', 'kind': 'note', 'at': at(minutesAgo: 1), 'text': 'feeling fine'});
      expect(s3, 200, reason: '$note');
      final notes = await db.watchTimedNotes(preset['experience_id'] as String).first;
      expect(notes.single.note, 'feeling fine');
      expect(notes.single.hlc, endsWith('-mcp'));
    });

    test('a note needs a session to go on', () async {
      final (status, reply) = await call('POST', '/v1/entries', body: {'request_id': 'n1', 'kind': 'note', 'at': at(), 'text': 'hello'});
      expect(status, 409);
      expect(reply['error'], contains('no session'));
    });

    test('future, too old, unknown and malformed entries are refused', () async {
      expect((await call('POST', '/v1/entries', body: dose('f', minutesAgo: -10))).$1, 422);
      expect((await call('POST', '/v1/entries', body: dose('o', minutesAgo: 24 * 60 + 1))).$1, 422);
      expect((await call('POST', '/v1/entries', body: dose('ok', minutesAgo: 24 * 60 - 1))).$1, 200);
      expect((await call('POST', '/v1/entries', body: {...dose('u'), 'substance': 'flarbnarb'})).$1, 400);
      expect((await call('POST', '/v1/entries', body: {...dose('z'), 'dose': 0})).$1, 400);
      expect((await call('POST', '/v1/entries', body: {...dose('k'), 'kind': 'delete'})).$1, 400);
      expect((await call('POST', '/v1/entries', body: {...dose('n'), 'person': 'Nobody'})).$1, 404);
      expect((await call('POST', '/v1/entries', body: {...dose('bad id!')})).$1, 400);
      expect((await call('POST', '/v1/entries', body: {...dose('a'), 'at': 'yesterday'})).$1, 400);
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
    });

    test('the hourly cap counts assistant entries in the journal', () async {
      await link.stop();
      link = makeLink(caps: const AssistantCaps(maxPerHour: 3));
      await link.start();
      for (var i = 0; i < 3; i++) {
        expect((await call('POST', '/v1/entries', body: dose('c$i'))).$1, 200);
      }
      final (status, reply) = await call('POST', '/v1/entries', body: dose('c3'));
      expect(status, 429);
      expect(reply['error'], contains('at most 3'));
      // An entry made by hand does not count.
      final e = await db.addExperience(personId: me.id, sortDate: now());
      await db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: now(), dose: 50, unit: 'µg');
      expect(await link.entriesLastHour(), 3);
      nowMs += const Duration(minutes: 61).inMilliseconds;
      expect((await call('POST', '/v1/entries', body: dose('c4'))).$1, 200);
    });

    test('the same request id is saved once, also by a later link', () async {
      final (_, a) = await call('POST', '/v1/entries', body: dose('same'));
      final (s, b) = await call('POST', '/v1/entries', body: dose('same'));
      expect(s, 200);
      expect(b['duplicate'], true);
      expect(b['id'], a['id']);
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
      await link.stop();
      await link.start();
      final (_, c) = await call('POST', '/v1/entries', body: dose('same'));
      expect(c['duplicate'], true);
      expect(c['id'], a['id']);
      expect(await db.ingestionsForPerson(me.id), hasLength(1));
    });

    test('each addition is announced for the on-screen message', () async {
      final got = <LinkAddition>[];
      final sub = link.additions.listen(got.add);
      await call('POST', '/v1/entries', body: dose('m1'));
      await Future<void>.delayed(Duration.zero);
      expect(got.single.summary, '100 µg of LSD, sublingual, for Me');
      expect(await link.undoFromApp(got.single), isTrue);
      expect(await db.ingestionsForPerson(me.id), isEmpty);
      expect(await db.watchExperiences(me.id).first, isEmpty); // the session it started went too
      await sub.cancel();
    });
  });

  group('undo', () {
    test('takes back only what this link added, recently, and unchanged', () async {
      final e = await db.addExperience(personId: me.id, sortDate: now().subtract(const Duration(days: 3)));
      final mine = await db.addIngestion(experience: e, substanceKey: 'mdma', route: 'oral', time: now().subtract(const Duration(days: 3)), dose: 80, unit: 'mg');
      final (_, a) = await call('POST', '/v1/entries', body: dose('u1'));
      final (_, b) = await call('POST', '/v1/entries', body: dose('u2'));
      final (_, c) = await call('POST', '/v1/entries', body: dose('u3'));
      await db.updateIngestion(b['id'] as String, notes: 'changed by hand');

      final (status, out) = await call('POST', '/v1/undo', body: {'ids': [a['id'], b['id'], mine.id, 'nope']});
      expect(status, 200);
      expect(out['removed'], [a['id']]);
      final reasons = {for (final s in out['skipped'] as List) s['id']: s['reason']};
      expect(reasons[b['id']], contains('changed in the app'));
      expect(reasons[mine.id], contains('not added through this link'));
      expect(reasons['nope'], contains('not added through this link'));

      final live = {for (final r in await db.ingestionsForPerson(me.id)) r.id};
      expect(live, {mine.id, b['id'], c['id']});
      final gone = await (db.select(db.ingestions)..where((t) => t.id.equals(a['id'] as String))).getSingle();
      expect(gone.deleted, isTrue);
      expect(gone.hlc, endsWith('-mcp'));

      // Never twice, and not after the window.
      expect(((await call('POST', '/v1/undo', body: {'ids': [a['id']]})).$2['removed'] as List), isEmpty);
      nowMs += const Duration(minutes: 11).inMilliseconds;
      final (_, late) = await call('POST', '/v1/undo', body: {'ids': [c['id']]});
      expect(late['removed'], isEmpty);
      expect((late['skipped'] as List).single['reason'], contains('more than 10 minutes'));
      expect((await call('POST', '/v1/undo', body: {'ids': 'all'})).$1, 400);
    });

    test('a session the link started goes when its last entry is undone; a session of yours never does', () async {
      final (_, a) = await call('POST', '/v1/entries', body: dose('s1'));
      await call('POST', '/v1/undo', body: {'ids': [a['id']]});
      expect(await db.watchExperiences(me.id).first, isEmpty);

      final e = await db.addExperience(personId: me.id, sortDate: now());
      await db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: now().subtract(const Duration(minutes: 30)), dose: 50, unit: 'µg');
      final (_, b) = await call('POST', '/v1/entries', body: dose('s2'));
      expect(b['experience_id'], e.id);
      await call('POST', '/v1/undo', body: {'ids': [b['id']]});
      expect((await db.watchExperiences(me.id).first).single.id, e.id);
    });
  });

  group('reading', () {
    test('status gives the app version, people, presets and caps, and nothing else', () async {
      final (status, s) = await call('GET', '/v1/status');
      expect(status, 200);
      expect(s.keys.toSet(), {'app', 'version', 'link_version', 'pid', 'people', 'presets', 'caps', 'entries_last_hour'});
      expect(s['version'], appVersionName);
      expect(s['pid'], 4242);
      expect(s['people'], [
        {'name': 'Me', 'default': true},
        {'name': 'Alex', 'default': false},
      ]);
      final presets = s['presets'] as Map<String, dynamic>;
      expect((presets['dose'] as List).single, {'name': 'Usual tab', 'substance': 'lsd', 'substance_name': 'LSD', 'route': 'sublingual', 'amount': 80.0, 'unit': 'µg'});
      expect((presets['drink'] as List).map((d) => d['name']), contains('Beer - 12 oz 5%'));
      expect((presets['drink'] as List).firstWhere((d) => d['name'] == 'Beer - 12 oz 5%'), {'name': 'Beer - 12 oz 5%', 'volume': 12.0, 'unit': 'oz', 'abv': 5.0});
      expect(s['caps'], {
        'max_backdate_hours': 24.0,
        'max_entries_per_hour': 12,
        'undo_window_minutes': 10,
        'max_note_chars': 500,
        'max_body_bytes': 65536,
        'max_recent': 20,
        'future_allowed': false,
      });
      expect(s['entries_last_hour'], 0);
    });

    test('the version shown matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^version: ([0-9.]+)', multiLine: true).firstMatch(pubspec)!.group(1), appVersionName);
    });

    test('recent and active are short, and marked where the assistant added them', () async {
      final e = await db.addExperience(personId: me.id, sortDate: now());
      await db.addIngestion(experience: e, substanceKey: 'lsd', route: 'sublingual', time: now().subtract(const Duration(hours: 2)), dose: 100, unit: 'µg');
      await call('POST', '/v1/entries', body: {
        'request_id': 'd1', 'kind': 'drink', 'at': at(minutesAgo: 30), 'drink': 'Beer - 12 oz 5%', 'volume': 12, 'volume_unit': 'oz', 'abv': 5,
      });
      await call('POST', '/v1/entries', body: {'request_id': 'n1', 'kind': 'note', 'at': at(minutesAgo: 10), 'text': 'peaking'});

      final (s1, recent) = await call('GET', '/v1/recent?limit=2');
      expect(s1, 200);
      final items = recent['items'] as List;
      expect(items, hasLength(2));
      expect(items[0]['kind'], 'note');
      expect(items[0]['note'], 'peaking');
      expect(items[0]['by_assistant'], true);
      expect(items[1]['kind'], 'drink');
      expect(items[1]['standard_drinks'], closeTo(1.0, 0.01));
      final (_, all) = await call('GET', '/v1/recent?limit=500');
      expect((all['items'] as List).length, 3); // capped at 20, and there are 3
      expect(((all['items'] as List).last as Map)['by_assistant'], false);

      final (s2, active) = await call('GET', '/v1/active');
      expect(s2, 200);
      final sub = (active['substances'] as List).single as Map<String, dynamic>;
      expect(sub['substance'], 'lsd');
      expect(sub['name'], 'LSD');
      expect(sub['phase_label'], isNotEmpty);
      expect(sub['last_at'], now().subtract(const Duration(hours: 2)).toIso8601String().split('.').first);
      final alc = active['alcohol'] as Map<String, dynamic>;
      expect(alc['standard_drinks_today'], closeTo(1.0, 0.01));
      expect((alc['drinks_last_24h'] as List), hasLength(1));
      expect((await call('GET', '/v1/active?person=Alex')).$2['substances'], isEmpty);
    });
  });
}
