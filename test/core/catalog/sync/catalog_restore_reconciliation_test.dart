import 'dart:async';
import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_conflict_decisions.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_initial_publication.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_projection.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_restore_reconciliation.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RestoreTransport implements CatalogRestoreTransport {
  @override
  String? authenticatedUid = 'admin';
  final records = <String, CatalogRemoteRecord>{};
  Future<CatalogRemotePage> Function(String, String?, int)? pageBehavior;
  Future<CatalogRemoteRecord?> Function(String)? readBehavior;
  bool allRequests = true;
  int pages = 0, reads = 0;
  @override
  Future<String?> currentUserId() async => authenticatedUid;
  @override
  Future<CatalogRemotePage> fetch({
    required String farmId,
    required String actorUid,
    required String entity,
    required bool allRequests,
    required int limit,
    String? cursor,
  }) async {
    pages++;
    this.allRequests = this.allRequests && allRequests;
    if (pageBehavior != null) {
      return pageBehavior!(entity, cursor, limit);
    }
    final list =
        records.values
            .where(
              (r) =>
                  r.entity == entity &&
                  (cursor == null ||
                      CatalogRemoteRecord.compareIds(r.targetId, cursor) > 0),
            )
            .toList()
          ..sort(
            (a, b) => CatalogRemoteRecord.compareIds(a.targetId, b.targetId),
          );
    final page = list.take(limit).toList();
    return CatalogRemotePage(
      records: page,
      nextCursor: page.length == limit ? page.last.targetId : null,
    );
  }

  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async {
    reads++;
    final key = '$entity/$targetId';
    return readBehavior == null ? records[key] : await readBehavior!(key);
  }
}

