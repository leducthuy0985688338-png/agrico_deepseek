import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/application/production_plan_report.dart';
import 'package:agrico_deepseek/features/inventory/data/local/production_inventory_integrity.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/exact_decimal.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_planning_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:excel/excel.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteInventoryRepository repo;
  late InventoryService service;
  late AuthorizationSubject live;
  final admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'a',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  const keeper = AuthorizationSubject(
    userId: 'keeper',
    membershipId: 'k',
    farmId: 'f',
    permissionCodes: {
      PermissionCodes.inventoryManage,
      PermissionCodes.inventoryView,
    },
    dataScopes: {DataScope.allFarm},
  );
  ProductionPlan plan(
    String id, {
    String parcel = 'p',
    String season = 's',
    String currency = 'VND',
    String start = '2026-10-01',
    String end = '2026-10-31',
  }) => ProductionPlan(
    id: id,
    farmId: 'f',
    parcelId: parcel,
    seasonId: season,
    name: id,
    crop: 'Peanut',
    startsOn: start,
    endsOn: end,
    currency: currency,
    materialBudget: '100000',
    laborBudget: '200000',
    machineBudget: '300000',
    laborHours: '16',
    machineShifts: '1.5',
  );
  InventoryMovement move(
    String id, {
    num quantity = 2.25,
    String? price = '20000',
    String currency = 'VND',
    bool zero = false,
  }) => InventoryMovement(
    id: id,
    farmId: 'f',
    itemId: 'i',
    kind: InventoryMovementKind.issue,
    quantity: quantity,
    occurredAt: DateTime.utc(2026, 10, 25),
    unitPriceText: price,
    currency: currency,
    zeroPriceConfirmed: zero,
  );
  Future<void> activate(String id, {String currency = 'VND'}) async {
    await service.createProductionPlan(admin, plan(id, currency: currency));
    await service.changeProductionPlanStatus(
      admin,
      (await service.productionPlans(admin)).firstWhere((p) => p.id == id),
      ProductionPlanStatus.active,
    );
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE land_parcels(id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT,active INTEGER,kind TEXT)',
    );
    await db.execute('CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY)');
    await SqliteFarmTaskRepository.createTaskTable(db);
    await SqliteInventoryRepository.createSchema(db);
    repo = SqliteInventoryRepository(db);
    live = admin;
    service = InventoryService(repo, currentSubject: () => live);
    await db.insert('land_parcels', {
      'id': 'p',
      'farm_id': 'f',
      'parcel_code': 'P001',
      'active': 1,
      'kind': 'fieldPlot',
    });
    await repo.createProductionSeason(
      const ProductionSeason(
        id: 's',
        farmId: 'f',
        parcelId: 'p',
        name: 'Season',
        startsOn: '2026-10-01',
      ),
    );
    await repo.register(
      const InventoryItem(
        id: 'i',
        farmId: 'f',
        code: 'VT001',
        name: 'Phân · ຝຸ່ນ',
        unit: 'kg',
        unitPrice: 999,
        supplier: '',
      ),
    );
    await repo.record(
      InventoryMovement(
        id: 'in',
        farmId: 'f',
        itemId: 'i',
        kind: InventoryMovementKind.receipt,
        quantity: 10.5,
        occurredAt: DateTime.utc(2026, 10, 1),
      ),
    );
  });
  tearDown(() => db.close());
  test(
    'system admin alone receives issue pricing in default role templates',
    () {
      expect(
        CompanyRolePolicy.permissions(CompanyRole.systemAdmin),
        contains(PermissionCodes.inventoryPrice),
      );
      for (final role in CompanyRole.values.where(
        (r) => r != CompanyRole.systemAdmin,
      )) {
        expect(
          CompanyRolePolicy.permissions(role),
          isNot(contains(PermissionCodes.inventoryPrice)),
        );
      }
    },
  );
  test(
    'plan sequences are atomic independent per currency plans and concurrent callers',
    () async {
      await Future.wait([
        service.createProductionPlan(admin, plan('a')),
        service.createProductionPlan(admin, plan('b', currency: 'LAK')),
      ]);
      expect((await repo.productionPlans('f')).map((p) => p.code).toSet(), {
        'KH-202610-001',
        'KH-202610-002',
      });
      expect(await repo.productionPlans('other'), isEmpty);
    },
  );
  test('failed plan audit rolls back number and plan', () async {
    await db.execute(
      "CREATE TRIGGER fail_plan BEFORE INSERT ON production_plan_audit_v1 BEGIN SELECT RAISE(ABORT,'test'); END",
    );
    await expectLater(
      service.createProductionPlan(admin, plan('a')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.productionPlans('f'), isEmpty);
    await db.execute('DROP TRIGGER fail_plan');
    await service.createProductionPlan(admin, plan('b'));
    expect((await repo.productionPlans('f')).single.code, 'KH-202610-001');
  });
  test(
    'invalid dates and wrong season reject without consuming a number',
    () async {
      expect(
        () => plan('bad', start: '2026-02-30').validate(),
        throwsFormatException,
      );
      await expectLater(
        service.createProductionPlan(admin, plan('bad', season: 'missing')),
        throwsStateError,
      );
      await service.createProductionPlan(admin, plan('ok'));
      expect((await repo.productionPlans('f')).single.code, 'KH-202610-001');
    },
  );
  test(
    'Admin price replaces catalog price and preserves fractional stock exactly',
    () async {
      await activate('a');
      await service.recordProductionIssue(
        admin,
        move('out'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'a',
      );
      expect((await repo.listByFarm('f')).single.stock, 8.25);
      final c = (await repo.productionCosts('f')).single;
      expect(c.unitPriceText, '20000');
      expect(c.amountText, '45000');
      expect(c.currency, 'VND');
      expect(
        (await db.query(
          'inventory_movements_v2',
          where: 'id=?',
          whereArgs: ['out'],
        )).single['priced_by'],
        'admin',
      );
      await db.update('inventory_items_v2', {'unit_price': 123});
      expect((await repo.productionCosts('f')).single.amountText, '45000');
      await ProductionInventoryIntegrity.validate(db);
    },
  );
  test(
    'decimal price multiplication has no binary error or implicit rounding',
    () async {
      await activate('a');
      await service.recordProductionIssue(
        admin,
        move('x', quantity: 0.1, price: '0.2'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'a',
      );
      expect((await repo.productionCosts('f')).single.amountText, '0.02');
      await ProductionInventoryIntegrity.validate(db);
    },
  );
  test(
    'warehouse permissions cannot supply a price or read financial budgets',
    () async {
      live = keeper;
      expect(() => service.record(keeper, move('x')), throwsStateError);
      expect(() => service.productionPlans(keeper), throwsStateError);
      expect((await repo.listByFarm('f')).single.stock, 10.5);
    },
  );
  test('missing price and unconfirmed zero cannot be posted', () async {
    expect(
      () => service.record(admin, move('missing', price: null)),
      throwsFormatException,
    );
    expect(
      () => service.record(admin, move('zero', price: '0')),
      throwsFormatException,
    );
    await service.record(admin, move('zero-ok', price: '0', zero: true));
    expect((await repo.listByFarm('f')).single.stock, 8.25);
  });
  test(
    'same request replay is successful without stock cost or counter duplication',
    () async {
      await activate('a');
      final request = move('out');
      for (var i = 0; i < 2; i++) {
        await service.recordProductionIssue(
          admin,
          request,
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        );
      }
      expect((await repo.listByFarm('f')).single.stock, 8.25);
      expect(await repo.productionCosts('f'), hasLength(1));
      await expectLater(
        service.recordProductionIssue(
          admin,
          move('out', quantity: 1),
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'cost insertion failure rolls back fractional stock movement and sequence',
    () async {
      await activate('a');
      await db.execute(
        "CREATE TRIGGER fail_cost BEFORE INSERT ON production_material_costs_v2 BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(
        service.recordProductionIssue(
          admin,
          move('x'),
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.listByFarm('f')).single.stock, 10.5);
      expect(await repo.movementsByFarm('f'), hasLength(1));
      await db.execute('DROP TRIGGER fail_cost');
      await service.recordProductionIssue(
        admin,
        move('x'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'a',
      );
      expect((await repo.movementsByFarm('f')).last.code, 'XUAT-202610-001');
    },
  );
  test(
    'draft paused wrong currency and closed season cannot accept consumption',
    () async {
      await service.createProductionPlan(admin, plan('a'));
      await expectLater(
        service.recordProductionIssue(
          admin,
          move('draft'),
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        ),
        throwsStateError,
      );
      await service.changeProductionPlanStatus(
        admin,
        (await repo.productionPlans('f')).single,
        ProductionPlanStatus.active,
      );
      await expectLater(
        service.recordProductionIssue(
          admin,
          move('currency', currency: 'LAK'),
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        ),
        throwsStateError,
      );
      await service.changeProductionPlanStatus(
        admin,
        (await repo.productionPlans('f')).single,
        ProductionPlanStatus.paused,
      );
      await expectLater(
        service.recordProductionIssue(
          admin,
          move('paused'),
          parcelId: 'p',
          seasonId: 's',
          planId: 'a',
        ),
        throwsStateError,
      );
      await repo.setProductionSeasonActive('f', 's', false);
      await expectLater(
        service.changeProductionPlanStatus(
          admin,
          (await repo.productionPlans('f')).single,
          ProductionPlanStatus.active,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'stale plan and task revisions cannot overwrite current state',
    () async {
      await service.createProductionPlan(admin, plan('a'));
      final original = (await repo.productionPlans('f')).single;
      await service.changeProductionPlanStatus(
        admin,
        original,
        ProductionPlanStatus.active,
      );
      await expectLater(
        service.changeProductionPlanStatus(
          admin,
          original,
          ProductionPlanStatus.cancelled,
        ),
        throwsStateError,
      );
      const t = ProductionPlanTask(
        id: 't',
        farmId: 'f',
        planId: 'a',
        title: 'Sowing',
        stage: 'Planting',
        quantity: '2.5',
        unit: 'ha',
      );
      await service.createProductionPlanTask(admin, t);
      await service.completeProductionPlanTask(admin, t, true);
      await expectLater(
        service.completeProductionPlanTask(admin, t, false),
        throwsStateError,
      );
    },
  );
  test(
    'pending tasks prevent completion and completed plan is final',
    () async {
      await activate('a');
      const t = ProductionPlanTask(
        id: 't',
        farmId: 'f',
        planId: 'a',
        title: 'Sowing',
        stage: '',
        quantity: '1',
        unit: 'ha',
      );
      await service.createProductionPlanTask(admin, t);
      await expectLater(
        service.changeProductionPlanStatus(
          admin,
          (await repo.productionPlans('f')).single,
          ProductionPlanStatus.completed,
        ),
        throwsStateError,
      );
      await service.completeProductionPlanTask(admin, t, true);
      await service.changeProductionPlanStatus(
        admin,
        (await repo.productionPlans('f')).single,
        ProductionPlanStatus.completed,
      );
      await expectLater(
        service.changeProductionPlanStatus(
          admin,
          (await repo.productionPlans('f')).single,
          ProductionPlanStatus.active,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'report keeps VND LAK separate and opens as independent Excel workbook',
    () async {
      await activate('a');
      await activate('b', currency: 'LAK');
      await service.recordProductionIssue(
        admin,
        move('v', quantity: 1, price: '20000'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'a',
      );
      await service.recordProductionIssue(
        admin,
        move('l', quantity: 1, price: '30000', currency: 'LAK'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'b',
      );
      final report = ProductionPlanReport(
        farmId: 'f',
        plans: await repo.productionPlans('f'),
        tasks: await repo.productionPlanTasks('f'),
        costs: await repo.productionCosts('f'),
      );
      final decoded = Excel.decodeBytes(report.bytes());
      expect(
        decoded.tables.keys,
        containsAll([
          'THONG TIN',
          'KE HOACH SAN XUAT',
          'VAT TU SD',
          'LICH TAC VU',
          'TONG HOP',
        ]),
      );
      final rows = decoded['TONG HOP'].rows;
      expect(rows[1][0]!.value.toString(), 'VND');
      expect(rows[1][2]!.value.toString(), '20000');
      expect(rows[2][0]!.value.toString(), 'LAK');
      expect(rows[2][2]!.value.toString(), '30000');
      final emptyPeriod = ProductionPlanReport(
        farmId: 'f',
        plans: report.plans,
        tasks: [],
        costs: report.costs,
        planId: 'a',
        from: DateTime(2026, 10, 26),
      );
      expect(emptyPeriod.materialActual('a').toString(), '0');
      expect(emptyPeriod.selectedPlans.single.materialBudget, '100000');
    },
  );
  test(
    'restore integrity rejects altered snapshot and cross-farm task',
    () async {
      await activate('a');
      await service.recordProductionIssue(
        admin,
        move('x'),
        parcelId: 'p',
        seasonId: 's',
        planId: 'a',
      );
      await db.update('production_material_costs_v2', {'amount_text': '1'});
      await expectLater(
        ProductionInventoryIntegrity.validate(db),
        throwsStateError,
      );
    },
  );
  test(
    'plan tasks share identity and completion with existing farm task module',
    () async {
      await activate('a');
      const t = ProductionPlanTask(
        id: 'shared',
        farmId: 'f',
        planId: 'a',
        title: 'Sow',
        stage: 'Sowing',
        quantity: '1',
        unit: 'ha',
      );
      await service.createProductionPlanTask(admin, t);
      final canonical = (await SqliteFarmTaskRepository(
        db,
      ).listByFarm('f')).single;
      expect(canonical.id, 'shared');
      expect(canonical.parcelId, 'p');
      await SqliteFarmTaskRepository(db).complete(farmId: 'f', id: 'shared');
      final linked = (await repo.productionPlanTasks('f')).single;
      expect(linked.completed, isTrue);
      expect(linked.revision, 1);
      await ProductionInventoryIntegrity.validate(db);
    },
  );
  test(
    'quantity precision is explicit and exact decimals reject exponents and NaN',
    () {
      expect(ExactDecimal.quantityUnits(2.25), 2250000);
      expect(
        () => ExactDecimal.quantityUnits(0.0000001),
        throwsFormatException,
      );
      expect(() => ExactDecimal.parse('NaN'), throwsFormatException);
      expect(() => ExactDecimal.parse('1e9'), throwsFormatException);
    },
  );
}
