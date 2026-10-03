import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_projection.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_conflict_decisions.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'dart:async';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Verifier implements CatalogConflictVerifier {
  String? uid = 'admin';
  CatalogRemoteRecord? remote;
  Future<CatalogRemoteRecord> Function()? read;
  int calls = 0;
  @override
  Future<String?> currentUserId() async => uid;
  @override
  Future<CatalogRemoteRecord> verify({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async {
    calls++;
    return read == null ? remote! : await read!();
  }
}

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
  late Verifier verifier;
  late CatalogConflictDecisions decisions;
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
  setUp(() {
    verifier = Verifier();
    decisions = CatalogConflictDecisions(
      database: db,
      verifier: verifier,
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

  Future<CatalogConflictReview> conflict({int version = 1}) async {
    await db.insert(
      SqliteCompanyCatalog.entriesTable,
      payload('kg', name: 'Local'),
    );
    await stage(payload('kg', name: 'Remote'), version: version);
    await projection.apply();
    final review = CatalogConflictReview.fromRow(
      (await projection.conflicts()).single,
    );
    verifier.remote = CatalogRemoteRecord(
      farmId: 'farm',
      entity: 'entry',
      targetId: 'kg',
      version: version,
      operationId: review.operationId,
      payload: payload('kg', name: 'Remote'),
    );
    return review;
  }

  Future<void> choose(
    CatalogConflictReview r, {
    CatalogConflictChoice choice = CatalogConflictChoice.acceptRemote,
    String reason = 'Reviewed',
  }) => decisions.decide(r, choice: choice, reason: reason);
  test(
    'accept remote commits guarded business shadow and durable review audit',
    () async {
      final review = await conflict();
      await choose(review);
      expect((await local('kg'))['name'], 'Remote');
      expect((await local('kg'))['revision'], 2);
      expect(await projection.conflicts(), isEmpty);
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      final audits = await db.query(SqliteCompanyCatalog.auditTable);
      expect(audits.map((r) => r['action']), contains('conflict.acceptRemote'));
      final proof = jsonDecode(audits.last['after_json'] as String) as Map;
      expect(proof['remote']['name'], 'Remote');
      expect(proof['cloudVersion'], 1);
    },
  );
  test(
    'keep local creates a new actor-owned command on verified remote base',
    () async {
      final review = await conflict(version: 3);
      await choose(review, choice: CatalogConflictChoice.keepLocal);
      expect((await local('kg'))['name'], 'Local');
      expect((await local('kg'))['revision'], 2);
      final q = (await db.query(CatalogSyncJournal.outbox)).single;
      expect(q['base_version'], 3);
      expect(q['new_version'], 4);
      expect(q['actor_uid'], 'admin');
      expect(jsonDecode(q['payload_json'] as String)['name'], 'Local');
      expect(
        jsonDecode(
          (await db.query(CatalogSyncJournal.shadow)).single['payload_json']
              as String,
        )['name'],
        'Remote',
      );
      expect(await projection.conflicts(), isEmpty);
      expect((await projection.apply()).conflicts, 0);
    },
  );
  test(
    'reusing an old decision cannot create a second mutation or audit',
    () async {
      final review = await conflict();
      await choose(review);
      await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
      expect((await db.query(SqliteCompanyCatalog.auditTable)).length, 2);
    },
  );
  test(
    'server changed version payload or operation refuses stale review',
    () async {
      final review = await conflict();
      for (final record in [
        CatalogRemoteRecord(
          farmId: 'farm',
          entity: 'entry',
          targetId: 'kg',
          version: 2,
          operationId: 'new',
          payload: payload('kg', name: 'Remote'),
        ),
        CatalogRemoteRecord(
          farmId: 'farm',
          entity: 'entry',
          targetId: 'kg',
          version: 1,
          operationId: 'other',
          payload: payload('kg', name: 'Remote'),
        ),
        CatalogRemoteRecord(
          farmId: 'farm',
          entity: 'entry',
          targetId: 'kg',
          version: 1,
          operationId: review.operationId,
          payload: payload('kg', name: 'New name'),
        ),
      ]) {
        verifier.remote = record;
        await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
      }
      expect((await local('kg'))['name'], 'Local');
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    },
  );
  test('local edit after review is not overwritten', () async {
    final review = await conflict();
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'name': 'New local'},
      where: 'id=?',
      whereArgs: ['kg'],
    );
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect((await local('kg'))['name'], 'New local');
    expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
  });
  test(
    'new staging or changed conflict after review refuses decision',
    () async {
      final review = await conflict();
      await stage(payload('kg', name: 'New'), version: 2);
      await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
      expect((await local('kg'))['name'], 'Local');
    },
  );
  test(
    'unresolved pending blocked and conflicted commands remain immutable',
    () async {
      final review = await conflict();
      await dirty('kg');
      for (final state in ['pending', 'blocked', 'conflict']) {
        await db.update(CatalogSyncJournal.outbox, {'state': state});
        await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
        await expectLater(
          choose(review, choice: CatalogConflictChoice.keepLocal),
          throwsA(isA<CatalogFailure>()),
        );
        expect(
          (await db.query(CatalogSyncJournal.outbox)).single['actor_uid'],
          'other',
        );
        expect(
          (await db.query(CatalogSyncJournal.outbox)).single['state'],
          state,
        );
      }
      expect((await local('kg'))['name'], 'Local');
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    },
  );
  test('SDK mismatch network failure and signout retain conflict', () async {
    final review = await conflict();
    verifier.uid = 'other';
    await expectLater(choose(review), throwsA(isA<CatalogSyncUnavailable>()));
    verifier.uid = 'admin';
    verifier.read = () async => throw const CatalogSyncUnavailable();
    await expectLater(choose(review), throwsA(isA<CatalogSyncUnavailable>()));
    verifier.read = () async {
      subject = null;
      return verifier.remote!;
    };
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect((await local('kg'))['name'], 'Local');
    expect((await db.query(CatalogSyncJournal.conflicts)).length, 1);
  });
  test('staff expired and different reader cannot decide', () async {
    final review = await conflict();
    subject = actor('admin', manager: false);
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    subject = actor('admin', active: false);
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    subject = actor('other');
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect(verifier.calls, 0);
  });
  test(
    'permission revoked at transaction end rolls back all decision writes',
    () async {
      final review = await conflict();
      var calls = 0;
      decisions = CatalogConflictDecisions(
        database: db,
        verifier: verifier,
        clock: () => now,
        currentSubject: () {
          calls++;
          return actor('admin', active: calls < 5);
        },
      );
      await expectLater(
        choose(review, choice: CatalogConflictChoice.keepLocal),
        throwsA(isA<CatalogFailure>()),
      );
      expect((await local('kg'))['name'], 'Local');
      expect((await local('kg'))['revision'], 1);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
      expect((await db.query(CatalogSyncJournal.conflicts)).length, 1);
    },
  );
  test('concurrent choices cannot run against one review', () async {
    final review = await conflict();
    final gate = Completer<CatalogRemoteRecord>();
    verifier.read = () => gate.future;
    final first = choose(review);
    await Future<void>.delayed(Duration.zero);
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    gate.complete(verifier.remote!);
    await first;
    expect(verifier.calls, 1);
  });
  test('reason is mandatory and disposal prevents a choice', () async {
    final review = await conflict();
    await expectLater(
      choose(review, reason: '   '),
      throwsA(isA<CatalogFailure>()),
    );
    decisions.dispose();
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect(verifier.calls, 0);
  });
  test('restored device stays blocked even after choosing remote', () async {
    final review = await conflict();
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    await choose(review);
    expect(
      (await db.query(CatalogSyncJournal.device)).single['restore_blocked'],
      1,
    );
  });
  test(
    'uniqueness guard rolls back a remote choice and keeps review',
    () async {
      final review = await conflict();
      await db.insert(
        SqliteCompanyCatalog.entriesTable,
        payload('other', name: 'Remote'),
      );
      await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
      expect((await local('kg'))['name'], 'Local');
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect((await projection.conflicts()).length, 1);
    },
  );
  test(
    'reference guard prevents renaming a unit through conflict decision',
    () async {
      final review = await conflict();
      await db.insert(
        SqliteCompanyCatalog.entriesTable,
        payload('crop', kind: 'crop', unit: 'kg', name: 'Peanut'),
      );
      await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
      expect((await local('kg'))['name'], 'Local');
    },
  );
  test('cross-farm collision can never be accepted into this farm', () async {
    await db.insert(
      SqliteCompanyCatalog.entriesTable,
      payload('kg', farm: 'other', name: 'Private'),
    );
    await stage(payload('kg', name: 'Remote'));
    await projection.apply();
    final review = CatalogConflictReview.fromRow(
      (await projection.conflicts()).single,
    );
    verifier.remote = CatalogRemoteRecord(
      farmId: 'farm',
      entity: 'entry',
      targetId: 'kg',
      version: 1,
      operationId: review.operationId,
      payload: payload('kg', name: 'Remote'),
    );
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect((await local('kg'))['farm_id'], 'other');
  });
  test('shadow advancing after review blocks older server decision', () async {
    final review = await conflict();
    await db.insert(CatalogSyncJournal.shadow, {
      'farm_id': 'farm',
      'entity': 'entry',
      'target_id': 'kg',
      'cloud_version': 2,
      'operation_id': 'later',
      'payload_json': jsonEncode(payload('kg', name: 'Later')),
    });
    await expectLater(choose(review), throwsA(isA<CatalogFailure>()));
    expect((await local('kg'))['name'], 'Local');
    expect(
      (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
      2,
    );
  });
  test(
    'request decisions cannot reopen an approved remote suggestion',
    () async {
      await db.insert(SqliteCompanyCatalog.entriesTable, payload('kg'));
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
      await db.insert(SqliteCompanyCatalog.requestsTable, p);
      final approved = {
        ...p,
        'status': 'approved',
        'entry_id': 'kg',
        'resolved_by': 'admin',
        'resolved_at': now.toIso8601String(),
        'resolution': 'Approved',
      };
      await stage(approved, entity: 'request');
      await projection.apply();
      final review = CatalogConflictReview.fromRow(
        (await projection.conflicts()).single,
      );
      verifier.remote = CatalogRemoteRecord(
        farmId: 'farm',
        entity: 'request',
        targetId: 'req',
        version: 1,
        operationId: review.operationId,
        payload: approved,
      );
      await expectLater(
        choose(review, choice: CatalogConflictChoice.keepLocal),
        throwsA(isA<CatalogFailure>()),
      );
      await choose(review);
      expect(
        (await db.query(SqliteCompanyCatalog.requestsTable)).single['status'],
        'approved',
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
    },
  );
}
