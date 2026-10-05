import 'dart:async';
import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_initial_publication.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PublicationVerifier implements CatalogPublicationVerifier {
  @override
  String? authenticatedUid = 'admin';
  final records = <String, CatalogRemoteRecord>{};
  Future<CatalogRemoteRecord?> Function(String)? behavior;
  int reads = 0;
  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String targetId,
  }) async {
    reads++;
    return behavior == null ? records[targetId] : await behavior!(targetId);
  }
}

class RejectingTransport implements CatalogSyncTransport {
  @override
  Future<String?> currentUserId() async => 'admin';
  @override
  Future<CatalogSyncReceipt> send(CatalogSyncCommand command) async =>
      throw const CatalogSyncRejected('catalog.changed', conflict: true);
}

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 5);
  AuthorizationSubject actor({
    String uid = 'admin',
    String farm = 'farm',
    bool active = true,
    Set<String>? permissions,
  }) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: farm,
    active: active,
    validUntil: now.add(const Duration(days: 7)),
    permissionCodes:
        permissions ??
        {PermissionCodes.catalogManage, PermissionCodes.cloudSync},
    dataScopes: {DataScope.allFarm},
  );
  late Database db;
  late PublicationVerifier verifier;
  late CatalogInitialPublication publisher;
  late AuthorizationSubject current;
  Map<String, Object?> entry(
    String id, {
    String kind = 'unit',
    String? unit,
    int active = 1,
    int revision = 1,
  }) => {
    'id': id,
    'farm_id': 'farm',
    'kind': kind,
    'code': id.toUpperCase(),
    'name': id,
    'name_key': id.toUpperCase(),
    'unit_id': unit,
    'active': active,
    'revision': revision,
  };
  Future<void> seed(
    String id, {
    String kind = 'unit',
    String? unit,
    int active = 1,
  }) => db.insert(
    SqliteCompanyCatalog.entriesTable,
    entry(id, kind: kind, unit: unit, active: active),
  );
  Future<List<Map<String, Object?>>> queue() =>
      db.query(CatalogSyncJournal.outbox, orderBy: 'sequence');
  Future<void> prepare(String id) async => publisher.prepare(
    await publisher.review(id),
    reason: 'Initial publication review',
  );
  Future<void> baselineUnit({int localRevision = 1}) async {
    final payload = entry('kg');
    final remote = CatalogRemoteRecord(
      farmId: 'farm',
      entity: 'entry',
      targetId: 'kg',
      version: 3,
      operationId: 'remote-unit',
      payload: payload,
    );
    verifier.records['kg'] = remote;
    await db.insert(CatalogSyncJournal.shadow, {
      'farm_id': 'farm',
      'entity': 'entry',
      'target_id': 'kg',
      'cloud_version': 3,
      'operation_id': remote.operationId,
      'payload_json': remote.payloadJson,
    });
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'revision': localRevision},
      where: 'id=?',
      whereArgs: ['kg'],
    );
  }

  final failure = throwsA(isA<CatalogFailure>());
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteCompanyCatalog.createSchema(db);
    current = actor();
    verifier = PublicationVerifier();
    publisher = CatalogInitialPublication(
      database: db,
      verifier: verifier,
      subject: () => current,
      clock: () => now,
    );
    await seed('kg');
  });
  tearDown(() async {
    publisher.dispose();
    await db.close();
  });

  test(
    'adopted unit gets one immutable initial command and audit without business edits',
    () async {
      final before = await db.query(SqliteCompanyCatalog.entriesTable);
      await prepare('kg');
      final row = (await queue()).single;
      expect(row['base_version'], 0);
      expect(row['new_version'], 1);
      expect(row['actor_uid'], 'admin');
      expect(jsonDecode(row['payload_json'] as String), before.single);
      expect(await db.query(SqliteCompanyCatalog.entriesTable), before);
      expect(
        (await db.query(SqliteCompanyCatalog.auditTable)).single['action'],
        'sync.prepareInitial',
      );
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    },
  );
  test('repeating preparation cannot duplicate command or audit', () async {
    await prepare('kg');
    final before = await queue();
    await expectLater(prepare('kg'), failure);
    expect(await queue(), before);
    expect((await db.query(SqliteCompanyCatalog.auditTable)).length, 1);
  });
  test(
    'existing remote target, even equal payload, is never adopted or overwritten',
    () async {
      verifier.records['kg'] = CatalogRemoteRecord(
        farmId: 'farm',
        entity: 'entry',
        targetId: 'kg',
        version: 1,
        operationId: 'existing',
        payload: entry('kg'),
      );
      await expectLater(prepare('kg'), failure);
      expect(await queue(), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
  test('new local edit after review invalidates selected snapshot', () async {
    final review = await publisher.review('kg');
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'revision': 2},
      where: 'id=?',
      whereArgs: ['kg'],
    );
    await expectLater(publisher.prepare(review, reason: 'review'), failure);
    expect(await queue(), isEmpty);
  });
  test('edit during server read prevents enqueue', () async {
    final review = await publisher.review('kg');
    verifier.behavior = (_) async {
      await db.update(
        SqliteCompanyCatalog.entriesTable,
        {'name': 'Changed', 'name_key': 'CHANGED', 'revision': 2},
        where: 'id=?',
        whereArgs: ['kg'],
      );
      return null;
    };
    await expectLater(publisher.prepare(review, reason: 'review'), failure);
    expect(await queue(), isEmpty);
  });
  test('unit then dependent crop have ordered initial operations', () async {
    await seed('crop', kind: 'crop', unit: 'kg');
    await expectLater(prepare('crop'), failure);
    await prepare('kg');
    await prepare('crop');
    expect((await queue()).map((r) => r['target_id']), ['kg', 'crop']);
    expect((await queue()).map((r) => r['base_version']), [0, 0]);
  });
  test(
    'verified remote unit baseline permits local material without changing stock',
    () async {
      await seed('material', kind: 'material', unit: 'kg');
      await baselineUnit(localRevision: 5);
      await db.execute(
        'CREATE TABLE inventory_items_v2 (id TEXT PRIMARY KEY, quantity REAL, unit_price REAL)',
      );
      await db.insert('inventory_items_v2', {
        'id': 'material',
        'quantity': 19.0,
        'unit_price': 27.0,
      });
      final before = await db.query('inventory_items_v2');
      await prepare('material');
      expect(await db.query('inventory_items_v2'), before);
      expect((await queue()).single['target_id'], 'material');
    },
  );
  test(
    'remote unit without verified local baseline needs reconciliation',
    () async {
      await seed('crop', kind: 'crop', unit: 'kg');
      verifier.records['kg'] = CatalogRemoteRecord(
        farmId: 'farm',
        entity: 'entry',
        targetId: 'kg',
        version: 1,
        operationId: 'remote',
        payload: entry('kg'),
      );
      await expectLater(prepare('crop'), failure);
      expect(await queue(), isEmpty);
    },
  );
  test(
    'changed remote unit or local unit cannot be treated as baseline',
    () async {
      await seed('crop', kind: 'crop', unit: 'kg');
      await baselineUnit();
      verifier.records['kg'] = CatalogRemoteRecord(
        farmId: 'farm',
        entity: 'entry',
        targetId: 'kg',
        version: 4,
        operationId: 'newer',
        payload: entry('kg'),
      );
      await expectLater(prepare('crop'), failure);
      expect(await queue(), isEmpty);
    },
  );
  for (final state in ['blocked', 'conflict']) {
    test(
      '$state unit command cannot authorize dependent initial publication',
      () async {
        await seed('crop', kind: 'crop', unit: 'kg');
        await prepare('kg');
        await CatalogSyncJournal(db).fail(
          (await queue()).single['operation_id'] as String,
          conflict: state == 'conflict',
          code: 'catalog.changed',
        );
        final before = await queue();
        await expectLater(prepare('crop'), failure);
        expect(await queue(), before);
      },
    );
  }
  test(
    'another actors unit command cannot authorize this publishers dependent entry',
    () async {
      await seed('crop', kind: 'crop', unit: 'kg');
      await db.transaction(
        (tx) => CatalogSyncJournal.append(
          tx,
          farmId: 'farm',
          actorUid: 'other',
          entity: 'entry',
          targetId: 'kg',
          payload: entry('kg'),
          reason: 'other actor',
          occurredAt: now,
        ),
      );
      await expectLater(prepare('crop'), failure);
      expect((await queue()).single['actor_uid'], 'other');
    },
  );
  test('retired unit cannot authorize consumers', () async {
    await seed('crop', kind: 'crop', unit: 'kg');
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'active': 0},
      where: 'id=?',
      whereArgs: ['kg'],
    );
    await expectLater(prepare('crop'), failure);
    expect(await queue(), isEmpty);
  });
  test('staging or shadow evidence prevents initial publication', () async {
    await db.insert(CatalogSyncJournal.inbox, {
      'farm_id': 'farm',
      'reader_uid': 'other',
      'entity': 'entry',
      'target_id': 'kg',
      'cloud_version': 1,
      'operation_id': 'remote',
      'payload_json': jsonEncode(entry('kg')),
    });
    await expectLater(prepare('kg'), failure);
    expect(await queue(), isEmpty);
  });
  test('restore barrier is preserved', () async {
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    await expectLater(prepare('kg'), failure);
    expect(await queue(), isEmpty);
    expect(
      (await db.query(CatalogSyncJournal.device)).single['restore_blocked'],
      1,
    );
  });
  test(
    'SDK switch and local revocation after read prevent all writes',
    () async {
      final review = await publisher.review('kg');
      verifier.behavior = (_) async {
        verifier.authenticatedUid = 'other';
        return null;
      };
      await expectLater(publisher.prepare(review, reason: 'review'), failure);
      expect(await queue(), isEmpty);
      verifier.authenticatedUid = 'admin';
      verifier.behavior = (_) async {
        current = actor(active: false);
        return null;
      };
      await expectLater(publisher.prepare(review, reason: 'review'), failure);
      expect(await queue(), isEmpty);
    },
  );
  test(
    'staff, missing sync permission and wrong farm cannot prepare',
    () async {
      final review = await publisher.review('kg');
      current = actor(permissions: {PermissionCodes.cloudSync});
      await expectLater(publisher.prepare(review, reason: 'review'), failure);
      current = actor(permissions: {PermissionCodes.catalogManage});
      await expectLater(publisher.prepare(review, reason: 'review'), failure);
      current = actor(farm: 'other');
      await expectLater(publisher.prepare(review, reason: 'review'), failure);
      expect(await queue(), isEmpty);
    },
  );
  test('network uncertainty does not enqueue or audit', () async {
    verifier.behavior = (_) async => throw const CatalogSyncUnavailable();
    await expectLater(prepare('kg'), throwsA(isA<CatalogSyncUnavailable>()));
    expect(await queue(), isEmpty);
    expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
  });
  test('reason required and disposed coordinator cannot prepare', () async {
    final review = await publisher.review('kg');
    await expectLater(publisher.prepare(review, reason: '  '), failure);
    publisher.dispose();
    await expectLater(publisher.prepare(review, reason: 'review'), failure);
    expect(await queue(), isEmpty);
  });
  test('overlap rejected; disposal during read leaves no commands', () async {
    final review = await publisher.review('kg');
    final gate = Completer<CatalogRemoteRecord?>();
    verifier.behavior = (_) => gate.future;
    final first = publisher.prepare(review, reason: 'review');
    await expectLater(publisher.prepare(review, reason: 'review'), failure);
    publisher.dispose();
    final expectation = expectLater(first, failure);
    gate.complete(null);
    await expectation;
    expect(await queue(), isEmpty);
  });
  test(
    'server race remains protected by sender compare-and-set rejection',
    () async {
      await prepare('kg');
      final result = await CatalogSyncSender(
        journal: CatalogSyncJournal(db),
        transport: RejectingTransport(),
        subject: () => current,
        clock: () => now,
      ).synchronize();
      expect(result.conflicts, 1);
      expect((await queue()).single['base_version'], 0);
      expect((await queue()).single['state'], 'conflict');
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    },
  );
  test(
    'late authorization loss rolls back enqueue and audit atomically',
    () async {
      var calls = 0;
      final guarded = CatalogInitialPublication(
        database: db,
        verifier: verifier,
        subject: () {
          calls++;
          return calls >= 8 ? actor(active: false) : actor();
        },
        clock: () => now,
      );
      final review = CatalogPublicationReview.fromRow(entry('kg'));
      // subject reads: initial, initial guard, after target, after unit, tx start, tx end.
      // Revoke on the final guard after the queue and audit have been inserted.
      calls = 2;
      await expectLater(guarded.prepare(review, reason: 'review'), failure);
      expect(await queue(), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
}
