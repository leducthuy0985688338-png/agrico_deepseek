import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_media_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<({Directory directory, Database primary, Database costs})>
      createPair() async {
    final directory = await Directory.systemTemp.createTemp('agrico-apply-');
    final primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    final costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    await primary.execute('CREATE TABLE parcels (id TEXT PRIMARY KEY)');
    await costs.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY)');
    await primary.insert('parcels', {'id': 'backup'});
    await costs.insert('expenses', {'id': 'backup'});
    return (directory: directory, primary: primary, costs: costs);
  }

  test('restore orders real parcel parents and children and preserves triggers', () async {
    final pair = await createPair();
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      await SqliteLandParcelRepository.createSchema(pair.primary);
      Future<void> insert(String id, String kind, String? parent) =>
          pair.primary.insert('land_parcels', {
            'id': id, 'farm_id': 'local-farm', 'parcel_code': id,
            'active': 1, 'boundary_version': 1, 'schema_version': 3,
            'payload_json': '{}', 'kind': kind, 'parent_block_id': parent,
          }).then((_) {});
      await insert('z-block', 'landBlock', null);
      await insert('a-child', 'fieldPlot', 'z-block');
      await insert('standalone', 'fieldPlot', null);
      final snapshot = await LocalDatabaseSnapshot.create(pair.primary,
        costsDatabase: pair.costs);
      // Force child-first backup order, independent of SQLite query order.
      final databases = LocalDatabaseSnapshot.decodeDatabases(snapshot);
      final tables = databases['agrico.db']!['tables'] as Map<String, dynamic>;
      final rows = tables['land_parcels'] as List;
      rows.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final body = jsonEncode({'databases': databases});
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
        'format': LocalDatabaseSnapshot.format, 'version': 2,
        'sha256': sha256.convert(utf8.encode(body)).toString(), 'payload': body,
      })));
      final triggersBefore = await pair.primary.rawQuery(
        "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name",
      );
      await insert('extra-child', 'fieldPlot', 'z-block');
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      final db = await databaseFactoryFfi.openDatabase('${pair.directory.path}/agrico.db');
      try {
        expect((await db.query('land_parcels')).map((r) => r['id']),
            unorderedEquals(['z-block', 'a-child', 'standalone']));
        expect(await db.rawQuery(
          "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name",
        ), triggersBefore);
        await expectLater(db.delete('land_parcels', where: 'id=?', whereArgs: ['z-block']),
            throwsA(isA<Exception>()));
        await expectLater(db.insert('land_parcels', {
          'id': 'orphan', 'farm_id': 'local-farm', 'parcel_code': 'orphan',
          'active': 1, 'boundary_version': 1, 'schema_version': 3,
          'payload_json': '{}', 'kind': 'fieldPlot', 'parent_block_id': 'missing',
        }), throwsA(isA<Exception>()));
      } finally { await db.close(); }
    } finally {
      if (pair.primary.isOpen) await pair.primary.close();
      if (pair.costs.isOpen) await pair.costs.close();
      await pair.directory.delete(recursive: true);
    }
  });

  test('replaces both databases at startup and saves previous state', () async {
    final pair = await createPair();
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      final bytes = await LocalDatabaseSnapshot.create(pair.primary,
        costsDatabase: pair.costs);
      await pair.primary.delete('parcels');
      await pair.costs.delete('expenses');
      await pair.primary.insert('parcels', {'id': 'current'});
      await pair.costs.insert('expenses', {'id': 'current'});
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      final primary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final costs = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      late final Uint8List previousBytes;
      try {
        expect((await primary.query('parcels')).single['id'], 'backup');
        expect((await costs.query('expenses')).single['id'], 'backup');
        final previous = pair.directory.listSync().whereType<File>().singleWhere(
          (file) => file.path.contains('agrico-before-restore-'));
        previousBytes = Uint8List.fromList(await previous.readAsBytes());
        expect(LocalDatabaseSnapshot.inspect(previousBytes), {
          'agrico.db/parcels': 1,
          'agrico_costs.db/expenses': 1,
        });
        final oldData = LocalDatabaseSnapshot.decodeDatabases(
          previousBytes);
        expect((oldData['agrico.db']!['tables'] as Map<String, dynamic>)
          ['parcels'][0]['id'], 'current');
        expect(await activation.previousBackup(), isNotNull);
        expect(await activation.applyPending(), isFalse);
      } finally {
        await primary.close();
        await costs.close();
      }
      await activation.schedule(previousBytes);
      expect(await activation.applyPending(), isTrue);
      final restoredPrimary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final restoredCosts = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      try {
        expect((await restoredPrimary.query('parcels')).single['id'], 'current');
        expect((await restoredCosts.query('expenses')).single['id'], 'current');
      } finally {
        await restoredPrimary.close();
        await restoredCosts.close();
      }
    } finally {
      await pair.directory.delete(recursive: true);
    }
  });

  test('failed costs insert rolls back the primary database too', () async {
    final pair = await createPair();
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      final bytes = await LocalDatabaseSnapshot.create(pair.primary,
        costsDatabase: pair.costs);
      await pair.primary.delete('parcels');
      await pair.costs.delete('expenses');
      await pair.primary.insert('parcels', {'id': 'current'});
      await pair.costs.insert('expenses', {'id': 'current'});
      await pair.costs.execute('''CREATE TRIGGER reject_backup
        BEFORE INSERT ON expenses WHEN NEW.id = 'backup'
        BEGIN SELECT RAISE(ABORT, 'blocked'); END''');
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(bytes);
      await expectLater(activation.applyPending(), throwsA(isA<Exception>()));
      final result = jsonDecode(await File(
        '${pair.directory.path}/agrico-restore-result.json',
      ).readAsString()) as Map<String, dynamic>;
      expect(result['status'], 'failed');
      expect(result['step'], 'agrico_costs.db.insert.expenses');
      expect(result['diagnostic'], isA<String>());
      expect(result['diagnostic'].toString(), isNot(contains('INSERT INTO')));
      final primary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final costs = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      try {
        expect((await primary.query('parcels')).single['id'], 'current');
        expect((await costs.query('expenses')).single['id'], 'current');
      } finally {
        await primary.close();
        await costs.close();
      }
    } finally {
      await pair.directory.delete(recursive: true);
    }
  });

  test('applies media backup with a portable photo path', () async {
    final pair = await createPair();
    final source = await Directory.systemTemp.createTemp('agrico-photo-');
    final photo = File('${source.path}/plot.jpg')
      ..writeAsBytesSync([10, 20, 30]);
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      await pair.primary.execute('CREATE TABLE fields '
          '(id TEXT PRIMARY KEY, photo_paths TEXT NOT NULL)');
      await pair.primary.insert('fields', {
        'id': 'plot', 'photo_paths': jsonEncode([photo.path]),
      });
      final backup = await LocalMediaSnapshot.create(pair.primary, pair.costs);
      // Simulate restoring on another device: the original file is gone.
      await photo.delete();
      await pair.primary.delete('fields');
      await pair.primary.insert('fields', {
        'id': 'plot', 'photo_paths': '[]',
      });
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(backup);
      expect(await activation.applyPending(), isTrue);
      final restored = await databaseFactoryFfi.openDatabase(
          '${pair.directory.path}/agrico.db');
      try {
        final paths = jsonDecode((await restored.query('fields')).single
            ['photo_paths'] as String) as List;
        final path = paths.single as String;
        expect(path, startsWith(pair.directory.path));
        expect(await File(path).readAsBytes(), [10, 20, 30]);
      } finally {
        await restored.close();
      }
    } finally {
      await source.delete(recursive: true);
      await pair.directory.delete(recursive: true);
    }
  });
  test(
    'restoring an accepted pre-warehouse empty snapshot clears newer warehouse configuration',
    () async {
      final pair = await createPair();
      final activation = LocalRestoreActivation(
        pair.directory,
        databaseFactoryFfi,
      );
      try {
        await SqliteInventoryRepository.createSchema(pair.primary);
        final source = await LocalDatabaseSnapshot.create(
          pair.primary,
          costsDatabase: pair.costs,
        );
        final databases = LocalDatabaseSnapshot.decodeDatabases(source);
        final tables = databases['agrico.db']!['tables'] as Map;
        for (final table in [
          'inventory_warehouses_v1',
          'inventory_warehouse_sequences_v1',
          'inventory_warehouse_stock_v1',
          'inventory_transfers_v1',
        ]) {
          tables.remove(table);
        }
        final body = jsonEncode({'databases': databases});
        final backup = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': LocalDatabaseSnapshot.format,
              'version': 2,
              'sha256': sha256.convert(utf8.encode(body)).toString(),
              'payload': body,
            }),
          ),
        );
        await SqliteInventoryRepository(
          pair.primary,
        ).createWarehouse('f', 'newer', 'Newer warehouse', 'admin');
        await pair.primary.close();
        await pair.costs.close();
        await activation.schedule(backup);
        expect(await activation.applyPending(), isTrue);
        final restored = await databaseFactoryFfi.openDatabase(
          '${pair.directory.path}/agrico.db',
        );
        try {
          expect(await restored.query('inventory_warehouses_v1'), isEmpty);
          expect(
            await restored.query('inventory_warehouse_sequences_v1'),
            isEmpty,
          );
        } finally {
          await restored.close();
        }
      } finally {
        if (pair.primary.isOpen) await pair.primary.close();
        if (pair.costs.isOpen) await pair.costs.close();
        await pair.directory.delete(recursive: true);
      }
    },
  );
}
