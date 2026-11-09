import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_projection.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject actor(
    String uid, {
    bool manager = true,
    bool active = true,
    String farm = 'farm',
  }) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: farm,
    active: active,
    validUntil: now.add(const Duration(days: 7)),
    permissionCodes: {
      PermissionCodes.cloudSync,
      PermissionCodes.catalogView,
      PermissionCodes.catalogRequest,
      if (manager) PermissionCodes.catalogManage,
    },
    dataScopes: {DataScope.allFarm},
  );
  Map<String, Object?> payload(
    String id, {
    String kind = 'unit',
    String? unit,
    String name = 'Kilogram',
    bool active = true,
    int revision = 1,
    String farm = 'farm',
  }) => {
    'id': id,
    'farm_id': farm,
    'kind': kind,
    'code': id.toUpperCase(),
    'name': name,
    'name_key': SqliteCompanyCatalog.nameKey(name),
    'unit_id': unit,
    'active': active ? 1 : 0,
    'revision': revision,
  };
  late Database db;
  late CatalogSyncProjection projection;
  AuthorizationSubject? subject;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute(
      'CREATE TABLE parcel_work_resources (id TEXT PRIMARY KEY,farm_id TEXT,kind TEXT,code TEXT,name TEXT,active INTEGER)',
    );
    await db.execute(
      'CREATE TABLE inventory_items_v2 (id TEXT PRIMARY KEY,farm_id TEXT,code TEXT,name TEXT,unit TEXT,unit_price REAL,supplier TEXT,stock INTEGER)',
    );
    await SqliteCompanyCatalog.createSchema(db);
    subject = actor('admin');
    projection = CatalogSyncProjection(
      database: db,
      currentSubject: () => subject,
      clock: () => now,
    );
  });
  tearDown(() => db.close());
  Future<void> stage(
    Map<String, Object?> p, {
    int version = 1,
    String entity = 'entry',
    String? op,
    String reader = 'admin',
  }) => CatalogSyncInbox(db).stage(
    [
      CatalogRemoteRecord(
        farmId: p['farm_id'] as String,
        entity: entity,
        targetId: p['id'] as String,
        version: version,
        operationId: op ?? 'op-$version-${p['id']}',
        payload: p,
      ),
    ],
    farmId: 'farm',
    readerUid: reader,
    allRequests: true,
    authorize: () {},
  );
  Future<Map<String, Object?>> local(String id) async => (await db.query(
    SqliteCompanyCatalog.entriesTable,
    where: 'id=?',
    whereArgs: [id],
  )).single;
  Future<void> dirty(String id, {String uid = 'other'}) => db.transaction(
    (tx) => CatalogSyncJournal.append(
      tx,
      farmId: 'farm',
      actorUid: uid,
      entity: 'entry',
      targetId: id,
      payload: payload(id),
      reason: 'Offline',
      occurredAt: now,
    ),
  );
  test(
    'clean master, shadow and receive audit commit without outgoing mutation',
    () async {
      await stage(payload('kg'));
      final result = await projection.apply();
      expect(result.applied, 1);
      expect((await local('kg'))['name'], 'Kilogram');
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        1,
      );
      expect(
        (await db.query(SqliteCompanyCatalog.auditTable)).single['action'],
        'remoteApply',
      );
    },
  );
  test(
    'same remote version is idempotent and local revision is independent',
    () async {
      await stage(payload('kg', revision: 20));
      await projection.apply();
      expect((await local('kg'))['revision'], 1);
      expect((await projection.apply()).unchanged, 1);
      expect((await db.query(SqliteCompanyCatalog.auditTable)).length, 1);
      await stage(payload('kg', name: 'Kilograms', revision: 40), version: 2);
      await projection.apply();
      expect((await local('kg'))['revision'], 2);
    },
  );
  test('units apply before crops even when IDs sort after crops', () async {
    await stage(payload('a', kind: 'crop', unit: 'z', name: 'Peanut'));
    await stage(payload('z'));
    final result = await projection.apply();
    expect(result.applied, 2);
    expect(result.conflicts, 0);
    expect((await local('a'))['unit_id'], 'z');
  });
  test(
    'missing unit remains a conflict and retries after dependency arrives',
    () async {
      await stage(payload('crop', kind: 'crop', unit: 'kg', name: 'Peanut'));
      expect((await projection.apply()).conflicts, 1);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      await stage(payload('kg'));
      expect((await projection.apply()).applied, 2);
      expect(await projection.conflicts(), isEmpty);
    },
  );
  test(
    'foreign actor pending edits are never overwritten or acknowledged',
    () async {
      await stage(payload('kg'));
      await projection.apply();
      await dirty('kg');
      await stage(payload('kg', name: 'Server name'), version: 2);
      expect((await projection.apply()).conflicts, 1);
      expect((await local('kg'))['name'], 'Kilogram');
      expect(
        (await db.query(CatalogSyncJournal.outbox)).single['state'],
        'pending',
      );
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        1,
      );
      expect(
        (await projection.conflicts()).single['failure'],
        'catalog.offlineEditConflict',
      );
    },
  );
  test('local changes without queue are detected against shadow', () async {
    await stage(payload('kg'));
    await projection.apply();
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'name': 'Local change'},
      where: 'id=?',
      whereArgs: ['kg'],
    );
    await stage(payload('kg', name: 'Remote'), version: 2);
    expect((await projection.apply()).conflicts, 1);
    expect((await local('kg'))['name'], 'Local change');
  });
  test(
    'existing unpublished catalog requires explicit reconciliation',
    () async {
      await db.insert(SqliteCompanyCatalog.entriesTable, payload('kg'));
      await stage(payload('kg', name: 'Remote'));
      expect((await projection.apply()).conflicts, 1);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    },
  );
  test(
    'same version forged content is never accepted even from corrupted staging',
    () async {
      await stage(payload('kg'));
      await projection.apply();
      await db.update(CatalogSyncJournal.inbox, {
        'payload_json': jsonEncode(payload('kg', name: 'Forged')),
      });
      expect((await projection.apply()).conflicts, 1);
      expect((await local('kg'))['name'], 'Kilogram');
    },
  );
  test(
    'duplicate code/name rolls back business shadow audit together',
    () async {
      await stage(payload('a'));
      await projection.apply();
      await stage(payload('b'));
      expect((await projection.apply()).conflicts, 1);
      expect((await db.query(SqliteCompanyCatalog.entriesTable)).length, 1);
      expect((await db.query(CatalogSyncJournal.shadow)).length, 1);
      expect((await db.query(SqliteCompanyCatalog.auditTable)).length, 1);
    },
  );
  test('unit rename with local references remains conflict', () async {
    await stage(payload('kg'));
    await stage(payload('crop', kind: 'crop', unit: 'kg', name: 'Peanut'));
    await projection.apply();
    await stage(payload('kg', name: 'Renamed'), version: 2);
    expect((await projection.apply()).conflicts, 1);
    expect((await local('kg'))['name'], 'Kilogram');
  });
  test('consumer retirement precedes unit retirement', () async {
    await stage(payload('kg'));
    await stage(payload('crop', kind: 'crop', unit: 'kg', name: 'Peanut'));
    await projection.apply();
    await stage(payload('kg', active: false), version: 2);
    await stage(
      payload('crop', kind: 'crop', unit: 'kg', name: 'Peanut', active: false),
      version: 2,
    );
    final result = await projection.apply();
    expect(result.conflicts, 0);
    expect(result.applied, 2);
    expect((await local('kg'))['active'], 0);
  });
  test(
    'material and machine projection reuse existing business tables',
    () async {
      await stage(payload('kg'));
      await stage(
        payload('m', kind: 'material', unit: 'kg', name: 'Fertilizer'),
      );
      await stage(payload('machine', kind: 'machine', name: 'Tractor'));
      await projection.apply();
      expect((await db.query('inventory_items_v2')).single['unit'], 'Kilogram');
      expect(
        (await db.query('parcel_work_resources')).single['name'],
        'Tractor',
      );
      await db.update('inventory_items_v2', {'stock': 15, 'unit_price': 7});
      await stage(
        payload('m', kind: 'material', unit: 'kg', name: 'New fertilizer'),
        version: 2,
      );
      await projection.apply();
      final item = (await db.query('inventory_items_v2')).single;
      expect(item['stock'], 15);
      expect(item['unit_price'], 7);
    },
  );
  test('material unit and master identity changes remain conflicts', () async {
    await stage(payload('kg'));
    await stage(payload('litre', name: 'Litre'));
    await stage(payload('m', kind: 'material', unit: 'kg', name: 'Material'));
    await projection.apply();
    await stage(
      payload('m', kind: 'material', unit: 'litre', name: 'Material'),
      version: 2,
    );
    expect((await projection.apply()).conflicts, 1);
    expect((await local('m'))['unit_id'], 'kg');
  });
  test(
    'foreign farm ID collision never exposes foreign payload in conflict',
    () async {
      await db.insert(
        SqliteCompanyCatalog.entriesTable,
        payload('kg', farm: 'other', name: 'Private'),
      );
      await stage(payload('kg'));
      expect((await projection.apply()).conflicts, 1);
      expect((await projection.conflicts()).single['local_json'], isNull);
      expect((await local('kg'))['farm_id'], 'other');
    },
  );
  test(
    'legacy resource collision cannot overwrite unpublished business data',
    () async {
      await db.insert('parcel_work_resources', {
        'id': 'm',
        'farm_id': 'farm',
        'kind': 'machine',
        'code': 'M',
        'name': 'Local',
        'active': 1,
      });
      await stage(payload('m', kind: 'machine', name: 'Remote'));
      expect((await projection.apply()).conflicts, 1);
      expect((await db.query('parcel_work_resources')).single['name'], 'Local');
      expect(await db.query(SqliteCompanyCatalog.entriesTable), isEmpty);
    },
  );
  test('expired session disposal and account changes cannot apply', () async {
    await stage(payload('kg'));
    subject = actor('admin', active: false);
    await expectLater(projection.apply(), throwsA(isA<CatalogFailure>()));
    subject = actor('other');
    expect((await projection.apply()).applied, 0);
    subject = actor('admin');
    projection.dispose();
    await expectLater(projection.apply(), throwsA(isA<CatalogFailure>()));
    expect(await db.query(SqliteCompanyCatalog.entriesTable), isEmpty);
  });
  test(
    'apply retains restore barrier and bounded runs report incomplete',
    () async {
      await db.insert(CatalogSyncJournal.device, {
        'farm_id': 'farm',
        'restore_blocked': 1,
      });
      await stage(payload('a'));
      await stage(payload('b', name: 'Litre'));
      final result = await projection.apply(maxRecords: 1);
      expect(result.complete, isFalse);
      expect(
        (await db.query(CatalogSyncJournal.device)).single['restore_blocked'],
        1,
      );
    },
  );
  test(
    'request projection enforces owner visibility and dependencies',
    () async {
      final p = <String, Object?>{
        'id': 'req',
        'farm_id': 'farm',
        'actor_uid': 'staff',
        'kind': 'unit',
        'code': 'KG',
        'name': 'Kilogram',
        'reason': 'Needed',
        'created_at': now.toIso8601String(),
        'status': 'pending',
      };
      await stage(p, entity: 'request', reader: 'staff');
      subject = actor('staff', manager: false);
      expect((await projection.apply()).applied, 1);
      expect(
        (await db.query(
          SqliteCompanyCatalog.requestsTable,
        )).single['actor_uid'],
        'staff',
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      final approved = {
        ...p,
        'status': 'approved',
        'entry_id': 'kg',
        'resolved_by': 'admin',
        'resolved_at': now.toIso8601String(),
        'resolution': 'Approved',
      };
      await stage(approved, entity: 'request', reader: 'staff', version: 2);
      expect((await projection.apply()).conflicts, 1);
      await stage(payload('kg'), reader: 'staff');
      expect((await projection.apply()).applied, 2);
      expect(
        (await db.query(SqliteCompanyCatalog.requestsTable)).single['status'],
        'approved',
      );
    },
  );
  test(
    'permission change at transaction end rolls back business shadow and audit',
    () async {
      await stage(payload('kg'));
      var reads = 0;
      projection = CatalogSyncProjection(
        database: db,
        clock: () => now,
        currentSubject: () {
          reads++;
          return actor('admin', active: reads < 4);
        },
      );
      await expectLater(projection.apply(), throwsA(isA<CatalogFailure>()));
      expect(await db.query(SqliteCompanyCatalog.entriesTable), isEmpty);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
  test(
    'approved suggestion retains reference to subsequently retired master',
    () async {
      await stage(payload('kg', active: false));
      await stage({
        'id': 'req',
        'farm_id': 'farm',
        'actor_uid': 'staff',
        'kind': 'unit',
        'code': 'KG',
        'name': 'Kilogram',
        'reason': 'Needed',
        'created_at': now.toIso8601String(),
        'status': 'approved',
        'entry_id': 'kg',
        'resolved_by': 'admin',
        'resolved_at': now.toIso8601String(),
        'resolution': 'Approved',
      }, entity: 'request');
      final result = await projection.apply();
      expect(result.applied, 2);
      expect(result.conflicts, 0);
      expect(
        (await db.query(SqliteCompanyCatalog.requestsTable)).single['entry_id'],
        'kg',
      );
    },
  );
  test(
    'unchanged remote baseline preserves ordinary pending offline edits without new conflict',
    () async {
      await stage(payload('kg'));
      await projection.apply();
      await dirty('kg');
      await db.update(
        SqliteCompanyCatalog.entriesTable,
        {'name': 'Offline'},
        where: 'id=?',
        whereArgs: ['kg'],
      );
      final result = await projection.apply();
      expect(result.conflicts, 0);
      expect(result.unchanged, 1);
      expect((await local('kg'))['name'], 'Offline');
      expect(
        (await db.query(CatalogSyncJournal.outbox)).single['state'],
        'pending',
      );
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        1,
      );
    },
  );
  test(
    'customer and product sync preserve warehouse projection and immutable unit',
    () async {
      await stage(payload('kg'));
      await stage(
        payload('product', kind: 'product', unit: 'kg', name: 'Peanut'),
      );
      await stage(payload('customer', kind: 'customer', name: 'Buyer'));
      expect((await projection.apply()).applied, 3);
      expect((await local('customer'))['kind'], 'customer');
      await db.update('inventory_items_v2', {
        'stock': 7,
      }, where: "id='product'");
      await stage(
        payload('product', kind: 'product', unit: 'kg', name: 'Peanut renamed'),
        version: 2,
      );
      expect((await projection.apply()).applied, 1);
      final product = (await db.query(
        'inventory_items_v2',
        where: "id='product'",
      )).single;
      expect(product['unit'], 'Kilogram');
      expect(product['name'], 'Peanut renamed');
      expect(product['stock'], 7);
      await stage(payload('other', name: 'Hectare'));
      await projection.apply();
      await stage(
        payload(
          'product',
          kind: 'product',
          unit: 'other',
          name: 'Peanut renamed',
        ),
        version: 3,
      );
      expect((await projection.apply()).conflicts, 1);
      expect((await local('product'))['unit_id'], 'kg');
    },
  );
}
