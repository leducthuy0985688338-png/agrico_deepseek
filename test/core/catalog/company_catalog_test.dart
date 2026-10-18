import 'dart:convert';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_catalog_policy.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteCompanyCatalog repo;
  late CompanyCatalogService admin, worker;
  var now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject subject(
    String uid,
    Set<String> permissions, {
    String farm = 'farm',
    Set<DataScope> scopes = const {DataScope.allFarm},
  }) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: farm,
    permissionCodes: permissions,
    dataScopes: scopes,
    validUntil: DateTime.utc(2026, 10, 10),
  );
  CatalogEntry entry(
    String id,
    CatalogKind kind,
    String code,
    String name, {
    String farm = 'farm',
    String? unit,
    bool active = true,
  }) => CatalogEntry(
    id: id,
    farmId: farm,
    kind: kind,
    code: code,
    name: name,
    unitId: unit,
    active: active,
  );
  Future<void> save(CatalogEntry e, {int? revision}) =>
      admin.save(e, expectedRevision: revision, reason: 'Approved standard');
  setUp(() async {
    now = DateTime.utc(2026, 10, 3);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE parcel_work_resources (id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER,UNIQUE(farm_id,kind,code))',
    );
    await db.execute(
      'CREATE TABLE inventory_items_v2 (id TEXT PRIMARY KEY,farm_id TEXT,code TEXT,name TEXT,unit TEXT,unit_price REAL,supplier TEXT,stock INTEGER)',
    );
    await db.execute(
      'CREATE TABLE land_parcels (id TEXT PRIMARY KEY,farm_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE land_parcel_crops (id TEXT PRIMARY KEY,parcel_id TEXT,payload_json TEXT)',
    );
    await SqliteCompanyCatalog.createSchema(db);
    repo = SqliteCompanyCatalog(db);
    admin = CompanyCatalogService(
      repository: repo,
      subject: subject('admin', {
        PermissionCodes.catalogView,
        PermissionCodes.catalogManage,
        PermissionCodes.catalogRequest,
      }),
      clock: () => now,
    );
    worker = CompanyCatalogService(
      repository: repo,
      subject: subject('worker', {
        PermissionCodes.catalogView,
        PermissionCodes.catalogRequest,
        PermissionCodes.fieldEdit,
        PermissionCodes.inventoryManage,
      }),
      clock: () => now,
    );
  });
  test('approval creates entry and resolves request atomically', () async {
    await worker.request(
      id: 'direct',
      kind: CatalogKind.unit,
      code: 'DIRECT',
      name: 'Direct unit',
      reason: 'Needed',
    );
    await admin.resolve(
      'direct',
      createEntry: entry(
        'direct-unit',
        CatalogKind.unit,
        '',
        'Direct unit',
      ),
      reason: 'Approved',
    );
    expect((await admin.entries()).single.id, 'direct-unit');
    expect((await admin.entries()).single.code, 'DVT-000001');
    final request = (await admin.requests()).single;
    expect(request.status, 'approved');
    expect(request.entryId, 'direct-unit');
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(3));
  });
  test('approval rejects caller-supplied code without changing request', () async {
    await worker.request(
      id: 'manual-approval',
      kind: CatalogKind.unit,
      code: 'SUGGESTED',
      name: 'Proposed unit',
      reason: 'Needed',
    );
    expect(
      () => admin.resolve(
        'manual-approval',
        createEntry: entry('manual-unit', CatalogKind.unit, 'CUSTOM', 'Proposed unit'),
        reason: 'Attempt',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await admin.entries(), isEmpty);
    expect((await admin.requests()).single.status, 'pending');
    await admin.resolve(
      'manual-approval',
      createEntry: entry('approved-unit', CatalogKind.unit, '', 'Proposed unit'),
      reason: 'Approved',
    );
    expect((await admin.entries()).single.code, 'DVT-000001');
  });

  test('approved suggestion allocates the next system code atomically', () async {
    await save(entry('existing', CatalogKind.unit, '', 'Existing'));
    await worker.request(
      id: 'suggested-unit',
      kind: CatalogKind.unit,
      code: 'SUGGESTED',
      name: 'Suggested unit',
      reason: 'Needed',
    );
    await admin.resolve(
      'suggested-unit',
      createEntry: entry(
        'approved-unit',
        CatalogKind.unit,
        '',
        'Suggested unit',
      ),
      reason: 'Approved',
    );
    final entries = await admin.entries();
    expect(entries.firstWhere((e) => e.id == 'existing').code, 'DVT-000001');
    expect(entries.firstWhere((e) => e.id == 'approved-unit').code, 'DVT-000002');
    expect((await admin.requests()).single.status, 'approved');
  });

  test('failed approval does not consume an automatic catalog code', () async {
    await save(entry('existing', CatalogKind.unit, '', 'Existing'));
    await worker.request(
      id: 'duplicate-request',
      kind: CatalogKind.unit,
      code: 'DUP',
      name: 'Existing',
      reason: 'Requested duplicate',
    );
    await expectLater(
      admin.resolve(
        'duplicate-request',
        createEntry: entry('duplicate', CatalogKind.unit, '', 'Existing'),
        reason: 'Attempt',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect((await admin.requests()).single.status, 'pending');
    await save(entry('next', CatalogKind.unit, '', 'Next unit'));
    final entries = await admin.entries();
    expect(entries.firstWhere((e) => e.id == 'next').code, 'DVT-000002');
    expect(entries, hasLength(2));
  });

  test('duplicate creation rolls back and leaves request pending', () async {
    await save(entry('existing', CatalogKind.unit, 'DIRECT', 'Existing'));
    await worker.request(
      id: 'direct',
      kind: CatalogKind.unit,
      code: 'DIRECT',
      name: 'Direct unit',
      reason: 'Needed',
    );
    await expectLater(
      admin.resolve(
        'direct',
        createEntry: entry(
          'new-unit',
          CatalogKind.unit,
          'DIRECT',
          'Direct unit',
        ),
        reason: 'Approved',
      ),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.code,
          'code',
          'catalog.duplicate',
        ),
      ),
    );
    expect((await admin.entries()).single.id, 'existing');
    expect((await admin.requests()).single.status, 'pending');
    expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
  });
  test('self approval cannot create an entry', () async {
    await repo.request(
      CatalogRequest(
        id: 'self-direct',
        farmId: 'farm',
        actorUid: admin.subject.userId,
        kind: CatalogKind.unit,
        code: 'SELF',
        name: 'Self',
        reason: 'Needed',
        createdAt: now,
      ),
      authorize: () {},
    );
    await expectLater(
      admin.resolve(
        'self-direct',
        createEntry: entry('self-unit', CatalogKind.unit, 'SELF', 'Self'),
        reason: 'Approved',
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await admin.entries(), isEmpty);
    expect((await admin.requests()).single.status, 'pending');
  });
  tearDown(() async => db.close());
  test(
    'business editing never grants catalog writing, own suggestions do not create entries',
    () async {
      await expectLater(
        () => worker.save(
          entry('u', CatalogKind.unit, 'KG', 'kg'),
          expectedRevision: null,
          reason: 'try',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await repo.entries('farm'), isEmpty);
      await worker.request(
        id: 'req',
        kind: CatalogKind.unit,
        code: ' kg ',
        name: 'kg',
        reason: 'Need unit',
      );
      expect(await repo.entries('farm'), isEmpty);
      expect((await worker.requests()).single.status, 'pending');
    },
  );
  test(
    'explicit denied scope, inactive and expired sessions cannot manage or suggest',
    () async {
      final denied = CompanyCatalogService(
        repository: repo,
        subject: AuthorizationSubject(
          userId: 'd',
          membershipId: 'd',
          farmId: 'farm',
          permissionCodes: {PermissionCodes.catalogManage},
          dataScopes: {DataScope.allFarm},
          permissionScopes: {PermissionCodes.catalogManage: {}},
        ),
        clock: () => now,
      );
      expect(denied.canManage, isFalse);
      now = DateTime.utc(2026, 10, 11);
      expect(admin.canManage, isFalse);
      expect(worker.canRequest, isFalse);
      await expectLater(
        () => worker.request(
          id: 'r',
          kind: CatalogKind.unit,
          code: 'KG',
          name: 'kg',
          reason: 'why',
        ),
        throwsA(isA<CatalogFailure>()),
      );
    },
  );
  test(
    'farm separation, normalization duplicates and immutable codes',
    () async {
      await save(entry('u', CatalogKind.unit, 'KG', 'kg'));
      await expectLater(
        () => save(entry('u2', CatalogKind.unit, 'KILO', 'KG')),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => save(entry('u2', CatalogKind.unit, 'KG', 'kilogram')),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => save(entry('u', CatalogKind.unit, 'NEW', 'kg'), revision: 1),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => save(entry('cross', CatalogKind.unit, 'KG', 'kg', farm: 'other')),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await repo.entries('other'), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(1));
    },
  );
  test(
    'stale revision and expiry during transaction roll back entry projection and audit',
    () async {
      await save(entry('m', CatalogKind.machine, 'M01', 'Machine'));
      await save(
        entry('m', CatalogKind.machine, 'M01', 'New name'),
        revision: 1,
      );
      await expectLater(
        () =>
            save(entry('m', CatalogKind.machine, 'M01', 'Stale'), revision: 1),
        throwsA(isA<CatalogFailure>()),
      );
      var calls = 0;
      await expectLater(
        repo.save(
          entry('failed', CatalogKind.machine, 'M02', 'Rollback'),
          expectedRevision: null,
          actorUid: 'admin',
          reason: 'test',
          occurredAt: now,
          authorize: () {
            if (++calls == 2) throw const CatalogFailure('catalog.denied');
          },
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect((await repo.entries('farm')).single.name, 'New name');
      expect(await db.query('parcel_work_resources'), hasLength(1));
      expect(await db.query(SqliteCompanyCatalog.auditTable), hasLength(2));
    },
  );
  test(
    'active farm unit required, material unit immutable, unit in use protected',
    () async {
      await save(entry('u', CatalogKind.unit, 'KG', 'kg'));
      await save(entry('c', CatalogKind.crop, 'PEANUT', 'Lạc', unit: 'u'));
      await expectLater(
        () => save(entry('u', CatalogKind.unit, 'KG', 'kilogram'), revision: 1),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => save(
          entry('u', CatalogKind.unit, 'KG', 'kg', active: false),
          revision: 1,
        ),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => save(
          entry('c2', CatalogKind.crop, 'MAIZE', 'Ngô', unit: 'missing'),
        ),
        throwsA(isA<CatalogFailure>()),
      );
      await save(
        entry('m', CatalogKind.material, 'FERT', 'Phân bón', unit: 'u'),
      );
      await db.update(
        'inventory_items_v2',
        {'stock': 25},
        where: 'id=?',
        whereArgs: ['m'],
      );
      await save(
        entry('m', CatalogKind.material, 'FERT', 'Phân bón mới', unit: 'u'),
        revision: 1,
      );
      expect((await db.query('inventory_items_v2')).single['stock'], 25);
      await save(entry('u2', CatalogKind.unit, 'L', 'lít'));
      await expectLater(
        () => save(
          entry('m', CatalogKind.material, 'FERT', 'Phân bón mới', unit: 'u2'),
          revision: 2,
        ),
        throwsA(isA<CatalogFailure>()),
      );
    },
  );
  test(
    'requests visible to owner or manager only, approve active entry atomically, no self approval',
    () async {
      await worker.request(
        id: 'req',
        kind: CatalogKind.unit,
        code: 'KG',
        name: 'kg',
        reason: 'Need unit',
      );
      final other = CompanyCatalogService(
        repository: repo,
        subject: subject(
          'other',
          {PermissionCodes.catalogRequest},
          scopes: {DataScope.own},
        ),
        clock: () => now,
      );
      expect(await other.requests(), isEmpty);
      await save(entry('u', CatalogKind.unit, 'KG', 'kg'));
      await expectLater(
        () => worker.resolve('req', entryId: 'u', reason: 'try'),
        throwsA(isA<CatalogFailure>()),
      );
      await admin.resolve('req', entryId: 'u', reason: 'Available');
      expect((await worker.requests()).single.entryId, 'u');
      await expectLater(
        () => admin.resolve('req', reason: 'again'),
        throwsA(isA<CatalogFailure>()),
      );
      await admin.request(
        id: 'self',
        kind: CatalogKind.unit,
        code: 'KG',
        name: 'kg',
        reason: 'mine',
      );
      await expectLater(
        () => admin.resolve('self', entryId: 'u', reason: 'mine'),
        throwsA(isA<CatalogFailure>()),
      );
      expect(
        (await admin.requests()).singleWhere((r) => r.id == 'self').status,
        'pending',
      );
    },
  );
  test(
    'adoption is one-time and preserves existing IDs; inactive entries not resurrected',
    () async {
      await db.insert('parcel_work_resources', {
        'id': 'old',
        'farm_id': 'farm',
        'kind': 'machine',
        'code': 'M01',
        'name': 'Old machine',
        'active': 1,
      });
      await repo.adoptExisting('farm');
      final adopted = (await repo.entries('farm')).single;
      expect(adopted.id, 'old');
      await save(
        entry('old', CatalogKind.machine, 'M01', 'Renamed', active: false),
        revision: 1,
      );
      await repo.adoptExisting('farm');
      expect((await repo.entries('farm')).single.active, isFalse);
      expect((await db.query('parcel_work_resources')).single['active'], 0);
    },
  );
  test(
    'crop selection checked in same business transaction; unchanged historical values retained',
    () async {
      await db.insert('land_parcels', {'id': 'p', 'farm_id': 'farm'});
      await save(entry('u', CatalogKind.unit, 'TREE', 'cây'));
      await save(entry('c', CatalogKind.crop, 'PEANUT', 'Lạc', unit: 'u'));
      await SqliteCatalogPolicy.crop(
        db,
        id: 'new',
        parcelId: 'p',
        type: 'Lạc',
        unit: 'cây',
      );
      await expectLater(
        SqliteCatalogPolicy.crop(
          db,
          id: 'new',
          parcelId: 'p',
          type: 'Free text',
          unit: 'cây',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      await db.insert('land_parcel_crops', {
        'id': 'old',
        'parcel_id': 'p',
        'payload_json': jsonEncode({'cropType': 'Lạc', 'unit': 'cây'}),
      });
      await save(
        entry('c', CatalogKind.crop, 'PEANUT', 'Lạc', unit: 'u', active: false),
        revision: 1,
      );
      await SqliteCatalogPolicy.crop(
        db,
        id: 'old',
        parcelId: 'p',
        type: 'Lạc',
        unit: 'cây',
      );
      await expectLater(
        SqliteCatalogPolicy.crop(
          db,
          id: 'new',
          parcelId: 'p',
          type: 'Lạc',
          unit: 'cây',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        db.transaction((tx) async {
          await tx.insert('land_parcels', {
            'id': 'rollback',
            'farm_id': 'farm',
          });
          await SqliteCatalogPolicy.crop(
            tx,
            id: 'new',
            parcelId: 'rollback',
            type: 'Lạc',
            unit: 'cây',
          );
        }),
        throwsA(isA<CatalogFailure>()),
      );
      expect(
        await db.query('land_parcels', where: 'id=?', whereArgs: ['rollback']),
        isEmpty,
      );
    },
  );
  test(
    'invalid input cannot persist and suggestions cannot auto-approve',
    () async {
      await expectLater(
        () => save(entry('u', CatalogKind.unit, 'bad code', 'kg')),
        throwsA(isA<CatalogFailure>()),
      );
      await expectLater(
        () => admin.save(
          entry('u', CatalogKind.unit, 'KG', 'kg'),
          expectedRevision: null,
          reason: ' ',
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
}
