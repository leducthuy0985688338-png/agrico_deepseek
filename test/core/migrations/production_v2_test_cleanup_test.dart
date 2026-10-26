import 'package:agrico_deepseek/core/migrations/production_v2_test_cleanup.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database main;
  late Database costs;
  late SqliteInventoryRepository inventory;
  setUp(() async {
    main = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    costs = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await main.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY, farm_id TEXT, parcel_code TEXT, active INTEGER, kind TEXT)',
    );
    await main.insert('land_parcels', {
      'id': 'keep',
      'farm_id': 'local-farm',
      'parcel_code': 'P1',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await SqliteInventoryRepository.createSchema(main);
    for (final table in ProductionV2TestCleanup.legacyPrimaryTables) {
      await main.execute('CREATE TABLE "$table"(id TEXT PRIMARY KEY)');
      await main.insert(table, {'id': 'old-test'});
    }
    await main.execute('CREATE TABLE finance_keep(id TEXT PRIMARY KEY)');
    await main.insert('finance_keep', {'id': 'keep'});
    await costs.execute('CREATE TABLE production_costs(id TEXT PRIMARY KEY)');
    await costs.insert('production_costs', {'id': 'old-test'});
    inventory = SqliteInventoryRepository(main);
    await inventory.register(
      const InventoryItem(
        id: 'item',
        farmId: 'local-farm',
        code: 'VT1',
        name: 'Material',
        unit: 'kg',
        unitPrice: 12,
        supplier: '',
      ),
    );
    await inventory.record(
      InventoryMovement(
        id: 'old-in',
        farmId: 'local-farm',
        itemId: 'item',
        kind: InventoryMovementKind.receipt,
        quantity: 5,
        occurredAt: DateTime.utc(2026, 10, 25),
      ),
    );
  });
  tearDown(() async {
    await main.close();
    await costs.close();
  });
  Future<void> clean() => ProductionV2TestCleanup.run(
    primary: main,
    legacyCosts: costs,
    farmId: 'local-farm',
  );

  test(
    'removes incompatible test rows preserves V2 parcels catalogs and unrelated data',
    () async {
      await clean();
      for (final table in ProductionV2TestCleanup.legacyPrimaryTables) {
        expect(await main.query(table), isEmpty);
      }
      expect(await costs.query('production_costs'), isEmpty);
      expect(await inventory.movementsByFarm('local-farm'), isEmpty);
      expect(await main.query('inventory_warehouse_stock_v1'), isEmpty);
      expect((await inventory.listByFarm('local-farm')).single.stock, 0);
      expect((await inventory.listByFarm('local-farm')).single.unitPrice, 12);
      expect(await main.query('land_parcels'), hasLength(1));
      expect(await main.query('finance_keep'), hasLength(1));
      expect(
        (await main.query(ProductionV2TestCleanup.table)).single['phase'],
        'complete',
      );
      await inventory.record(
        InventoryMovement(
          id: 'new-in',
          farmId: 'local-farm',
          itemId: 'item',
          kind: InventoryMovementKind.receipt,
          quantity: 3,
          occurredAt: DateTime.utc(2026, 10, 25),
        ),
      );
      await clean();
      expect((await inventory.listByFarm('local-farm')).single.stock, 3);
      expect(
        (await inventory.movementsByFarm('local-farm')).single.code,
        'NHAP-202610-001',
      );
    },
  );

  test(
    'cost DB failure leaves durable phase; retry does not clear new inventory',
    () async {
      await costs.execute(
        "CREATE TRIGGER fail_cleanup BEFORE DELETE ON production_costs BEGIN SELECT RAISE(ABORT,'locked'); END",
      );
      await expectLater(clean(), throwsA(isA<DatabaseException>()));
      expect(
        (await main.query(ProductionV2TestCleanup.table)).single['phase'],
        'main_done',
      );
      await inventory.record(
        InventoryMovement(
          id: 'new-in',
          farmId: 'local-farm',
          itemId: 'item',
          kind: InventoryMovementKind.receipt,
          quantity: 3,
          occurredAt: DateTime.utc(2026, 10, 25),
        ),
      );
      await costs.execute('DROP TRIGGER fail_cleanup');
      await clean();
      expect((await inventory.listByFarm('local-farm')).single.stock, 3);
      expect(await costs.query('production_costs'), isEmpty);
    },
  );

  test(
    'primary failure rolls back all old-data removal and has no completion marker',
    () async {
      await main.execute(
        "CREATE TRIGGER fail_fields BEFORE DELETE ON fields BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      await expectLater(clean(), throwsA(isA<DatabaseException>()));
      expect(await main.query('production_logs'), hasLength(1));
      expect(await main.query('fields'), hasLength(1));
      expect(await main.query(ProductionV2TestCleanup.table), isEmpty);
      expect((await inventory.listByFarm('local-farm')).single.stock, 5);
      expect(await costs.query('production_costs'), hasLength(1));
    },
  );
}
