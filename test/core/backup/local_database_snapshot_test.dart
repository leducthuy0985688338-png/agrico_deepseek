import 'dart:convert';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('snapshot includes rows and preserves Lao Unicode across validation',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('CREATE TABLE sample (id TEXT PRIMARY KEY, name TEXT)');
      await db.insert('sample', {'id': 'parcel-1', 'name': 'ບ້ານຕາໂກ'});
      final bytes = await LocalDatabaseSnapshot.create(db);
      expect(LocalDatabaseSnapshot.inspect(bytes)['sample'], 1);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(root['format'], LocalDatabaseSnapshot.format);
      expect(root['payload'], contains('ບ້ານຕາໂກ'));
      expect((await db.query('sample')).single['name'], 'ບ້ານຕາໂກ');
    } finally {
      await db.close();
    }
  });

  test('altered and incompatible snapshots fail before any restore', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('CREATE TABLE sample (id TEXT PRIMARY KEY)');
      final bytes = await LocalDatabaseSnapshot.create(db);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      root['payload'] = (root['payload'] as String).replaceFirst('sample', 'tamper');
      expect(() => LocalDatabaseSnapshot.inspect(
          Uint8List.fromList(utf8.encode(jsonEncode(root)))), throwsFormatException);
      root['version'] = 999;
      expect(() => LocalDatabaseSnapshot.inspect(
          Uint8List.fromList(utf8.encode(jsonEncode(root)))), throwsFormatException);
    } finally {
      await db.close();
    }
  });
}
