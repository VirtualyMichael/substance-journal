import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:substance_journal_app/data/db_security.dart';

class _Vault implements KeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String hex) async => value = hex;
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sj-sec');
    file = File('${dir.path}/journal.sqlite');
    final raw = sql.sqlite3.open(file.path)
      ..execute('PRAGMA user_version = 7')
      ..execute('CREATE TABLE t (v TEXT)')
      ..execute("INSERT INTO t VALUES ('private entry')");
    raw.close();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a plain journal is encrypted in place, keeps its data and needs the key', () async {
    final key = newKeyHex();
    expect(isPlainSqlite(file), isTrue);
    expect(await encryptInPlace(file, key), isTrue);
    expect(isPlainSqlite(file), isFalse);
    expect(file.readAsBytesSync().length, greaterThan(0));
    expect(String.fromCharCodes(file.readAsBytesSync()).contains('private entry'), isFalse);
    expect(File('${file.path}.pre-encrypt').existsSync(), isFalse); // the plain copy is wiped

    final good = sql.sqlite3.open(file.path)..execute("PRAGMA hexkey = '$key'");
    expect(good.select('SELECT v FROM t').first['v'], 'private entry');
    expect(good.select('PRAGMA user_version').first.values.first, 7);
    good.close();

    final wrong = sql.sqlite3.open(file.path);
    expect(() => applyKey(wrong, newKeyHex()), throwsA(isA<sql.SqliteException>()));
    wrong.close();
    final none = sql.sqlite3.open(file.path);
    expect(() => none.select('SELECT * FROM t'), throwsA(isA<sql.SqliteException>()));
    none.close();

    expect(await encryptInPlace(file, key), isFalse); // already done
  });

  test('a key is made once, reused, and never replaced for an encrypted journal', () async {
    final vault = _Vault();
    final first = await loadOrCreateKey(vault, file);
    expect(first, hasLength(64));
    expect(await loadOrCreateKey(vault, file), first);
    await encryptInPlace(file, first);
    vault.value = null; // the key is lost
    await expectLater(loadOrCreateKey(vault, file), throwsA(isA<KeyUnavailable>()));
  });

  test('wipe overwrites and removes a file', () {
    final f = File('${dir.path}/x')..writeAsStringSync('secret');
    wipe(f);
    expect(f.existsSync(), isFalse);
  });
}
