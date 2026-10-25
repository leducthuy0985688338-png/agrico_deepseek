import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteInventoryRepository repo;
  const admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: {
      PermissionCodes.inventoryManage,
      PermissionCodes.productionPlan,
      PermissionCodes.financeView,
      PermissionCodes.inventoryView,
    },
    dataScopes: {DataScope.allFarm},
  );
  InventoryMovement event(
    String id, {
    int quantity = 2,
    String farm = 'farm',
    InventoryMovementKind kind = InventoryMovementKind.issue,
  }) => InventoryMovement(
    id: id,
    farmId: farm,
    itemId: 'item',
    kind: kind,
    quantity: quantity,
    occurredAt: DateTime.utc(2026, 10, 25),
  );
  ProductionSeason season(
    String id,
    String parcel, {
    String farm = 'farm',
    String date = '2026-10-01',
  }) => ProductionSeason(
    id: id,
    farmId: farm,
    parcelId: parcel,
    name: id,
    startsOn: date,
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY, farm_id TEXT, parcel_code TEXT, active INTEGER, kind TEXT)',
    );
    await SqliteInventoryRepository.createSchema(db);
    repo = SqliteInventoryRepository(db);
    for (final p in [
      ('p1', 'farm', 'fieldPlot'),
      ('p2', 'farm', 'fieldPlot'),
      ('other', 'other-farm', 'fieldPlot'),
      ('block', 'farm', 'landBlock'),
    ]) {
      await db.insert('land_parcels', {
        'id': p.$1,
        'farm_id': p.$2,
        'parcel_code': p.$1,
        'active': 1,
        'kind': p.$3,
      });
    }
    await repo.register(
      const InventoryItem(
        id: 'item',
        farmId: 'farm',
        code: 'VT001',
        name: 'Material',
        unit: 'kg',
        unitPrice: 12,
        supplier: '',
      ),
    );
    await repo.record(
      event('receipt', quantity: 10, kind: InventoryMovementKind.receipt),
    );
  });
  tearDown(() => db.close());

  test(
    'creates seasons directly on V2 plots without any legacy field table',
    () async {
      final service = InventoryService(repo);
      await service.createProductionSeason(admin, season('s1', 'p1'));
      expect(
        (await service.productionDestinations(admin)).single.parcelId,
        'p1',
      );
      expect((await repo.productionParcels('farm')).map((p) => p.id), [
        'p1',
        'p2',
      ]);
      expect(await repo.productionDestinations('other-farm'), isEmpty);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name IN ('fields','production_seasons','production_field_links_v1','inventory_cost_outbox_v2')",
        ),
        isEmpty,
      );
      await expectLater(
        repo.createProductionSeason(season('bad', 'other')),
        throwsStateError,
      );
      await expectLater(
        repo.createProductionSeason(season('bad', 'block')),
        throwsStateError,
      );
      await expectLater(
        repo.createProductionSeason(season('bad', 'p1', date: '2026-02-30')),
        throwsFormatException,
      );
      await expectLater(
        repo.createProductionSeason(season('s1', 'p1')),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'one transaction persists movement stock price and V2 cost; replay cannot duplicate',
    () async {
      await repo.createProductionSeason(season('s1', 'p1'));
      await repo.recordProductionIssue(
        event('issue'),
        parcelId: 'p1',
        seasonId: 's1',
      );
      final reopened = SqliteInventoryRepository(db);
      expect((await reopened.listByFarm('farm')).single.stock, 8);
      final cost = (await reopened.productionCosts('farm')).single;
      expect(cost.amount, 24);
      expect(cost.parcelId, 'p1');
      expect(cost.seasonId, 's1');
      await db.update(SqliteInventoryRepository.itemsTable, {
        'unit_price': 999,
      });
      await expectLater(
        repo.recordProductionIssue(
          event('issue'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.productionCosts('farm')).single.unitPrice, 12);
      expect((await repo.listByFarm('farm')).single.stock, 8);
      expect(await repo.productionCosts('other-farm'), isEmpty);
      expect(
        (await repo.movementsByFarm(
          'farm',
        )).firstWhere((m) => m.id == 'issue').code,
        'XUAT-202610-001',
      );
    },
  );

  test(
    'failed cost insert rolls back stock movement and number; retry succeeds once',
    () async {
      await repo.createProductionSeason(season('s1', 'p1'));
      await db.execute(
        "CREATE TRIGGER reject_cost BEFORE INSERT ON production_material_costs_v2 BEGIN SELECT RAISE(ABORT,'disk failure'); END",
      );
      await expectLater(
        repo.recordProductionIssue(
          event('issue'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.listByFarm('farm')).single.stock, 10);
      expect(await repo.movementsByFarm('farm'), hasLength(1));
      expect(await repo.productionCosts('farm'), isEmpty);
      await db.execute('DROP TRIGGER reject_cost');
      await repo.recordProductionIssue(
        event('issue'),
        parcelId: 'p1',
        seasonId: 's1',
      );
      expect(
        (await repo.movementsByFarm(
          'farm',
        )).firstWhere((m) => m.id == 'issue').code,
        'XUAT-202610-001',
      );
      expect(await repo.productionCosts('farm'), hasLength(1));
    },
  );

  test(
    'wrong season farm inactive future date and insufficient stock leave no cost',
    () async {
      await repo.createProductionSeason(season('s1', 'p1'));
      await repo.createProductionSeason(season('s2', 'p2'));
      await repo.createProductionSeason(
        season('future', 'p1', date: '2026-11-01'),
      );
      for (final destination in [
        ('p1', 's2'),
        ('p1', 'future'),
        ('other', 's1'),
      ]) {
        await expectLater(
          repo.recordProductionIssue(
            event('bad'),
            parcelId: destination.$1,
            seasonId: destination.$2,
          ),
          throwsStateError,
        );
      }
      await expectLater(
        repo.recordProductionIssue(
          event('bad', farm: 'other-farm'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.recordProductionIssue(
          event('bad', quantity: 99),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsStateError,
      );
      await repo.setProductionSeasonActive('farm', 's1', false);
      await expectLater(
        repo.recordProductionIssue(
          event('bad'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsStateError,
      );
      await repo.setProductionSeasonActive('farm', 's1', true);
      await db.update(
        'land_parcels',
        {'active': 0},
        where: 'id=?',
        whereArgs: ['p1'],
      );
      await expectLater(
        repo.recordProductionIssue(
          event('bad'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsStateError,
      );
      expect(await repo.productionCosts('farm'), isEmpty);
      expect((await repo.listByFarm('farm')).single.stock, 10);
    },
  );

  test(
    'view-only and expired sessions cannot create or post production data',
    () async {
      const viewer = AuthorizationSubject(
        userId: 'u',
        membershipId: 'm',
        farmId: 'farm',
        permissionCodes: {PermissionCodes.inventoryView},
        dataScopes: {DataScope.allFarm},
      );
      final service = InventoryService(repo);
      const warehouse = AuthorizationSubject(
        userId: 'u',
        membershipId: 'm',
        farmId: 'farm',
        permissionCodes: {
          PermissionCodes.inventoryView,
          PermissionCodes.inventoryManage,
        },
        dataScopes: {DataScope.allFarm},
      );
      expect(
        () => service.createProductionSeason(warehouse, season('denied', 'p1')),
        throwsStateError,
      );
      expect(() => service.productionCosts(warehouse), throwsStateError);

      expect(
        () => service.createProductionSeason(viewer, season('s1', 'p1')),
        throwsStateError,
      );
      final expired = AuthorizationSubject(
        userId: 'u',
        membershipId: 'm',
        farmId: 'farm',
        permissionCodes: {PermissionCodes.inventoryManage},
        dataScopes: {DataScope.allFarm},
        validUntil: DateTime.utc(2000),
      );
      expect(
        () => service.recordProductionIssue(
          expired,
          event('bad'),
          parcelId: 'p1',
          seasonId: 's1',
        ),
        throwsStateError,
      );
      expect(await repo.productionSeasons('farm'), isEmpty);
    },
  );
}
