import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sj_core/sj_core.dart';

import 'database.dart';

/// Syncing journals between devices.
///
/// Every row carries the hybrid-logical-clock stamp of its last edit and a tombstone flag, so
/// two devices can exchange "everything changed since X" and settle every row the same way:
/// the later stamp wins, deletes included. Nothing here needs a connection. A package is text
/// (encrypted, see sj_core's sync_package.dart) that can travel as a file, through any messenger,
/// or as QR frames.
class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApplyResult {
  const ApplyResult({required this.applied, required this.skipped, required this.peerName, required this.peerId});
  final int applied;

  /// Rows already up to date here, or older than what this device has.
  final int skipped;
  final String peerName;
  final String peerId;
}

/// A device this one has paired with.
class SyncPeer {
  const SyncPeer({required this.deviceId, required this.name, required this.pending, required this.pairedAt, this.lastSync});
  final String deviceId;
  final String name;

  /// A pairing code was shown but no package has come back from the other device yet.
  final bool pending;
  final DateTime pairedAt;
  final DateTime? lastSync;
}

const _pendingPrefix = 'pending:';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List _unb64(String text) => Uint8List.fromList(base64Url.decode(text.padRight((text.length + 3) ~/ 4 * 4, '=')));

class SyncService {
  SyncService(this.db, {required this.deviceName, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AppDatabase db;
  final String deviceName;
  final DateTime Function() _now;

  // Parents before children, so a row never refers to one that has not arrived.
  late final List<_SyncTable> _tables = [
    _SyncTable<$PeopleTable, Person>(db.people, Person.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$ExperiencesTable, Experience>(db.experiences, Experience.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$CustomSubstancesTable, CustomSubstance>(db.customSubstances, CustomSubstance.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$CustomUnitsTable, CustomUnit>(db.customUnits, CustomUnit.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$ProductsTable, Product>(db.products, Product.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$IngestionsTable, Ingestion>(db.ingestions, Ingestion.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$TimedNotesTable, TimedNote>(db.timedNotes, TimedNote.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$RatingsTable, Rating>(db.ratings, Rating.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$PresetsTable, Preset>(db.presets, Preset.fromJson, (r) => r.hlc, (r) => r.toJson()),
    _SyncTable<$RecipesTable, RecipeRow>(db.recipes, RecipeRow.fromJson, (r) => r.hlc, (r) => r.toJson()),
  ];

  // ---- pairing ----

  /// A code for another device to scan or type. Offering it again reuses the same key until a
  /// device claims it, so a QR already shown keeps working.
  Future<PairingCode> offerPairing() async {
    final pending = await (db.select(db.peers)..where((t) => t.deviceId.like('$_pendingPrefix%'))).get();
    final Uint8List key;
    if (pending.isNotEmpty) {
      key = _unb64(pending.first.sharedKey);
    } else {
      key = generateSyncKey();
      await db.into(db.peers).insert(PeersCompanion.insert(
            deviceId: '$_pendingPrefix${_b64(key.sublist(0, 6))}',
            name: 'Waiting for a device',
            // Databases created before v3 have this column as NOT NULL with no default.
            publicKey: const Value(''),
            pairedAt: _now(),
            sharedKey: Value(_b64(key)),
          ));
    }
    return PairingCode(deviceId: db.deviceId, deviceName: deviceName, key: key);
  }

  /// Adopts a code shown by another device. Returns the peer's name.
  Future<String> acceptPairing(String text) async {
    final code = PairingCode.decode(text);
    if (code == null) throw const SyncException('That is not a Substance Journal pairing code.');
    if (code.deviceId == db.deviceId) throw const SyncException('That code is from this device.');
    await db.into(db.peers).insertOnConflictUpdate(PeersCompanion.insert(
          deviceId: code.deviceId,
          name: code.deviceName,
          publicKey: const Value(''),
          pairedAt: _now(),
          sharedKey: Value(_b64(code.key)),
        ));
    return code.deviceName;
  }

  Future<List<SyncPeer>> peers() async {
    final rows = await (db.select(db.peers)..orderBy([(t) => OrderingTerm.asc(t.pairedAt)])).get();
    final result = <SyncPeer>[];
    for (final p in rows) {
      final last = await db.getSetting('syncLast:${p.deviceId}');
      result.add(SyncPeer(
        deviceId: p.deviceId,
        name: p.name,
        pending: p.deviceId.startsWith(_pendingPrefix),
        pairedAt: p.pairedAt,
        lastSync: last == null ? null : DateTime.tryParse(last),
      ));
    }
    return result;
  }

  Future<void> forgetPeer(String deviceId) async {
    await (db.delete(db.peers)..where((t) => t.deviceId.equals(deviceId))).go();
  }

  // ---- building and applying changes ----

  /// Everything changed after [since] (a clock stamp), or everything when null.
  Future<Map<String, Object?>> buildChangeset({String? since}) async {
    final tables = <String, Object?>{};
    var count = 0;
    for (final t in _tables) {
      final rows = await t.changedSince(db, since);
      if (rows.isNotEmpty) tables[t.name] = rows;
      count += rows.length;
    }
    final sharedSettings = await (db.select(db.settings)
          ..where((s) => s.shared.equals(true) & (since == null ? const Constant(true) : s.hlc.isBiggerThanValue(since))))
        .get();
    if (sharedSettings.isNotEmpty) tables['settings'] = [for (final s in sharedSettings) s.toJson()];
    return {'tables': tables, 'rowCount': count + sharedSettings.length};
  }

  /// A sealed package for [peerId]: only what they do not have yet, unless [everything].
  Future<String> createPackage(String peerId, {bool everything = false}) async {
    final peer = await (db.select(db.peers)..where((t) => t.deviceId.equals(peerId))).getSingleOrNull();
    if (peer == null) throw const SyncException('Pair with that device first.');
    // A pairing nobody has claimed yet has no history: the first package carries everything.
    final since = everything || peer.deviceId.startsWith(_pendingPrefix) ? null : await db.getSetting('syncPeerHave:$peerId');
    final changes = await buildChangeset(since: since);
    final body = {
      'v': 1,
      'from': db.deviceId,
      'fromName': deviceName,
      'created': _now().toIso8601String(),
      // What this device already has from the receiver, so their reply is a true delta.
      'have': peer.lastSyncedHlc.isEmpty ? null : peer.lastSyncedHlc,
      ...changes,
    };
    return sealSyncPackage(senderId: db.deviceId, key: _unb64(peer.sharedKey), plain: utf8.encode(jsonEncode(body)));
  }

  /// Rows a package for [peerId] would carry right now, for showing "N changes" before sending.
  Future<int> pendingChangeCount(String peerId) async {
    final since = await db.getSetting('syncPeerHave:$peerId');
    return (await buildChangeset(since: since))['rowCount'] as int;
  }

  /// Opens a package from any paired device and merges it. All or nothing.
  Future<ApplyResult> receivePackage(String text) async {
    final sender = senderOfPackage(text);
    if (sender == null) throw const SyncException('This is not a Substance Journal sync package.');
    if (sender == db.deviceId) throw const SyncException('This package was made by this device.');

    final known = await (db.select(db.peers)..where((t) => t.deviceId.equals(sender))).getSingleOrNull();
    final candidates = <Peer>[
      ?known,
      if (known == null) ...await (db.select(db.peers)..where((t) => t.deviceId.like('$_pendingPrefix%'))).get(),
    ];
    if (candidates.isEmpty) throw const SyncException('This package is from a device you have not paired with. Pair first.');

    Uint8List? plain;
    Peer? used;
    for (final c in candidates) {
      try {
        plain = await openSyncPackage(text, _unb64(c.sharedKey));
        used = c;
        break;
      } on SyncCryptoException {
        continue;
      }
    }
    if (plain == null || used == null) {
      throw const SyncException('Could not open this package. It may be damaged, or from a device paired with a different code.');
    }
    final usedKey = used.sharedKey;
    final usedId = used.deviceId;
    final body = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final peerName = body['fromName'] as String? ?? 'Another device';

    return db.transaction(() async {
      // A pending pairing becomes a real peer now that the other device has answered.
      if (usedId.startsWith(_pendingPrefix)) {
        await (db.delete(db.peers)..where((t) => t.deviceId.equals(usedId))).go();
        await db.into(db.peers).insertOnConflictUpdate(PeersCompanion.insert(
              deviceId: sender,
              name: peerName,
              publicKey: const Value(''),
              pairedAt: _now(),
              sharedKey: Value(usedKey),
            ));
      } else if (known != null && known.name != peerName) {
        await (db.update(db.peers)..where((t) => t.deviceId.equals(sender))).write(PeersCompanion(name: Value(peerName)));
      }

      final merged = await _mergeTables({...?(body['tables'] as Map<String, dynamic>?)});
      final applied = merged.applied;
      final skipped = merged.skipped;
      final maxHlc = merged.maxHlc;

      // Remember how far we have seen this device, and how far it says it has seen us.
      final peer = await (db.select(db.peers)..where((t) => t.deviceId.equals(sender))).getSingle();
      if (maxHlc.compareTo(peer.lastSyncedHlc) > 0) {
        await (db.update(db.peers)..where((t) => t.deviceId.equals(sender))).write(PeersCompanion(lastSyncedHlc: Value(maxHlc)));
      }
      final have = body['have'];
      if (have is String && have.isNotEmpty) await db.setSetting('syncPeerHave:$sender', have);
      await db.setSetting('syncLast:$sender', _now().toIso8601String());
      return ApplyResult(applied: applied, skipped: skipped, peerName: peerName, peerId: sender);
    });
  }

  /// Merges the rows of a restored backup. Same rules as sync, with no peer involved.
  Future<ApplyResult> mergeBackup(Map<String, dynamic> body) async {
    final merged = await db.transaction(() => _mergeTables({...?(body['tables'] as Map<String, dynamic>?)}));
    return ApplyResult(applied: merged.applied, skipped: merged.skipped, peerName: 'the backup', peerId: '');
  }

  /// Folds a set of incoming rows into this database. Run inside a transaction.
  Future<_TableResult> _mergeTables(Map<String, dynamic> tables) async {
    var applied = 0;
    var skipped = 0;
    var maxHlc = '';
    final aliases = await _personAliases((tables['people'] as List?)?.cast<Map<String, dynamic>>() ?? const []);
    if (aliases.isNotEmpty) _applyAliases(tables, aliases);
    for (final t in _tables) {
      final rows = (tables[t.name] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final result = await t.apply(db, rows);
      applied += result.applied;
      skipped += result.skipped;
      if (result.maxHlc.compareTo(maxHlc) > 0) maxHlc = result.maxHlc;
    }
    final settingRows = (tables['settings'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final json in settingRows) {
      final row = Setting.fromJson(json);
      if (!row.shared) continue;
      if (row.hlc.compareTo(maxHlc) > 0) maxHlc = row.hlc;
      final local = await (db.select(db.settings)..where((s) => s.key.equals(row.key))).getSingleOrNull();
      if (local == null || _newer(row.hlc, local.hlc)) {
        await db.into(db.settings).insertOnConflictUpdate(row);
        applied++;
      } else {
        skipped++;
      }
    }
    if (maxHlc.isNotEmpty) {
      try {
        db.observeHlc(maxHlc);
      } on StateError {
        // A clock far in the future is ignored rather than dragging this device's clock forward.
      }
    }
    return _TableResult(applied, skipped, maxHlc);
  }

  /// Incoming people who are already here under another id. Each device creates its own "Me" on
  /// first run, and the same person may have been added by name on both, so without this a sync
  /// would leave two of everyone. The default person matches the default person; others match by name.
  Future<Map<String, String>> _personAliases(List<Map<String, dynamic>> incoming) async {
    if (incoming.isEmpty) return const {};
    final local = await db.select(db.people).get();
    final localIds = {for (final p in local) p.id};
    final live = [for (final p in local) if (!p.deleted) p]..sort((a, b) => a.id.compareTo(b.id));
    final aliases = <String, String>{};
    for (final json in incoming) {
      final id = json['id'] as String;
      if (localIds.contains(id)) continue;
      Person? match;
      if (json['isDefault'] == true) match = live.where((p) => p.isDefault).firstOrNull;
      match ??= live.where((p) => p.name.toLowerCase() == (json['name'] as String).toLowerCase()).firstOrNull;
      if (match != null) aliases[id] = match.id;
    }
    return aliases;
  }

  /// Points incoming rows at the local person instead of the one they were made under.
  void _applyAliases(Map<String, dynamic> tables, Map<String, String> aliases) {
    tables['people'] = [
      for (final p in (tables['people'] as List).cast<Map<String, dynamic>>())
        if (!aliases.containsKey(p['id'])) p,
    ];
    for (final table in const ['experiences', 'ingestions']) {
      final rows = (tables[table] as List?)?.cast<Map<String, dynamic>>();
      if (rows == null) continue;
      tables[table] = [
        for (final r in rows) {...r, 'personId': aliases[r['personId']] ?? r['personId']},
      ];
    }
    final settingRows = (tables['settings'] as List?)?.cast<Map<String, dynamic>>();
    if (settingRows != null) {
      tables['settings'] = [
        for (final s in settingRows)
          {
            ...s,
            'key': aliases.entries.fold<String>(s['key'] as String, (key, a) => key.endsWith(':${a.key}') ? key.replaceFirst(':${a.key}', ':${a.value}') : key),
          },
      ];
    }
  }
}

bool _newer(String incoming, String local) {
  try {
    return Hlc.parse(incoming) > Hlc.parse(local);
  } on FormatException {
    return incoming.compareTo(local) > 0;
  }
}

class _TableResult {
  const _TableResult(this.applied, this.skipped, this.maxHlc);
  final int applied;
  final int skipped;
  final String maxHlc;
}

/// One synced table: reading rows changed after a stamp, and merging incoming rows.
class _SyncTable<T extends Table, D extends DataClass> {
  _SyncTable(this.table, this._fromJson, this._hlcOf, this._toJson);

  final TableInfo<T, D> table;
  final D Function(Map<String, dynamic>) _fromJson;
  final String Function(D) _hlcOf;
  final Map<String, dynamic> Function(D) _toJson;

  String get name => table.actualTableName;

  Future<List<Map<String, dynamic>>> changedSince(GeneratedDatabase db, String? since) async {
    final result = await db
        .customSelect(
          since == null ? 'SELECT * FROM $name' : 'SELECT * FROM $name WHERE hlc > ?',
          variables: [if (since != null) Variable<String>(since)],
        )
        .get();
    return [for (final r in result) _toJson(await table.map(r.data))];
  }

  /// Takes each incoming row whose stamp is later than the local row's (or that is new here).
  Future<_TableResult> apply(AppDatabase db, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const _TableResult(0, 0, '');
    final local = {
      for (final r in await db.customSelect('SELECT id, hlc FROM $name').get()) r.data['id'] as String: r.data['hlc'] as String,
    };
    var applied = 0;
    var skipped = 0;
    var maxHlc = '';
    for (final json in rows) {
      final row = _fromJson(json);
      final hlc = _hlcOf(row);
      if (hlc.compareTo(maxHlc) > 0) maxHlc = hlc;
      final id = json['id'] as String;
      final existing = local[id];
      if (existing == null || _newer(hlc, existing)) {
        await db.into(table).insertOnConflictUpdate(row as Insertable<D>);
        applied++;
      } else {
        skipped++;
      }
    }
    return _TableResult(applied, skipped, maxHlc);
  }
}
