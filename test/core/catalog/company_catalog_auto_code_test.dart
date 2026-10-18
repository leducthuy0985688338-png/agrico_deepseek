import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
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

  Future<void> create(CatalogEntry entry) => admin.save(
    entry,
    expectedRevision: null,
    reason: 'Approved catalog entry',
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await SqliteCompanyCatalog.createSchema(db);
    await SqliteInventoryRepository.createSchema(db);
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

  test('concurrent new entries receive distinct sequential codes', () async {
    await Future.wait([
      create(item('unit-1', CatalogKind.unit, 'Kilogram')),
      create(item('unit-2', CatalogKind.unit, 'Litre')),
      create(item('unit-3', CatalogKind.unit, 'Bag')),
    ]);
    final entries = await admin.entries();
    expect(
      entries.map((e) => e.code).toSet(),
      {'DVT-000001', 'DVT-000002', 'DVT-000003'},
    );
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
    'existing manual codes are respected when allocating next code',
    () async {
      await create(
        item('old', CatalogKind.unit, 'Old unit', code: 'DVT-000099'),
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