class RestoreConflictVerifier implements CatalogConflictVerifier {
  RestoreConflictVerifier(this.transport);
  final RestoreTransport transport;
  @override
  Future<String?> currentUserId() async => transport.authenticatedUid;
  @override
  Future<CatalogRemoteRecord> verify({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async => (await transport.read(
    farmId: farmId,
    actorUid: actorUid,
    entity: entity,
    targetId: targetId,
  ))!;
}

class RestorePublicationVerifier implements CatalogPublicationVerifier {
  RestorePublicationVerifier(this.transport);
  final RestoreTransport transport;
  @override
  String? get authenticatedUid => transport.authenticatedUid;
  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String targetId,
  }) => transport.read(
    farmId: farmId,
    actorUid: actorUid,
    entity: 'entry',
    targetId: targetId,
  );
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
        {
          PermissionCodes.catalogView,
          PermissionCodes.catalogManage,
          PermissionCodes.cloudSync,
        },
    dataScopes: {DataScope.allFarm},
  );
  Map<String, Object?> entry(String id, {String? name, int revision = 1}) => {
    'id': id,
    'farm_id': 'farm',
    'kind': 'unit',
    'code': id.toUpperCase(),
    'name': name ?? id,
    'name_key': (name ?? id).toUpperCase(),
    'unit_id': null,
    'active': 1,
    'revision': revision,
  };
  Map<String, Object?> request(String id) => {
    'id': id,
    'farm_id': 'farm',
    'actor_uid': 'other',
    'kind': 'unit',
    'code': id.toUpperCase(),
    'name': id,
    'reason': 'Restored suggestion',
    'created_at': now.toIso8601String(),
    'status': 'pending',
    'entry_id': null,
    'resolved_by': null,
    'resolved_at': null,
    'resolution': null,
  };
  late Database db;
  late RestoreTransport transport;
  late CatalogRestoreReconciliation gate;
  late AuthorizationSubject current;
  CatalogRemoteRecord remote(
    String id, {
    String entity = 'entry',
    String? name,
    int version = 2,
  }) => CatalogRemoteRecord(
    farmId: 'farm',
    entity: entity,
    targetId: id,
    version: version,
    operationId: 'remote-$id-$version',
    payload: entity == 'entry' ? entry(id, name: name) : request(id),
  );
  Future<void> seed(String id, {String? name, int revision = 1}) => db.insert(
    SqliteCompanyCatalog.entriesTable,
    entry(id, name: name, revision: revision),
  );
  Future<int> blocked() async =>
      (await db.query(
            CatalogSyncJournal.device,
            where: 'farm_id=?',
            whereArgs: ['farm'],
          )).single['restore_blocked']
          as int;
  Future<void> unlock(
    CatalogRestoreReview review, {
    Set<String> localOnly = const {},
  }) => gate.unlock(
    review,
    reason: 'Reviewed restored catalog',
    keepLocalOnly: localOnly,
  );
  final failure = throwsA(isA<CatalogFailure>());
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteCompanyCatalog.createSchema(db);
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    current = actor();
    transport = RestoreTransport();
    gate = CatalogRestoreReconciliation(
      database: db,
      transport: transport,
      subject: () => current,
      clock: () => now,
    );
  });
  tearDown(() async {
    gate.dispose();
    await db.close();
  });

  test(
    'equal restored data establishes verified baseline and audited release without business writes',
    () async {
      await seed('kg', revision: 7);
      transport.records['entry/kg'] = remote('kg');
      final before = await db.query(SqliteCompanyCatalog.entriesTable);
      final review = await gate.review();
      expect(review.matched, 1);
      expect(await blocked(), 1);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      await unlock(review);
      expect(await blocked(), 0);
      expect(await db.query(SqliteCompanyCatalog.entriesTable), before);
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        2,
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      expect(
        (await db.query(SqliteCompanyCatalog.auditTable)).single['action'],
        'sync.restoreReviewed',
      );
      await expectLater(unlock(review), failure);
      expect((await db.query(SqliteCompanyCatalog.auditTable)).length, 1);
    },
  );
  test(
    'empty local and cloud still require complete scan and explicit release',
    () async {
      final review = await gate.review();
      expect(transport.pages, 2);
      await unlock(review);
      expect(await blocked(), 0);
    },
  );
  test(
    'local-only masters must be explicitly retained without creating send authority',
    () async {
      await seed('kg');
      final review = await gate.review();
      expect(review.localOnly, ['entry/kg']);
      await expectLater(unlock(review), failure);
      expect(await blocked(), 1);
      await unlock(review, localOnly: {'entry/kg'});
      expect(await blocked(), 0);
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect((await db.query(SqliteCompanyCatalog.entriesTable)).length, 1);
    },
  );
  test(
    'restored foreign-actor suggestion stays local and is never reassigned or queued',
    () async {
      await db.insert(
        SqliteCompanyCatalog.requestsTable,
        request('suggestion'),
      );
      final review = await gate.review();
      await unlock(review, localOnly: {'request/suggestion'});
      expect(
        (await db.query(
          SqliteCompanyCatalog.requestsTable,
        )).single['actor_uid'],
        'other',
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
    },
  );
  test('all farm suggestions included in review', () async {
    await db.insert(SqliteCompanyCatalog.requestsTable, request('suggestion'));
    transport.records['request/suggestion'] = remote(
      'suggestion',
      entity: 'request',
    );
    final review = await gate.review();
    expect(review.matched, 1);
    expect(transport.allRequests, isTrue);
    await unlock(review);
    expect(await blocked(), 0);
  });
  test(
    'divergent or remote-only data is staged but prevents release',
    () async {
      await seed('kg', name: 'Local');
      transport.records['entry/kg'] = remote('kg', name: 'Server');
      transport.records['entry/new'] = remote('new');
      final review = await gate.review();
      expect(review.divergent, ['entry/kg']);
      expect(review.remoteOnly, ['entry/new']);
      expect((await db.query(CatalogSyncJournal.inbox)).length, 2);
      await expectLater(unlock(review), failure);
      expect(await blocked(), 1);
      expect(
        (await db.query(SqliteCompanyCatalog.entriesTable)).single['name'],
        'Local',
      );
    },
  );
  test(
    'partial page budget never produces review or releases isolation',
    () async {
      transport.records['entry/kg'] = remote('kg');
      final small = CatalogRestoreReconciliation(
        database: db,
        transport: transport,
        subject: () => current,
        clock: () => now,
        pageSize: 1,
        maxPages: 2,
      );
      await expectLater(small.review(), failure);
      expect(await blocked(), 1);
      expect(await db.query(CatalogSyncJournal.inbox), isEmpty);
    },
  );
  test('full page includes terminal read before complete review', () async {
    await seed('kg');
    transport.records['entry/kg'] = remote('kg');
    final small = CatalogRestoreReconciliation(
      database: db,
      transport: transport,
      subject: () => current,
      clock: () => now,
      pageSize: 1,
      maxPages: 3,
    );
    final review = await small.review();
    expect(review.matched, 1);
    expect(transport.pages, 3);
  });
  test('forged cursor or unsorted page is rejected', () async {
    transport.pageBehavior = (_, _, _) async =>
        CatalogRemotePage(records: [remote('kg')], nextCursor: 'wrong');
    await expectLater(gate.review(), failure);
    expect(await blocked(), 1);
    transport.pageBehavior = (_, _, _) async =>
        CatalogRemotePage(records: [remote('z'), remote('a')]);
    await expectLater(gate.review(), failure);
    expect(await db.query(CatalogSyncJournal.inbox), isEmpty);
  });
  test('network interruption preserves isolation and business rows', () async {
    await seed('kg');
    transport.pageBehavior = (_, _, _) async =>
        throw const CatalogSyncUnavailable();
    await expectLater(gate.review(), throwsA(isA<CatalogSyncUnavailable>()));
    expect(await blocked(), 1);
    expect((await db.query(SqliteCompanyCatalog.entriesTable)).length, 1);
  });
  test('old review invalidated by local edits', () async {
    await seed('kg');
    transport.records['entry/kg'] = remote('kg');
    final review = await gate.review();
    await db.update(
      SqliteCompanyCatalog.entriesTable,
      {'revision': 2},
      where: 'id=?',
      whereArgs: ['kg'],
    );
    await expectLater(unlock(review), failure);
    expect(await blocked(), 1);
    expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
  });
  test(
    'old review invalidated by newer server version or changed local-only absence',
    () async {
      await seed('kg');
      transport.records['entry/kg'] = remote('kg');
      final review = await gate.review();
      transport.records['entry/kg'] = remote('kg', version: 3);
      await expectLater(unlock(review), failure);
      expect(await blocked(), 1);
      transport.records.clear();
      final localOnly = await gate.review();
      transport.readBehavior = (_) async => remote('kg');
      await expectLater(unlock(localOnly, localOnly: {'entry/kg'}), failure);
      expect(await blocked(), 1);
    },
  );
  test(
    'fresh exact read detects server change hidden by page result',
    () async {
      await seed('kg');
      transport.records['entry/kg'] = remote('kg');
      final review = await gate.review();
      transport.readBehavior = (_) async => remote('kg', version: 3);
      await expectLater(unlock(review), failure);
      expect(await blocked(), 1);
    },
  );
  for (final state in ['pending', 'blocked', 'conflict']) {
    test(
      'unresolved $state operation is retained and prevents release',
      () async {
        await seed('kg');
        await db.transaction(
          (tx) => CatalogSyncJournal.append(
            tx,
            farmId: 'farm',
            actorUid: 'other',
            entity: 'entry',
            targetId: 'kg',
            payload: entry('kg'),
            reason: 'New offline edit',
            occurredAt: now,
          ),
        );
        if (state != 'pending') {
          final id =
              (await db.query(CatalogSyncJournal.outbox)).single['operation_id']
                  as String;
          await CatalogSyncJournal(
            db,
          ).fail(id, conflict: state == 'conflict', code: 'catalog.changed');
        }
        final before = await db.query(CatalogSyncJournal.outbox);
        final review = await gate.review();
        await expectLater(unlock(review, localOnly: {'entry/kg'}), failure);
        expect(await db.query(CatalogSyncJournal.outbox), before);
        expect(await blocked(), 1);
      },
    );
  }
  test('conflicts from any reader prevent release', () async {
    await seed('kg');
    transport.records['entry/kg'] = remote('kg');
    await db.insert(CatalogSyncJournal.conflicts, {
      'farm_id': 'farm',
      'reader_uid': 'other',
      'entity': 'entry',
      'target_id': 'kg',
      'cloud_version': 2,
      'operation_id': 'remote-kg-2',
      'remote_json': jsonEncode(entry('kg')),
      'local_json': jsonEncode(entry('kg')),
      'failure': 'catalog.changed',
    });
    final review = await gate.review();
    await expectLater(unlock(review), failure);
    expect(await blocked(), 1);
  });
  test(
    'stale inbox or shadow evidence for absent target is not discarded',
    () async {
      await seed('kg');
      await db.insert(CatalogSyncJournal.shadow, {
        'farm_id': 'farm',
        'entity': 'entry',
        'target_id': 'kg',
        'cloud_version': 3,
        'operation_id': 'old',
        'payload_json': jsonEncode(entry('kg')),
      });
      final review = await gate.review();
      await expectLater(unlock(review, localOnly: {'entry/kg'}), failure);
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        3,
      );
      expect(await blocked(), 1);
    },
  );
  test('staff, wrong SDK actor, and revocation cannot release', () async {
    final review = await gate.review();
    current = actor(
      permissions: {PermissionCodes.catalogView, PermissionCodes.cloudSync},
    );
    await expectLater(unlock(review), failure);
    current = actor();
    transport.authenticatedUid = 'other';
    await expectLater(unlock(review), failure);
    transport.authenticatedUid = 'admin';
    transport.pageBehavior = (_, _, _) async {
      current = actor(active: false);
      return CatalogRemotePage(records: []);
    };
    await expectLater(unlock(review), failure);
    expect(await blocked(), 1);
  });
  test('review is actor and farm bound', () async {
    final review = await gate.review();
    current = actor(uid: 'other');
    transport.authenticatedUid = 'other';
    await expectLater(unlock(review), failure);
    current = actor(farm: 'other');
    transport.authenticatedUid = 'admin';
    await expectLater(unlock(review), failure);
    expect(await blocked(), 1);
  });
  test(
    'reason, exact local-only selections and unblocked state are guarded',
    () async {
      await seed('kg');
      final review = await gate.review();
      await expectLater(
        gate.unlock(review, reason: ' ', keepLocalOnly: {'entry/kg'}),
        failure,
      );
      await expectLater(
        unlock(review, localOnly: {'entry/kg', 'entry/extra'}),
        failure,
      );
      await db.update(CatalogSyncJournal.device, {'restore_blocked': 0});
      await expectLater(unlock(review, localOnly: {'entry/kg'}), failure);
    },
  );
  test('overlap and disposal during scan cannot release', () async {
    final waiting = Completer<CatalogRemotePage>();
    transport.pageBehavior = (_, _, _) => waiting.future;
    final first = gate.review();
    while (transport.pages == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(gate.review(), failure);
    gate.dispose();
    final expectation = expectLater(first, failure);
    waiting.complete(CatalogRemotePage(records: []));
    await expectation;
    expect(await blocked(), 1);
  });
  test(
    'late authorization loss rolls back shadows, audit and unlock together',
    () async {
      await seed('kg');
      transport.records['entry/kg'] = remote('kg');
      final review = await gate.review();
      var checks = 0;
      final guarded = CatalogRestoreReconciliation(
        database: db,
        transport: transport,
        subject: () {
          checks++;
          return checks >= 11 ? actor(active: false) : actor();
        },
        clock: () => now,
      );
      // Initial + guard, two page pairs, exact read pair, transaction pair = 10.
      // Revoke on the final transaction guard; offset makes that check eleven.
      checks = 1;
      await expectLater(
        guarded.unlock(review, reason: 'review', keepLocalOnly: {}),
        failure,
      );
      expect(await blocked(), 1);
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
  test(
    'restore conflict acceptance then fresh review permits audited release',
    () async {
      await seed('kg', name: 'Local');
      transport.records['entry/kg'] = remote('kg', name: 'Server');
      expect((await gate.review()).divergent, ['entry/kg']);
      final projection = CatalogSyncProjection(
        database: db,
        currentSubject: () => current,
        clock: () => now,
      );
      expect((await projection.apply()).conflicts, 1);
      final decisions = CatalogConflictDecisions(
        database: db,
        verifier: RestoreConflictVerifier(transport),
        currentSubject: () => current,
        clock: () => now,
      );
      final conflicts = await projection.conflicts();
      await decisions.decide(
        CatalogConflictReview.fromRow(conflicts.single),
        choice: CatalogConflictChoice.acceptRemote,
        reason: 'Accept current server after restore',
      );
      expect(await blocked(), 1);
      final review = await gate.review();
      expect(review.matched, 1);
      expect(review.divergent, isEmpty);
      await unlock(review);
      expect(await blocked(), 0);
      expect(
        (await db.query(SqliteCompanyCatalog.entriesTable)).single['name'],
        'Server',
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      projection.dispose();
      decisions.dispose();
    },
  );
  test(
    'kept local-only master requires separate explicit publication after release',
    () async {
      await seed('kg');
      final publisher = CatalogInitialPublication(
        database: db,
        verifier: RestorePublicationVerifier(transport),
        subject: () => current,
        clock: () => now,
      );
      final selected = await publisher.review('kg');
      await expectLater(
        publisher.prepare(selected, reason: 'Initial send'),
        failure,
      );
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      await unlock(await gate.review(), localOnly: {'entry/kg'});
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      await publisher.prepare(
        await publisher.review('kg'),
        reason: 'Reviewed separate publication',
      );
      final command = (await db.query(CatalogSyncJournal.outbox)).single;
      expect(command['base_version'], 0);
      expect(command['actor_uid'], 'admin');
      expect(command['state'], 'pending');
      publisher.dispose();
    },
  );
}
