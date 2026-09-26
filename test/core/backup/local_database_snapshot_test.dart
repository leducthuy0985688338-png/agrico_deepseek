import 'dart:convert';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:crypto/crypto.dart';
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
      expect(LocalDatabaseSnapshot.inspect(bytes)['agrico.db/sample'], 1);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(root['format'], LocalDatabaseSnapshot.format);
      expect(root['payload'], contains('ບ້ານຕາໂກ'));
      expect((await db.query('sample')).single['name'], 'ບ້ານຕາໂກ');
    } finally {
      await db.close();
    }
  });

  test('snapshot includes costs in a second database', () async {
    final primary = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final costs = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await primary.execute('CREATE TABLE parcels (id TEXT PRIMARY KEY)');
      await costs.execute('CREATE TABLE production_costs (id TEXT PRIMARY KEY)');
      await primary.insert('parcels', {'id': 'parcel-1'});
      await costs.insert('production_costs', {'id': 'cost-1'});
      final bytes = await LocalDatabaseSnapshot.create(
        primary, costsDatabase: costs,
      );
      expect(LocalDatabaseSnapshot.inspect(bytes), {
        'agrico.db/parcels': 1,
        'agrico_costs.db/production_costs': 1,
      });
    } finally {
      await primary.close();
      await costs.close();
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

  test('inspects older primary-only backup without claiming cost data', () {
    final body = jsonEncode({
      'databaseVersion': 8,
      'tables': {'parcels': [{'id': 'parcel-1'}]},
    });
    final legacy = utf8.encode(jsonEncode({
      'format': LocalDatabaseSnapshot.format,
      'version': 1,
      'sha256': sha256.convert(utf8.encode(body)).toString(),
      'payload': body,
    }));
    expect(LocalDatabaseSnapshot.inspect(Uint8List.fromList(legacy)), {
      'agrico.db/parcels': 1,
    });
  });
}
