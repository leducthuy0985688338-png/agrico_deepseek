import 'dart:async';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_conflict_decisions.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_initial_publication.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_receipt_recovery.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_restore_reconciliation.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_workspace.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class WorkspaceRemote
    implements
        CatalogSyncTransport,
        CatalogRestoreTransport,
        CatalogReceiptLookup,
        CatalogConflictVerifier,
        CatalogPublicationVerifier {
  String? uid = 'admin';
  final events = <String>[];
  Completer<void>? gate;
  bool unavailable = false;
  @override
  String? get authenticatedUid => uid;
  @override
  Future<String?> currentUserId() async => uid;
  @override
  Future<Map<String, Object?>?> lookup(CatalogSyncCommand command) async {
    events.add('receipt');
    return null;
  }

  @override
  Future<CatalogSyncReceipt> send(CatalogSyncCommand command) async {
    events.add('send');
    if (gate != null) {
      await gate!.future;
    }
    if (unavailable) {
      throw const CatalogSyncUnavailable();
    }
    return CatalogSyncReceipt(
      operationId: command.operationId,
      farmId: command.farmId,
      actorUid: command.actorUid,
      entity: command.entity,
      targetId: command.targetId,
      cloudVersion: command.newVersion,
      payload: command.payload,
    );
  }

  @override
  Future<CatalogRemotePage> fetch({
    required String farmId,
    required String actorUid,
    required String entity,
    required bool allRequests,
    required int limit,
    String? cursor,
  }) async {
    events.add('download:$entity:$allRequests');
    return CatalogRemotePage(records: []);
  }

  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String targetId,
    String? entity,
  }) async => null;
  @override
  Future<CatalogRemoteRecord> verify({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async => throw const CatalogSyncUnavailable();
}

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 5);
  AuthorizationSubject actor({String uid = 'admin', bool manage = true}) =>
      AuthorizationSubject(
        userId: uid,
        membershipId: uid,
        farmId: 'farm',
        active: true,
        validUntil: now.add(const Duration(days: 7)),
        permissionCodes: {
          PermissionCodes.cloudSync,
          PermissionCodes.catalogView,
          PermissionCodes.catalogRequest,
          if (manage) PermissionCodes.catalogManage,
        },
        dataScopes: {DataScope.allFarm},
      );
  Map<String, Object?> entry(String id) => {
    'id': id,
    'farm_id': 'farm',
    'kind': 'unit',
    'code': id.toUpperCase(),
    'name': id,
    'name_key': id.toUpperCase(),
    'unit_id': null,
    'active': 1,
    'revision': 1,
  };
  late Database db;
  late WorkspaceRemote remote;
  late AuthorizationSubject current;
  late CatalogSyncWorkspace workspace;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteCompanyCatalog.createSchema(db);
    remote = WorkspaceRemote();
    current = actor();
    workspace = CatalogSyncWorkspace(
      database: db,
      currentSubject: () => current,
      sendTransport: remote,
      receiveTransport: remote,
      receiptLookup: remote,
      conflictVerifier: remote,
      publicationVerifier: remote,
      restoreTransport: remote,
      clock: () => now,
    );
  });
  tearDown(() async {
    workspace.dispose();
    await db.close();
  });
  Future<void> pending({String uid = 'admin', String state = 'pending'}) async {
    await db.insert(SqliteCompanyCatalog.entriesTable, entry('kg'));
    await CatalogSyncJournal.append(
      db,
      farmId: 'farm',
      actorUid: uid,
      entity: 'entry',
      targetId: 'kg',
      payload: entry('kg'),
      reason: 'Test',
      occurredAt: now,
    );
    if (state != 'pending') {
      await db.update(CatalogSyncJournal.outbox, {'state': state});
    }
  }

  test(
    'opening status performs no network read or send; units are reviewable',
    () async {
      await db.insert(SqliteCompanyCatalog.entriesTable, entry('kg'));
      final s = await workspace.load();
      expect(remote.events, isEmpty);
      expect(s.unpublished.single.targetId, 'kg');
      expect(s.labels['entry/kg'], 'KG · kg');
    },
  );
  test('manual sync recovers receipts before sending then downloads', () async {
    await pending();
    expect(await workspace.synchronize(), isTrue);
    expect(remote.events, [
      'receipt',
      'send',
      'download:entry:false',
      'download:request:true',
    ]);
    expect((await workspace.load()).counts['acked'], 1);
  });
  test(
    'unconfirmed rejection never reports synchronization complete',
    () async {
      await pending(state: 'blocked');
      expect(await workspace.synchronize(), isFalse);
      expect(remote.events, contains('receipt'));
      expect(remote.events, isNot(contains('send')));
    },
  );
  test(
    'network uncertainty leaves operation pending and stops download',
    () async {
      await pending();
      remote.unavailable = true;
      await expectLater(
        workspace.synchronize(),
        throwsA(isA<CatalogSyncUnavailable>()),
      );
      expect((await workspace.load()).counts['pending'], 1);
      expect(remote.events, isNot(contains('download:entry:false')));
    },
  );
  test(
    'restore barrier allows download but no receipt recovery or send',
    () async {
      await pending();
      await db.insert(CatalogSyncJournal.device, {
        'farm_id': 'farm',
        'restore_blocked': 1,
      });
      expect(await workspace.synchronize(), isFalse);
      expect(remote.events, ['download:entry:false', 'download:request:true']);
      final s = await workspace.load();
      expect(s.restoreBlocked, isTrue);
      expect(s.unpublished, isEmpty);
      expect(s.farmUnresolved, 1);
    },
  );
  test('staff sees own queue only and cannot prepare publication', () async {
    await pending();
    current = actor(uid: 'staff', manage: false);
    remote.uid = 'staff';
    final s = await workspace.load();
    expect(s.counts.values.fold<int>(0, (a, b) => a + b), 0);
    expect(s.canManage, isFalse);
    expect(s.unpublished, isEmpty);
    await expectLater(
      workspace.prepare(
        CatalogPublicationReview.fromRow(entry('kg')),
        'review',
      ),
      throwsA(isA<CatalogFailure>()),
    );
  });
  test('session mismatch denies status and sends nothing', () async {
    await pending();
    remote.uid = 'other';
    await expectLater(workspace.synchronize(), throwsA(isA<CatalogFailure>()));
    expect(remote.events, isEmpty);
  });
  test(
    'restore local-only approval retains business data and requires separate publication',
    () async {
      await db.insert(SqliteCompanyCatalog.entriesTable, entry('kg'));
      await db.insert(CatalogSyncJournal.device, {
        'farm_id': 'farm',
        'restore_blocked': 1,
      });
      final review = await workspace.reviewRestore();
      expect(review.localOnly, ['entry/kg']);
      await workspace.releaseRestore(review, 'Retain test catalog locally', {
        'entry/kg',
      });
      final status = await workspace.load();
      expect(status.restoreBlocked, isFalse);
      expect(status.unpublished.single.targetId, 'kg');
      expect(await db.query(CatalogSyncJournal.outbox), isEmpty);
      await workspace.prepare(
        status.unpublished.single,
        'Reviewed publication',
      );
      expect((await workspace.load()).counts['pending'], 1);
      expect(remote.events, isNot(contains('send')));
    },
  );
  test('staff cannot obtain a restore approval review', () async {
    current = actor(manage: false);
    await expectLater(
      workspace.reviewRestore(),
      throwsA(isA<CatalogFailure>()),
    );
    expect(remote.events, isEmpty);
  });
  test(
    'duplicate action is rejected while send waits; disposal prevents acknowledgment',
    () async {
      await pending();
      remote.gate = Completer<void>();
      final running = workspace.synchronize();
      while (!remote.events.contains('send')) {
        await Future<void>.delayed(Duration.zero);
      }
      await expectLater(workspace.load(), throwsA(isA<CatalogFailure>()));
      workspace.dispose();
      remote.gate!.complete();
      await expectLater(running, throwsA(isA<CatalogFailure>()));
      expect(
        (await db.query(CatalogSyncJournal.outbox)).single['state'],
        'pending',
      );
    },
  );
}
