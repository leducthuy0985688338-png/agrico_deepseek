import 'package:agrico_deepseek/core/permissions/live_authorization.dart';
import 'package:agrico_deepseek/core/permissions/operation_scope.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/trade/domain/trade.dart' as trade;
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';
import 'package:agrico_deepseek/features/machines/domain/machines.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_planning_repository.dart';

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
          unitPriceText: '100',
          currency: 'VND',
          pricedBy: 'admin',
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

  test(
    'trade backup preserves lot debt cash and rejects partial or altered ledger',
    () async {
      await primary.execute(
        'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
      );
      await primary.execute(
        'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
      );
      await SqliteCompanyCatalog.createSchema(primary);
      await SqliteFinanceDocumentRepository.createSchema(primary);
      await SqliteTradeRepository.createSchema(primary);
      final subject = AuthorizationSubject(
        userId: 'admin',
        membershipId: 'admin',
        farmId: 'farm-1',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      final catalog = CompanyCatalogService(
        repository: SqliteCompanyCatalog(primary),
        subject: subject,
      );
      for (final (id, kind, unit) in [
        ('unit', CatalogKind.unit, null),
        ('product', CatalogKind.product, 'unit'),
        ('customer', CatalogKind.customer, null),
      ]) {
        await catalog.create(
          CatalogEntry(
            id: id,
            farmId: 'farm-1',
            kind: kind,
            code: '',
            name: id,
            unitId: unit,
          ),
          reason: 'Test setup',
        );
      }
      await primary.insert('land_parcels', {
        'id': 'land',
        'farm_id': 'farm-1',
        'parcel_code': 'P001',
        'active': 1,
        'kind': 'fieldPlot',
      });
      await repository.createProductionSeason(
        const ProductionSeason(
          id: 'season',
          farmId: 'farm-1',
          parcelId: 'land',
          name: 'Season',
          startsOn: '2026-10-01',
        ),
      );
      await repository.createProductionPlan(
        const ProductionPlan(
          id: 'p',
          farmId: 'farm-1',
          parcelId: 'land',
          seasonId: 'season',
          name: 'Plan',
          crop: 'Peanut',
          startsOn: '2026-10-01',
          endsOn: '2026-10-31',
          currency: 'VND',
          materialBudget: '0',
          laborBudget: '0',
          machineBudget: '0',
          laborHours: '0',
          machineShifts: '0',
        ),
        'admin',
      );
      await repository.changeProductionPlanStatus(
        'farm-1',
        'p',
        0,
        ProductionPlanStatus.active,
        'admin',
      );
      final repo = SqliteTradeRepository(primary);
      final h = trade.TradeDraft(
        id: 'h',
        kind: trade.TradeKind.harvest,
        day: '2026-10-20',
        currency: 'VND',
        rounding: trade.MoneyRounding.halfUp,
        lines: const [
          trade.TradeLine(ref: 'product', quantity: '10', price: '5'),
        ],
        planId: 'p',
      );
      final sale = trade.TradeDraft(
        id: 'sale',
        kind: trade.TradeKind.sale,
        day: '2026-10-21',
        currency: 'VND',
        rounding: trade.MoneyRounding.halfUp,
        lines: const [
          trade.TradeLine(
            ref: 'h:0',
            quantity: '4',
            price: '10',
            issuePrice: '5',
          ),
        ],
        partyId: 'customer',
        dueOn: '2026-10-25',
      );
      await repo.create('farm-1', h, 'admin');
      await repo.post('farm-1', 'h', 0, 'admin');
      await repo.create('farm-1', sale, 'admin');
      await repo.post('farm-1', 'sale', 0, 'admin');
      await repo.settle(
        'farm-1',
        'pay',
        'sale',
        '15',
        'VND',
        '2026-10-22',
        'Bank reference',
        'admin',
      );
      final original = await snapshot();
      final counts = await validate(original);
      expect(counts['agrico.db/trade_lots_v1'], 1);
      await expectLater(
        validate(
          _rewrite(original, (tables) {
            ((tables['trade_lots_v1'] as List).single as Map)['stock_units'] =
                1;
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
      await expectLater(
        validate(
          _rewrite(original, (tables) {
            ((tables['finance_documents_v2'] as List).single
                    as Map)['amount_minor'] =
                16;
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
      await expectLater(
        validate(
          _rewrite(original, (tables) {
            tables.remove('trade_settlements_v1');
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
      expect((await repo.lots('farm-1')).single.quantity, '6');
      expect(
        (await repo.documents(
          'farm-1',
        )).firstWhere((d) => d.draft.id == 'sale').balance,
        '25',
      );
      expect(
        (await repository.listByFarm(
          'farm-1',
        )).firstWhere((i) => i.id == 'item-1').stock,
        3,
      );
    },
  );

  test(
    'machine backup retains snapshots and rejects tampering or partial tables',
    () async {
      await primary.execute(
        'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
      );
      await primary.execute(
        'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
      );
      await SqliteCompanyCatalog.createSchema(primary);
      await SqliteMachineRepository.createSchema(primary);
      for (final (id, kind) in [
        ('machine', 'machine'),
        ('operator', 'worker'),
      ]) {
        await primary.insert('company_catalog_entries_v1', {
          'id': id,
          'farm_id': 'farm-1',
          'kind': kind,
          'code': id,
          'name': id,
          'name_key': id,
          'active': 1,
          'revision': 1,
        });
        await primary.insert('parcel_work_resources', {
          'id': id,
          'farm_id': 'farm-1',
          'kind': kind,
          'code': id,
          'name': id,
          'active': 1,
        });
      }
      final machines = SqliteMachineRepository(primary);
      await machines.profile('farm-1', 'machine', 0, {
        'meterUnit': 'hour',
      }, 'admin');
      await machines.addRate(
        'farm-1',
        const MachineRate(
          id: 'rate',
          machineId: 'machine',
          effectiveOn: '2026-10-01',
          amount: '800000',
          currency: 'VND',
          shiftMinutes: 480,
          scale: 0,
          rounding: MoneyRounding.halfUp,
        ),
        'admin',
      );
      await machines.addRun(
        'farm-1',
        MachineRun(
          id: 'run',
          machineId: 'machine',
          operatorId: 'operator',
          startsAt: DateTime.utc(2026, 10, 20, 1),
          endsAt: DateTime.utc(2026, 10, 20, 10),
          idleMinutes: 60,
          meterStart: '100',
          meterEnd: '108',
        ),
        'admin',
      );
      await machines.approveRun('farm-1', 'run', 0, 'admin');
      final bytes = await snapshot();
      final counts = await validate(bytes);
      expect(counts['agrico.db/machine_runs_v1'], 1);
      await expectLater(
        validate(
          _rewrite(bytes, (tables) {
            ((tables['machine_runs_v1'] as List).single as Map)['amount'] = '1';
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
      await expectLater(
        validate(
          _rewrite(bytes, (tables) {
            tables.remove('machine_rates_v1');
          }),
        ),
        throwsA(isA<RestorePreflightException>()),
      );
      await validate(
        _rewrite(bytes, (tables) {
          for (final table in SqliteMachineRepository.tables) {
            tables.remove(table);
          }
        }),
      );
      expect((await machines.runs('farm-1')).single.amount, '800000');
      await unchanged();
    },
  );

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
    await repository.createProductionPlan(
      const ProductionPlan(
        id: 'plan',
        farmId: 'farm-1',
        parcelId: 'p',
        seasonId: 's',
        name: 'Plan',
        crop: 'Peanut',
        startsOn: '2026-09-01',
        endsOn: '2026-12-31',
        currency: 'VND',
        materialBudget: '1000',
        laborBudget: '0',
        machineBudget: '0',
        laborHours: '0',
        machineShifts: '0',
      ),
      'admin',
    );
    await repository.changeProductionPlanStatus(
      'farm-1',
      'plan',
      0,
      ProductionPlanStatus.active,
      'admin',
    );
    await repository.recordProductionIssue(
      InventoryMovement(
        unitPriceText: '100',
        currency: 'VND',
        pricedBy: 'admin',
        id: 'production',
        farmId: 'farm-1',
        itemId: 'item-1',
        kind: InventoryMovementKind.issue,
        quantity: 1,
        occurredAt: DateTime.utc(2026, 10, 25),
      ),
      parcelId: 'p',
      seasonId: 's',
      planId: 'plan',
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
        for (final t in [
          'inventory_warehouses_v1',
          'inventory_warehouse_sequences_v1',
          'inventory_warehouse_stock_v1',
          'inventory_transfers_v1',
        ]) {
          tables.remove(t);
        }
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
  test(
    'multi-warehouse backup reconciles transfer pairs and rejects a tampered leg',
    () async {
      const actor = AuthorizationSubject(
        userId: 'admin',
        membershipId: 'm',
        farmId: 'farm-1',
        permissionCodes: PermissionCodes.values,
        dataScopes: {DataScope.allFarm},
      );
      await repository.createWarehouse(
        'farm-1',
        'second',
        'Kho thứ hai',
        'admin',
      );
      await repository.transfer(
        'farm-1',
        'transfer',
        'item-1',
        'warehouse:default:farm-1',
        'second',
        1.125,
        DateTime.utc(2026, 10, 1),
        'admin',
        OperationScope(actor, LiveAuthorization(() => actor), [
          PermissionCodes.inventoryView,
          PermissionCodes.inventoryTransfer,
        ]),
      );
      final bytes = await snapshot();
      final counts = await validate(bytes);
      expect(counts['agrico.db/inventory_transfers_v1'], 1);
      final tampered = _rewrite(bytes, (tables) {
        final rows = tables['inventory_movements_v2'] as List;
        (rows.singleWhere((r) => (r as Map)['id'] == 'transfer:transfer:in')
                as Map)['transfer_id'] =
            null;
      });
      await expectLater(
        validate(tampered),
        throwsA(
          isA<RestorePreflightException>().having(
            (e) => e.reason,
            'reason',
            'integrity',
          ),
        ),
      );
      expect((await repository.listByFarm('farm-1')).single.stock, 3);
    },
  );
  test(
    'nonempty pre-warehouse backups are rejected rather than guessing split balances',
    () async {
      final old = _rewrite(await snapshot(), (tables) {
        for (final name in [
          'inventory_warehouses_v1',
          'inventory_warehouse_sequences_v1',
          'inventory_warehouse_stock_v1',
          'inventory_transfers_v1',
        ]) {
          tables.remove(name);
        }
        for (final row in tables['inventory_movements_v2'] as List) {
          (row as Map).remove('warehouse_id');
          row.remove('transfer_id');
        }
      });
      await expectLater(
        validate(old),
        throwsA(
          isA<RestorePreflightException>().having(
            (e) => e.reason,
            'reason',
            'incompatibleProductionData',
          ),
        ),
      );
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
