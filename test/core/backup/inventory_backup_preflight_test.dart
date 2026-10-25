import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database primary;
  late Database costs;
  late SqliteInventoryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'agrico-inventory-backup-',
    );
    primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    await costs.execute('CREATE TABLE production_costs (id TEXT PRIMARY KEY)');
    await SqliteInventoryRepository.createSchema(primary);
    repository = SqliteInventoryRepository(primary);
    await repository.register(
      const InventoryItem(
        id: 'item-1',
        farmId: 'farm-1',
        code: 'PB001',
        name: 'ຝຸ່ນ · Phân bón',
        unit: 'kg',
        unitPrice: 100,
        supplier: '',
      ),
    );
    for (final entry in [
      (InventoryMovementKind.receipt, 5),
      (InventoryMovementKind.issue, 2),
    ].indexed) {
      await repository.record(
        InventoryMovement(
          id: 'movement-${entry.$1}',
          farmId: 'farm-1',
          itemId: 'item-1',
          kind: entry.$2.$1,
          quantity: entry.$2.$2,
          occurredAt: DateTime.utc(2026, 9, 30, entry.$1),
        ),
      );
    }
  });

  tearDown(() async {
    await primary.close();
    await costs.close();
    await directory.delete(recursive: true);
  });

  Future<Uint8List> snapshot() =>
      LocalDatabaseSnapshot.create(primary, costsDatabase: costs);

  Future<Map<String, int>> validate(Uint8List bytes) =>
      LocalRestorePreflight.validate(
        bytes: bytes,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );

  Future<void> unchanged() async {
    expect((await repository.listByFarm('farm-1')).single.stock, 3);
    expect((await repository.movementsByFarm('farm-1')).length, 2);
    final files = await directory.list().toList();
    expect(
      files.where((file) => file.path.contains('agrico-restore-')),
      isEmpty,
    );
  }

  test('native V2 seasons and cost snapshots survive backup preflight', () async {
    await primary.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY, farm_id TEXT, parcel_code TEXT, active INTEGER, kind TEXT)',
    );
    await primary.insert('land_parcels', {
      'id': 'p',
      'farm_id': 'farm-1',
      'parcel_code': 'P1',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await repository.createProductionSeason(
      const ProductionSeason(
        id: 's',
        farmId: 'farm-1',
        parcelId: 'p',
        name: 'Season',
        startsOn: '2026-09-01',
      ),
    );
    await repository.recordProductionIssue(
      InventoryMovement(
        id: 'production',
        farmId: 'farm-1',
        itemId: 'item-1',
        kind: InventoryMovementKind.issue,
        quantity: 1,
        occurredAt: DateTime.utc(2026, 10, 25),
      ),
      parcelId: 'p',
      seasonId: 's',
    );
    final original = await snapshot();
    final counts = await validate(original);
    expect(counts['agrico.db/production_seasons_v2'], 1);
    expect(counts['agrico.db/production_material_costs_v2'], 1);
    for (final table in [
      'production_seasons_v2',
      'production_material_costs_v2',
    ]) {
      await expectLater(
        validate(
          _rewrite(original, (tables) {
            ((tables[table] as List).single as Map)['farm_id'] = 'wrong-farm';
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
    }
    expect((await repository.productionCosts('farm-1')).single.amount, 100);
  });

  test(
    'pre-production backup may omit empty native production tables',
    () async {
      final bytes = _rewrite(await snapshot(), (tables) {
        tables.remove('production_seasons_v2');
        tables.remove('production_material_costs_v2');
      });
      await validate(bytes);
      await unchanged();
    },
  );

  test(
    'stages inventory stock and Unicode movement snapshot without live changes',
    () async {
      final bytes = await snapshot();
      final saved = LocalDatabaseSnapshot.decodeDatabases(bytes)['agrico.db']!;
      final tables = saved['tables'] as Map<String, dynamic>;
      final item =
          (tables[SqliteInventoryRepository.itemsTable] as List).single as Map;
      expect(item['stock'], 3);
      expect(item['name'], 'ຝຸ່ນ · Phân bón');
      final counts = await validate(bytes);
      expect(counts['agrico.db/inventory_items_v2'], 1);
      expect(counts['agrico.db/inventory_movements_v2'], 2);
      await unchanged();
    },
  );

  test(
    'accepts a pre-inventory backup with both inventory tables absent',
    () async {
      final bytes = _rewrite(await snapshot(), (tables) {
        tables.remove(SqliteInventoryRepository.itemsTable);
        tables.remove(SqliteInventoryRepository.movementsTable);
      });
      final counts = await validate(bytes);
      expect(counts.containsKey('agrico.db/inventory_items_v2'), isFalse);
      expect(counts.containsKey('agrico.db/inventory_movements_v2'), isFalse);
      await unchanged();
    },
  );

  test(
    'rejects either missing inventory table when the other contains data',
    () async {
      final original = await snapshot();
      for (final name in [
        SqliteInventoryRepository.itemsTable,
        SqliteInventoryRepository.movementsTable,
      ]) {
        await expectLater(
          validate(_rewrite(original, (tables) => tables.remove(name))),
          throwsA(
            isA<RestorePreflightException>().having(
              (error) => error.reason,
              'reason',
              'tables',
            ),
          ),
        );
      }
      await unchanged();
    },
  );

  test(
    'rejects inconsistent stock or movement farm despite valid foreign keys',
    () async {
      final original = await snapshot();
      for (final wrongFarm in [false, true]) {
        final bytes = _rewrite(original, (tables) {
          if (wrongFarm) {
            final movement =
                (tables[SqliteInventoryRepository.movementsTable] as List).first
                    as Map;
            movement['farm_id'] = 'farm-2';
          } else {
            final item =
                (tables[SqliteInventoryRepository.itemsTable] as List).single
                    as Map;
            item['stock'] = 4;
          }
        });
        await expectLater(
          validate(bytes),
          throwsA(
            isA<RestorePreflightException>()
                .having((error) => error.reason, 'reason', 'integrity')
                .having(
                  (error) => error.step,
                  'step',
                  'inventory reconciliation',
                ),
          ),
        );
      }
      await unchanged();
    },
  );
}

Uint8List _rewrite(
  Uint8List bytes,
  void Function(Map<String, dynamic>) change,
) {
  final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final payload =
      jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
  final databases = payload['databases'] as Map<String, dynamic>;
  final primary = databases['agrico.db'] as Map<String, dynamic>;
  change(primary['tables'] as Map<String, dynamic>);
  final body = jsonEncode(payload);
  envelope['payload'] = body;
  envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}
