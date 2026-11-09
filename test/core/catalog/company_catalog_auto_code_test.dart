import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_repository.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CompanyCatalogService admin;
  late SqliteCompanyCatalog repo;
  final now = DateTime.utc(2026, 10, 16);

  CatalogEntry item(
    String id,
    CatalogKind kind,
    String name, {
    String farm = 'farm',
    String? unit,
    String code = '',
  }) => CatalogEntry(
    id: id,
    farmId: farm,
    kind: kind,
    code: code,
    name: name,
    unitId: unit,
  );

  Future<void> create(CatalogEntry entry) =>
      admin.create(entry, reason: 'Approved catalog entry');

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await SqliteCompanyCatalog.createSchema(db);
    await SqliteInventoryRepository.createSchema(db);
    await SqliteParcelWorkRepository.createSchema(db);
    repo = SqliteCompanyCatalog(db);
    admin = CompanyCatalogService(
      repository: repo,
      subject: AuthorizationSubject(
        userId: 'admin',
        membershipId: 'admin',
        farmId: 'farm',
        permissionCodes: {
          PermissionCodes.catalogView,
          PermissionCodes.catalogManage,
        },
        dataScopes: {DataScope.allFarm},
        validUntil: DateTime.utc(2026, 10, 20),
      ),
      clock: () => now,
    );
  });
  tearDown(() async => db.close());

  test(
    'service allocates unit and material codes in separate sequences',
    () async {
      await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
      await create(item('unit-2', CatalogKind.unit, 'Litre'));
      await create(
        item('material-1', CatalogKind.material, 'Fertilizer', unit: 'unit-1'),
      );
      final entries = await admin.entries();
      expect(entries.firstWhere((e) => e.id == 'unit-1').code, 'DVT-000001');
      expect(entries.firstWhere((e) => e.id == 'unit-2').code, 'DVT-000002');
      expect(entries.firstWhere((e) => e.id == 'material-1').code, 'VT-000001');
    },
  );

  test(
    'unit rename updates material projection without changing stock or movements',
    () async {
      await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
      await create(
        item('material-1', CatalogKind.material, 'Fertilizer', unit: 'unit-1'),
      );
      final inventory = SqliteInventoryRepository(db);
      await inventory.register(
        const InventoryItem(
          id: 'material-1',
          farmId: 'farm',
          code: 'VT-000001',
          name: 'Fertilizer',
          unit: 'Kilogram',
          unitPrice: 25,
          supplier: 'Supplier',
        ),
      );
      await inventory.record(
        InventoryMovement(
          id: 'receipt-1',
          farmId: 'farm',
          itemId: 'material-1',
          kind: InventoryMovementKind.receipt,
          quantity: 8,
          occurredAt: DateTime.utc(2026, 10, 18),
        ),
      );
      final unit = (await admin.entries()).firstWhere((e) => e.id == 'unit-1');
      await admin.save(
        item('unit-1', CatalogKind.unit, 'Kilogram renamed', code: unit.code),
        expectedRevision: unit.revision,
        reason: 'Rename unit',
      );
      final rows = await inventory.listByFarm('farm');
      expect(rows, hasLength(1));
      expect(rows.single.unit, 'Kilogram renamed');
      expect(rows.single.stock, 8);
      expect(rows.single.unitPrice, 25);
      expect(rows.single.supplier, 'Supplier');
      expect(await inventory.movementsByFarm('farm'), hasLength(1));
      expect(
        (await admin.entries()).firstWhere((e) => e.id == 'material-1').unitId,
        'unit-1',
      );
    },
  );

  test(
    'service create rejects caller-supplied code and allocates system code',
    () async {
      expect(
        () => admin.create(
          item('manual', CatalogKind.unit, 'Manual unit', code: 'CUSTOM'),
          reason: 'New unit',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await admin.entries(), isEmpty);
      await admin.create(
        item('generated', CatalogKind.unit, 'Generated unit'),
        reason: 'New unit',
      );
      expect((await admin.entries()).single.code, 'DVT-000001');
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(1));
    },
  );

  test('editing preserves generated code and rejects stale revision', () async {
    await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
    final original = (await admin.entries()).single;
    expect(original.code, 'DVT-000001');
    await admin.save(
      item('unit-1', CatalogKind.unit, 'Kilogram updated', code: original.code),
      expectedRevision: original.revision,
      reason: 'Rename unit',
    );
    final updated = (await admin.entries()).single;
    expect(updated.code, original.code);
    expect(updated.name, 'Kilogram updated');
    expect(updated.revision, original.revision + 1);
    await expectLater(
      admin.save(
        item('unit-1', CatalogKind.unit, 'Stale edit', code: original.code),
        expectedRevision: original.revision,
        reason: 'Stale update',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    await expectLater(
      admin.save(
        item('unit-1', CatalogKind.unit, 'Changed code', code: 'CUSTOM'),
        expectedRevision: updated.revision,
        reason: 'Attempt code change',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect((await admin.entries()).single.code, 'DVT-000001');
    expect((await admin.entries()).single.name, 'Kilogram updated');
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
  });

  test('concurrent new entries receive distinct sequential codes', () async {
    await Future.wait([
      create(item('unit-1', CatalogKind.unit, 'Kilogram')),
      create(item('unit-2', CatalogKind.unit, 'Litre')),
      create(item('unit-3', CatalogKind.unit, 'Bag')),
    ]);
    final entries = await admin.entries();
    expect(entries.map((e) => e.code).toSet(), {
      'DVT-000001',
      'DVT-000002',
      'DVT-000003',
    });
    expect(entries, hasLength(3));
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(3));
  });

  test('failed insert rolls back allocated number and audit', () async {
    await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
    await expectLater(
      create(item('unit-2', CatalogKind.unit, 'Kilogram')),
      throwsA(isA<CatalogFailure>()),
    );
    await create(item('unit-3', CatalogKind.unit, 'Litre'));
    final entries = await admin.entries();
    expect(
      entries.map((e) => e.code),
      containsAll(['DVT-000001', 'DVT-000002']),
    );
    expect(entries, hasLength(2));
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
  });

  test(
    'failed unit creation does not advance unit or material sequences',
    () async {
      await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
      await expectLater(
        create(item('duplicate-unit', CatalogKind.unit, 'Kilogram')),
        throwsA(isA<CatalogFailure>()),
      );
      await create(
        item('material-1', CatalogKind.material, 'Fertilizer', unit: 'unit-1'),
      );
      await create(item('unit-2', CatalogKind.unit, 'Litre'));
      final entries = await admin.entries();
      expect(entries.firstWhere((e) => e.id == 'unit-1').code, 'DVT-000001');
      expect(entries.firstWhere((e) => e.id == 'unit-2').code, 'DVT-000002');
      expect(entries.firstWhere((e) => e.id == 'material-1').code, 'VT-000001');
      expect(entries, hasLength(3));
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(3));
    },
  );

  test(
    'failed dependent material creation preserves material sequence',
    () async {
      await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
      await expectLater(
        create(
          item(
            'bad-material',
            CatalogKind.material,
            'Invalid fertilizer',
            unit: 'missing-unit',
          ),
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(
        (await admin.entries()).where((e) => e.kind == CatalogKind.material),
        isEmpty,
      );
      await create(
        item('material-1', CatalogKind.material, 'Fertilizer', unit: 'unit-1'),
      );
      final entries = await admin.entries();
      expect(entries.firstWhere((e) => e.id == 'material-1').code, 'VT-000001');
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
    },
  );

  test(
    'historical import rejects empty code without allocating a number',
    () async {
      expect(
        () => repo.importHistoricalEntry(
          item('missing-code', CatalogKind.unit, 'Uncoded legacy unit'),
          actorUid: 'migration',
          reason: 'Import persisted catalog identity',
          occurredAt: now,
          authorize: () {},
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await admin.entries(), isEmpty);
      await create(item('first', CatalogKind.unit, 'First new unit'));
      expect((await admin.entries()).single.code, 'DVT-000001');
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(1));
    },
  );

  test(
    'historical import rejects duplicate code without changing catalog',
    () async {
      await repo.importHistoricalEntry(
        item('old', CatalogKind.unit, 'Legacy unit', code: 'DVT-000007'),
        actorUid: 'migration',
        reason: 'Import persisted catalog identity',
        occurredAt: now,
        authorize: () {},
      );
      await expectLater(
        repo.importHistoricalEntry(
          item(
            'collision',
            CatalogKind.unit,
            'Another legacy unit',
            code: 'DVT-000007',
          ),
          actorUid: 'migration',
          reason: 'Import persisted catalog identity',
          occurredAt: now,
          authorize: () {},
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await admin.entries(), hasLength(1));
      await create(item('new', CatalogKind.unit, 'New unit'));
      expect(
        (await admin.entries()).firstWhere((e) => e.id == 'new').code,
        'DVT-000008',
      );
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
    },
  );

  test(
    'historical import preserves code and advances automatic sequence',
    () async {
      await repo.importHistoricalEntry(
        item('historical', CatalogKind.unit, 'Legacy unit', code: 'DVT-000099'),
        actorUid: 'migration',
        reason: 'Import persisted catalog identity',
        occurredAt: now,
        authorize: () {},
      );
      await create(item('new', CatalogKind.unit, 'New unit'));
      final entries = await admin.entries();
      expect(
        entries.firstWhere((e) => e.id == 'historical').code,
        'DVT-000099',
      );
      expect(entries.firstWhere((e) => e.id == 'new').code, 'DVT-000100');
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
    },
  );

  test('lower historical code never rewinds an active sequence', () async {
    await create(item('first', CatalogKind.unit, 'First unit'));
    await create(item('second', CatalogKind.unit, 'Second unit'));
    await repo.importHistoricalEntry(
      item(
        'historical-low',
        CatalogKind.unit,
        'Legacy low unit',
        code: 'DVT-000000',
      ),
      actorUid: 'migration',
      reason: 'Import earlier historical unit',
      occurredAt: now,
      authorize: () {},
    );
    await create(item('third', CatalogKind.unit, 'Third unit'));
    final entries = await admin.entries();
    expect(entries.firstWhere((e) => e.id == 'first').code, 'DVT-000001');
    expect(entries.firstWhere((e) => e.id == 'second').code, 'DVT-000002');
    expect(
      entries.firstWhere((e) => e.id == 'historical-low').code,
      'DVT-000000',
    );
    expect(entries.firstWhere((e) => e.id == 'third').code, 'DVT-000003');
    expect(entries, hasLength(4));
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(4));
  });

  test('higher historical code advances an already started sequence', () async {
    await create(item('first', CatalogKind.unit, 'First unit'));
    await repo.importHistoricalEntry(
      item(
        'historical-high',
        CatalogKind.unit,
        'Legacy high unit',
        code: 'DVT-000250',
      ),
      actorUid: 'migration',
      reason: 'Import later historical unit',
      occurredAt: now,
      authorize: () {},
    );
    await create(item('after-high', CatalogKind.unit, 'Next unit'));
    final entries = await admin.entries();
    expect(entries.firstWhere((e) => e.id == 'first').code, 'DVT-000001');
    expect(
      entries.firstWhere((e) => e.id == 'historical-high').code,
      'DVT-000250',
    );
    expect(entries.firstWhere((e) => e.id == 'after-high').code, 'DVT-000251');
    expect(entries, hasLength(3));
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(3));
  });

  test(
    'existing manual codes are respected when allocating next code',
    () async {
      await repo.importHistoricalEntry(
        item('old', CatalogKind.unit, 'Old unit', code: 'DVT-000099'),
        actorUid: 'migration',
        reason: 'Adopt existing unit code',
        occurredAt: now,
        authorize: () {},
      );
      await create(item('new', CatalogKind.unit, 'New unit'));
      expect(
        (await admin.entries()).firstWhere((e) => e.id == 'new').code,
        'DVT-000100',
      );
    },
  );

  test(
    'different farms allocate independently and cannot be crossed',
    () async {
      await create(item('unit-1', CatalogKind.unit, 'Kilogram'));
      await expectLater(
        () => create(
          item('other', CatalogKind.unit, 'Litre', farm: 'other-farm'),
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await repo.entries('other-farm'), isEmpty);
    },
  );

  test(
    'work resource registration uses generated shared catalog identities',
    () async {
      final workSubject = AuthorizationSubject(
        userId: admin.subject.userId,
        membershipId: admin.subject.membershipId,
        farmId: admin.subject.farmId,
        permissionCodes: admin.subject.permissionCodes,
        dataScopes: admin.subject.dataScopes,
      );
      final work = ParcelWorkService(
        SqliteParcelWorkRepository(db),
        catalog: admin,
      );
      await work.register(
        workSubject,
        const WorkResource(
          id: 'machine-one',
          farmId: 'farm',
          kind: WorkResourceKind.machine,
          code: 'MANUAL',
          name: 'Tractor',
        ),
      );
      await work.register(
        workSubject,
        const WorkResource(
          id: 'worker-one',
          farmId: 'farm',
          kind: WorkResourceKind.worker,
          code: 'MANUAL',
          name: 'Operator',
        ),
      );
      final entries = await admin.entries();
      expect(
        entries.firstWhere((e) => e.id == 'machine-one').code,
        'MAY-000001',
      );
      expect(entries.firstWhere((e) => e.id == 'worker-one').code, 'NS-000001');
      final resources = await work.resources(workSubject);
      expect(
        resources.firstWhere((e) => e.id == 'machine-one').code,
        'MAY-000001',
      );
      expect(
        resources.firstWhere((e) => e.id == 'worker-one').code,
        'NS-000001',
      );
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
    },
  );

  test('all eleven catalog kinds use independent standard prefixes', () async {
    await create(item('unit', CatalogKind.unit, 'Kilogram'));
    final kinds = <CatalogKind, String>{
      CatalogKind.crop: 'CT',
      CatalogKind.machine: 'MAY',
      CatalogKind.worker: 'NS',
      CatalogKind.material: 'VT',
      CatalogKind.taskType: 'CV',
      CatalogKind.supplier: 'NCC',
      CatalogKind.incomeCategory: 'DMTHU',
      CatalogKind.expenseCategory: 'DMCHI',
      CatalogKind.customer: 'KH',
      CatalogKind.product: 'TP',
    };
    for (final kind in kinds.keys) {
      final unitId =
          kind == CatalogKind.crop ||
              kind == CatalogKind.material ||
              kind == CatalogKind.product
          ? 'unit'
          : null;
      await create(
        item('first-${kind.name}', kind, 'First ${kind.name}', unit: unitId),
      );
      await create(
        item('second-${kind.name}', kind, 'Second ${kind.name}', unit: unitId),
      );
    }
    final entries = await admin.entries();
    expect(entries.firstWhere((e) => e.id == 'unit').code, 'DVT-000001');
    for (final kind in kinds.keys) {
      final prefix = kinds[kind]!;
      expect(
        entries.firstWhere((e) => e.id == 'first-${kind.name}').code,
        '${prefix}-000001',
      );
      expect(
        entries.firstWhere((e) => e.id == 'second-${kind.name}').code,
        '${prefix}-000002',
      );
    }
    expect(entries, hasLength(21));
    expect(entries.map((e) => e.code).toSet(), hasLength(21));
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(21));
  });

  test(
    'failed create validation cannot consume a code or write audit',
    () async {
      await expectLater(
        () => admin.create(
          item('invalid', CatalogKind.unit, '  Untrimmed  '),
          reason: 'Attempt invalid creation',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => admin.create(
          item('invalid-material', CatalogKind.material, 'No unit'),
          reason: 'Attempt invalid material',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await admin.entries(), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
      await create(item('valid', CatalogKind.unit, 'Valid unit'));
      expect((await admin.entries()).single.code, 'DVT-000001');
    },
  );

  test('unauthorized service cannot allocate a code', () async {
    final staff = CompanyCatalogService(
      repository: repo,
      subject: AuthorizationSubject(
        userId: 'staff',
        membershipId: 'staff',
        farmId: 'farm',
        permissionCodes: {PermissionCodes.catalogView},
        dataScopes: {DataScope.allFarm},
        validUntil: DateTime.utc(2026, 10, 20),
      ),
      clock: () => now,
    );
    await expectLater(
      () => staff.save(
        item('unit-1', CatalogKind.unit, 'Kilogram'),
        expectedRevision: null,
        reason: 'Attempt',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await repo.entries('farm'), isEmpty);
  });
}
