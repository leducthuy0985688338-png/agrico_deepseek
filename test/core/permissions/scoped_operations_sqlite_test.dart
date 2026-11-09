import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/live_authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';
import 'package:agrico_deepseek/core/permissions/data/sqlite_operation_directory.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_warehouse_stock.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/personnel/data/sqlite_personnel_repository.dart';
import 'package:agrico_deepseek/features/machines/application/machine_service.dart';
import 'package:agrico_deepseek/features/machines/data/sqlite_machine_repository.dart';

AuthorizationSubject actor({
  Set<String>? permissions,
  Set<DataScope> scopes = const {DataScope.allFarm},
  Set<String> warehouses = const {},
  Set<String> machines = const {},
  Set<String> departments = const {},
  Map<String, Set<DataScope>> overrides = const {},
  String farm = 'f',
}) => AuthorizationSubject(
  userId: 'u',
  membershipId: 'm',
  farmId: farm,
  permissionCodes: permissions ?? PermissionCodes.values,
  dataScopes: scopes,
  assignedWarehouseIds: warehouses,
  assignedMachineIds: machines,
  departmentIds: departments,
  permissionScopes: overrides,
);

void main() {
  sqfliteFfiInit();
  late Database db;
  late AuthorizationSubject live;
  late InventoryService inventory;
  late PersonnelService people;
  late MachineService machines;
  final admin = actor();
  final at = DateTime.utc(2026, 10, 26, 1);
  InventoryMovement move(
    String id,
    String warehouse,
    num quantity, {
    bool issue = false,
    String farm = 'f',
  }) => InventoryMovement(
    id: id,
    farmId: farm,
    itemId: 'item',
    warehouseId: warehouse,
    kind: issue ? InventoryMovementKind.issue : InventoryMovementKind.receipt,
    quantity: quantity,
    occurredAt: at,
    unitPriceText: issue ? '100' : null,
    currency: issue ? 'LAK' : null,
    pricedBy: issue ? 'u' : null,
  );
  Future<num> stock(String warehouse) async =>
      (await inventory.list(live, warehouseId: warehouse)).single.stock;
  Future<void> seedStock() async {
    await inventory.createWarehouse(admin, 'a', 'Kho A');
    await inventory.createWarehouse(admin, 'b', 'Kho B');
    await inventory.record(admin, move('r-a', 'a', 10));
    await inventory.record(admin, move('r-b', 'b', 4));
  }

  MachineRun run(String id, String machine) => MachineRun(
    id: id,
    machineId: machine,
    operatorId: machine == 'm2' ? 'w2' : 'w1',
    startsAt: at,
    endsAt: at.add(const Duration(hours: 1)),
    idleMinutes: 0,
    meterStart: '0',
    meterEnd: '1',
  );
  setUp(() async {
    live = admin;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE company_catalog_entries_v1(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER,unit_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE parcel_work_resources(id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
    );
    await db.execute(
      'CREATE TABLE farm_tasks_v2(id TEXT PRIMARY KEY,farm_id TEXT,machine_resource_id TEXT,worker_resource_id TEXT,title TEXT,due_at TEXT)',
    );
    await SqliteInventoryRepository.createSchema(db);
    await SqlitePersonnelRepository.createSchema(db);
    await SqliteMachineRepository.createSchema(db);
    inventory = InventoryService(
      SqliteInventoryRepository(db),
      currentSubject: () => live,
    );
    people = PersonnelService(
      SqlitePersonnelRepository(db),
      currentSubject: () => live,
    );
    machines = MachineService(
      SqliteMachineRepository(db),
      currentSubject: () => live,
    );
    await db.insert('inventory_items_v2', {
      'id': 'item',
      'farm_id': 'f',
      'code': 'VT-001',
      'name': 'Phân bón',
      'unit': 'kg',
      'unit_price': 0,
      'supplier': '',
      'stock': 0,
      'stock_units': 0,
    });
    for (final (id, kind) in [
      ('w1', 'worker'),
      ('w2', 'worker'),
      ('m1', 'machine'),
      ('m2', 'machine'),
    ]) {
      final row = {
        'id': id,
        'farm_id': 'f',
        'kind': kind,
        'code': id,
        'name': id,
        'active': 1,
      };
      await db.insert('company_catalog_entries_v1', row);
      await db.insert('parcel_work_resources', row);
    }
    await people.createDepartment(
      admin,
      const PersonnelDepartment('d1', 'Bộ phận A'),
    );
    await people.createDepartment(
      admin,
      const PersonnelDepartment('d2', 'Bộ phận B'),
    );
    for (final (id, dept) in [('w1', 'd1'), ('w2', 'd2')]) {
      await people.saveProfile(
        admin,
        EmployeeProfile(
          workerId: id,
          farmId: 'f',
          departmentId: dept,
          details: {
            'position': 'Nhân viên',
            'identityNo': 'private-$id',
            'bankAccount': 'bank-$id',
          },
        ),
      );
    }
    for (final id in ['m1', 'm2']) {
      await machines.profile(admin, MachineCard(id, id, id, true, {}, 0), {
        'meterUnit': 'hour',
      });
      await machines.addRun(admin, run('run-$id', id));
    }
  });
  tearDown(() async => db.close());

  test(
    'one shared material has independent warehouse balances and a reconciled farm total',
    () async {
      await seedStock();
      expect(await stock('a'), 10);
      expect(await stock('b'), 4);
      expect((await inventory.list(admin)).single.stock, 14);
      await inventory.record(admin, move('out-a', 'a', 3, issue: true));
      expect(await stock('a'), 7);
      expect(await stock('b'), 4);
      expect(
        (await inventory.movements(admin, warehouseId: 'b')).map((m) => m.id),
        ['r-b'],
      );
      await SqliteWarehouseStock.validate(db);
    },
  );
  test(
    'warehouse shortage cannot borrow stock from another warehouse and rolls back',
    () async {
      await seedStock();
      await expectLater(
        inventory.record(admin, move('too-much', 'b', 5, issue: true)),
        throwsStateError,
      );
      expect(await stock('b'), 4);
      expect((await inventory.list(admin)).single.stock, 14);
      expect(
        await db.query(
          'inventory_movements_v2',
          where: 'id=?',
          whereArgs: ['too-much'],
        ),
        isEmpty,
      );
    },
  );
  test(
    'assigned warehouse reads and receipts work, aggregate and cross-warehouse reads do not',
    () async {
      await seedStock();
      live = actor(
        permissions: {
          PermissionCodes.inventoryView,
          PermissionCodes.inventoryReceive,
        },
        scopes: {DataScope.assignedWarehouses},
        warehouses: {'a'},
      );
      expect((await inventory.warehouses(admin)).map((w) => w.id), ['a']);
      expect(await stock('a'), 10);
      expect(() => inventory.list(admin), throwsStateError);
      expect(() => inventory.list(admin, warehouseId: 'b'), throwsStateError);
      await inventory.record(admin, move('keeper-receipt', 'a', 2));
      expect(await stock('a'), 12);
      expect(
        () => inventory.record(admin, move('outside', 'b', 1)),
        throwsStateError,
      );
      expect(
        () => inventory.record(
          admin,
          move('unpriced-admin-only', 'a', 1, issue: true),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'permission overrides restrict an all-farm union and assignment withdrawal is live',
    () async {
      await seedStock();
      live = actor(
        warehouses: {'a'},
        overrides: {
          PermissionCodes.inventoryView: {DataScope.assignedWarehouses},
        },
      );
      expect(() => inventory.list(admin), throwsStateError);
      expect(await stock('a'), 10);
      live = actor(
        overrides: {
          PermissionCodes.inventoryView: {DataScope.assignedWarehouses},
        },
      );
      expect(() => inventory.list(admin, warehouseId: 'a'), throwsStateError);
    },
  );
  test(
    'transfer is paired, exact, idempotent, unpriced and preserves total stock',
    () async {
      await seedStock();
      Future<void> transfer() => inventory.transfer(
        admin,
        id: 't',
        itemId: 'item',
        sourceId: 'a',
        destinationId: 'b',
        quantity: 2.125,
        at: at,
      );
      await transfer();
      await transfer();
      expect(await stock('a'), 7.875);
      expect(await stock('b'), 6.125);
      expect((await inventory.list(admin)).single.stock, 14);
      final rows = await db.query(
        'inventory_movements_v2',
        where: 'transfer_id=?',
        whereArgs: ['t'],
      );
      expect(rows.length, 2);
      expect(
        rows.every((r) => r['currency'] == null && r['amount_text'] == null),
        isTrue,
      );
      await SqliteWarehouseStock.validate(db);
      await expectLater(
        inventory.transfer(
          admin,
          id: 't',
          itemId: 'item',
          sourceId: 'a',
          destinationId: 'b',
          quantity: 1,
          at: at,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'transfer needs view and transfer permission on both warehouses; second-leg failure is atomic',
    () async {
      await seedStock();
      live = actor(scopes: {DataScope.assignedWarehouses}, warehouses: {'a'});
      expect(
        () => inventory.transfer(
          admin,
          id: 'denied',
          itemId: 'item',
          sourceId: 'a',
          destinationId: 'b',
          quantity: 1,
          at: at,
        ),
        throwsStateError,
      );
      live = admin;
      await db.update(
        'inventory_warehouses_v1',
        {'active': 0},
        where: 'id=?',
        whereArgs: ['b'],
      );
      await expectLater(
        inventory.transfer(
          admin,
          id: 'fail',
          itemId: 'item',
          sourceId: 'a',
          destinationId: 'b',
          quantity: 1,
          at: at,
        ),
        throwsStateError,
      );
      expect(await stock('a'), 10);
      expect(await db.query('inventory_transfers_v1'), isEmpty);
      expect((await db.query('inventory_movements_v2')).length, 2);
    },
  );
  test('cross-farm warehouse and balance corruption are rejected', () async {
    await seedStock();
    await db.insert('inventory_warehouses_v1', {
      'id': 'foreign',
      'farm_id': 'other',
      'code': 'KHO-001',
      'name': 'Other',
      'active': 1,
    });
    await expectLater(
      inventory.record(admin, move('foreign', 'foreign', 1)),
      throwsStateError,
    );
    await db.update(
      'inventory_warehouse_stock_v1',
      {'stock_units': 1},
      where: 'warehouse_id=?',
      whereArgs: ['a'],
    );
    await expectLater(SqliteWarehouseStock.validate(db), throwsStateError);
  });
  test('failed warehouse creation rolls its automatic sequence back', () async {
    await inventory.createWarehouse(admin, 'a', 'A');
    await expectLater(
      inventory.createWarehouse(admin, 'duplicate', 'A'),
      throwsA(isA<DatabaseException>()),
    );
    await inventory.createWarehouse(admin, 'b', 'B');
    final b = (await inventory.warehouses(
      admin,
    )).singleWhere((w) => w.id == 'b');
    expect(b.code, 'KHO-002');
  });
  test(
    'department reads do not expose other workers or private fields to an editor',
    () async {
      live = actor(
        permissions: {
          PermissionCodes.employeeView,
          PermissionCodes.employeeEdit,
        },
        scopes: {DataScope.department},
        departments: {'d1'},
      );
      final result = await people.employees(admin);
      expect(result.map((e) => e.workerId), ['w1']);
      expect(result.single.profile!.details.containsKey('identityNo'), isFalse);
      await people.saveProfile(
        admin,
        EmployeeProfile(
          workerId: 'w1',
          farmId: 'f',
          departmentId: 'd1',
          details: {'position': 'Updated'},
          revision: 1,
        ),
      );
      final stored = (await db.query(
        'personnel_profiles_v1',
        where: 'worker_id=?',
        whereArgs: ['w1'],
      )).single;
      expect(
        jsonDecode(stored['profile_json']! as String)['identityNo'],
        'private-w1',
      );
      await expectLater(
        people.saveProfile(
          admin,
          EmployeeProfile(
            workerId: 'w2',
            farmId: 'f',
            departmentId: 'd1',
            details: {},
            revision: 1,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        people.saveProfile(
          admin,
          EmployeeProfile(
            workerId: 'w1',
            farmId: 'f',
            departmentId: 'd2',
            details: {},
            revision: 2,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'private view is independent of edit and is checked for each department',
    () async {
      live = actor(
        permissions: {
          PermissionCodes.employeeView,
          PermissionCodes.employeeSensitiveView,
        },
        departments: {'d1'},
        overrides: {
          PermissionCodes.employeeSensitiveView: {DataScope.department},
        },
      );
      final list = await people.employees(admin);
      expect(list.length, 2);
      expect(
        list
            .singleWhere((e) => e.workerId == 'w1')
            .profile!
            .details['identityNo'],
        'private-w1',
      );
      expect(
        list
            .singleWhere((e) => e.workerId == 'w2')
            .profile!
            .details
            .containsKey('identityNo'),
        isFalse,
      );
      expect(
        () => people.saveProfile(
          admin,
          EmployeeProfile(
            workerId: 'w1',
            farmId: 'f',
            departmentId: 'd1',
            details: {},
            revision: 1,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'private data cannot be overwritten by a scoped editor without explicit private view',
    () async {
      live = actor(
        permissions: {
          PermissionCodes.employeeView,
          PermissionCodes.employeeEdit,
        },
        scopes: {DataScope.department},
        departments: {'d1'},
      );
      await expectLater(
        () => people.saveProfile(
          admin,
          EmployeeProfile(
            workerId: 'w1',
            farmId: 'f',
            departmentId: 'd1',
            details: {'bankAccount': 'forged'},
            revision: 1,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'machine view/log is limited to assigned identities and canonical approval cannot be spoofed',
    () async {
      live = actor(scopes: {DataScope.assignedMachines}, machines: {'m1'});
      expect((await machines.machines(admin)).map((m) => m.id), ['m1']);
      expect((await machines.runs(admin)).map((r) => r.value.id), ['run-m1']);
      await machines.profile(
        admin,
        const MachineCard('m1', 'm1', 'm1', true, {}, 1),
        {'meterUnit': 'hour', 'notes': 'ok'},
      );
      await expectLater(
        machines.profile(
          admin,
          const MachineCard('m2', 'm1', 'spoof', true, {}, 1),
          {'meterUnit': 'hour'},
        ),
        throwsStateError,
      );
      await expectLater(
        machines.approveRun(
          admin,
          MachineRecord(run('run-m2', 'm1'), 'draft', 0),
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'machine_runs_v1',
          where: 'id=?',
          whereArgs: ['run-m2'],
        )).single['status'],
        'draft',
      );
    },
  );
  test(
    'machine financial read grants redact rows individually and export is an intersection',
    () async {
      await db.update(
        'machine_runs_v1',
        {'amount': '100', 'currency': 'LAK'},
        where: 'farm_id=?',
        whereArgs: ['f'],
      );
      live = actor(
        machines: {'m1'},
        overrides: {
          PermissionCodes.financeView: {DataScope.assignedMachines},
          PermissionCodes.dataExport: {DataScope.assignedMachines},
        },
      );
      final rows = await machines.runs(admin);
      expect(rows.length, 2);
      expect(rows.singleWhere((r) => r.value.machineId == 'm1').amount, '100');
      expect(rows.singleWhere((r) => r.value.machineId == 'm2').amount, isNull);
      expect(
        (await machines.exporting(admin).machines(admin)).map((r) => r.id),
        ['m1'],
      );
    },
  );
  test(
    'personnel export intersects export scopes and never includes another department',
    () async {
      live = actor(
        departments: {'d1'},
        overrides: {
          PermissionCodes.dataExport: {DataScope.department},
        },
      );
      expect((await people.employees(admin)).length, 2);
      expect(
        (await people.exporting(admin).employees(admin)).map((r) => r.workerId),
        ['w1'],
      );
    },
  );
  test(
    'scope changes during a read discard its result even when the permission still exists',
    () async {
      live = actor(scopes: {DataScope.assignedMachines}, machines: {'m1'});
      final pending = Completer<int>();
      final guard = LiveAuthorization(() => live);
      final result = guard.readScoped(admin, [
        PermissionCodes.machineView,
      ], () => pending.future);
      live = actor(scopes: {DataScope.assignedMachines}, machines: {'m2'});
      final assertion = expectLater(result, throwsStateError);
      pending.complete(1);
      await assertion;
    },
  );
  test(
    'assignment directory exposes only basic same-farm identities',
    () async {
      await seedStock();
      final choices = await SqliteOperationDirectory(
        db,
        LiveAuthorization(() => live),
      ).load(admin);
      expect(choices['machineIds']!.keys.toSet(), {'m1', 'm2'});
      expect(choices['departmentIds']!.keys.toSet(), {'d1', 'd2'});
      expect(choices['warehouseIds']!.keys, containsAll(['a', 'b']));
      expect(choices.toString(), isNot(contains('private-')));
    },
  );
  test(
    'role policy keeps warehouse and machine assignments narrow and gives HR a distinct private permission',
    () {
      final warehouse = CompanyAccessProfile(
        userId: 'u',
        membershipId: 'm',
        farmId: 'f',
        roles: [RoleAssignment(CompanyRole.warehouseKeeper)],
        warehouseIds: {'a'},
      ).subject(now: DateTime.now());
      expect(warehouse.permissionScopes[PermissionCodes.inventoryView], {
        DataScope.assignedWarehouses,
      });
      expect(
        CompanyRolePolicy.permissions(CompanyRole.hrOfficer),
        contains(PermissionCodes.employeeSensitiveView),
      );
      expect(
        CompanyRolePolicy.permissions(CompanyRole.machineOperator),
        isNot(contains(PermissionCodes.employeeSensitiveView)),
      );
    },
  );
  test(
    'existing fractional stock migrates once to the default warehouse without changing history',
    () async {
      final old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await old.execute(
          'CREATE TABLE inventory_items_v2(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,stock_units INTEGER NOT NULL)',
        );
        await old.execute(
          'CREATE TABLE inventory_movements_v2(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,item_id TEXT NOT NULL,kind TEXT NOT NULL,quantity_units INTEGER NOT NULL,occurred_at TEXT)',
        );
        await old.insert('inventory_items_v2', {
          'id': 'legacy',
          'farm_id': 'f',
          'stock_units': 5500000,
        });
        await old.insert('inventory_movements_v2', {
          'id': 'historic',
          'farm_id': 'f',
          'item_id': 'legacy',
          'kind': 'receipt',
          'quantity_units': 5500000,
        });
        await SqliteWarehouseStock.createSchema(old);
        await SqliteWarehouseStock.createSchema(old);
        final rows = await old.query('inventory_warehouse_stock_v1');
        expect(rows.length, 1);
        expect(rows.single['stock_units'], 5500000);
        expect(
          (await old.query('inventory_movements_v2')).single['warehouse_id'],
          'warehouse:default:f',
        );
        await SqliteWarehouseStock.validate(old);
      } finally {
        await old.close();
      }
    },
  );
  test('failed warehouse migration rolls DDL and backfill back together', () async {
    final old = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await old.execute(
        'CREATE TABLE inventory_items_v2(id TEXT PRIMARY KEY,farm_id TEXT,stock_units INTEGER)',
      );
      await old.execute(
        'CREATE TABLE inventory_movements_v2(id TEXT PRIMARY KEY,farm_id TEXT,item_id TEXT,kind TEXT,quantity_units INTEGER,occurred_at TEXT)',
      );
      await old.insert('inventory_items_v2', {
        'id': 'broken',
        'farm_id': 'f',
        'stock_units': -1,
      });
      await expectLater(
        SqliteWarehouseStock.createSchema(old),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await old.rawQuery(
          'PRAGMA table_info(inventory_movements_v2)',
        )).any((c) => c['name'] == 'warehouse_id'),
        isFalse,
      );
      expect(
        await old.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='inventory_warehouses_v1'",
        ),
        isEmpty,
      );
    } finally {
      await old.close();
    }
  });
  test(
    'tampered transfer pair fails reconciliation even if farm total still matches',
    () async {
      await seedStock();
      await inventory.transfer(
        admin,
        id: 'pair',
        itemId: 'item',
        sourceId: 'a',
        destinationId: 'b',
        quantity: 1,
        at: at,
      );
      await db.update(
        'inventory_movements_v2',
        {'transfer_id': null},
        where: 'id=?',
        whereArgs: ['transfer:pair:in'],
      );
      await expectLater(SqliteWarehouseStock.validate(db), throwsStateError);
    },
  );
  test('SQL scope values cannot inject another machine into a read', () async {
    live = actor(
      scopes: {DataScope.assignedMachines},
      machines: {"m1') OR 1=1 --"},
    );
    expect(await machines.machines(admin), isEmpty);
    expect(await machines.runs(admin), isEmpty);
  });
  test(
    'department pay rates are filtered in SQL and cannot be created outside the assigned department',
    () async {
      PayRate rate(String worker) => PayRate(
        id: 'rate-$worker',
        farmId: 'f',
        workerId: worker,
        effectiveOn: '2026-10-01',
        basis: PayBasis.daily,
        rate: '80000',
        currency: 'LAK',
        rounding: MoneyRounding.halfUp,
        moneyScale: 0,
      );
      await people.createRate(admin, rate('w1'));
      await people.createRate(admin, rate('w2'));
      live = actor(scopes: {DataScope.department}, departments: {'d1'});
      expect((await people.rates(admin)).map((r) => r.workerId), ['w1']);
      await expectLater(people.createRate(admin, rate('w2')), throwsStateError);
    },
  );
  test(
    'failed department creation preserves its generated code sequence',
    () async {
      await expectLater(
        people.createDepartment(
          admin,
          const PersonnelDepartment('duplicate', 'Bộ phận A'),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await people.createDepartment(
        admin,
        const PersonnelDepartment('d3', 'Bộ phận C'),
      );
      final departments = await people.departments(admin);
      expect(departments.singleWhere((d) => d.id == 'd3').code, 'BP-003');
    },
  );
}
