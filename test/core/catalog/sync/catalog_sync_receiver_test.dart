import 'dart:async';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_receiver.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Remote implements CatalogReceiveTransport {
  String? uid = 'admin';
  final calls = <Map<String, Object?>>[];
  Future<CatalogRemotePage> Function(String, String?, bool)? read;
  @override
  Future<String?> currentUserId() async => uid;
  @override
  Future<CatalogRemotePage> fetch({
    required String farmId,
    required String actorUid,
    required String entity,
    required bool allRequests,
    required int limit,
    String? cursor,
  }) async {
    calls.add({
      'entity': entity,
      'cursor': cursor,
      'all': allRequests,
      'uid': actorUid,
    });
    return read == null
        ? CatalogRemotePage(records: [])
        : await read!(entity, cursor, allRequests);
  }
}

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject actor(
    String uid, {
    bool manager = true,
    bool active = true,
  }) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: 'farm',
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
    String farm = 'farm',
    String name = 'Kilogram',
  }) => {
    'id': id,
    'farm_id': farm,
    'kind': 'unit',
    'code': id.toUpperCase(),
    'name': name,
    'name_key': SqliteCompanyCatalog.nameKey(name),
    'unit_id': null,
    'active': 1,
    'revision': 1,
  };
  CatalogRemoteRecord record(
    String id, {
    int version = 1,
    String? op,
    String farm = 'farm',
    String name = 'Kilogram',
  }) => CatalogRemoteRecord(
    farmId: farm,
    entity: 'entry',
    targetId: id,
    version: version,
    operationId: op ?? 'op-$version-$id',
    payload: payload(id, farm: farm, name: name),
  );
  CatalogRemoteRecord request(String uid) => CatalogRemoteRecord(
    farmId: 'farm',
    entity: 'request',
    targetId: 'req',
    version: 1,
    operationId: 'req-op',
    payload: {
      'id': 'req',
      'farm_id': 'farm',
      'actor_uid': uid,
      'kind': 'unit',
      'code': 'KG',
      'name': 'Kilogram',
      'reason': 'Needed',
      'created_at': now.toIso8601String(),
      'status': 'pending',
    },
  );
  late Database db;
  late CatalogSyncInbox inbox;
  late Remote remote;
  late CatalogSyncReceiver receiver;
  AuthorizationSubject? subject;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteCompanyCatalog.createSchema(db);
    inbox = CatalogSyncInbox(db);
    remote = Remote();
    subject = actor('admin');
    receiver = CatalogSyncReceiver(
      inbox: inbox,
      transport: remote,
      currentSubject: () => subject,
      clock: () => now,
    );
  });
  tearDown(() => db.close());
  Future<void> stage(
    List<CatalogRemoteRecord> rows, {
    String reader = 'admin',
    bool all = true,
    void Function()? authorize,
  }) => inbox.stage(
    rows,
    farmId: 'farm',
    readerUid: reader,
    allRequests: all,
    authorize: authorize ?? () {},
  );
  test(
    'immutable envelopes reject invalid canonical values and identities',
    () {
      final p = payload('kg');
      final r = CatalogRemoteRecord(
        farmId: 'farm',
        entity: 'entry',
        targetId: 'kg',
        version: 1,
        operationId: 'op',
        payload: p,
      );
      p['name'] = 'changed';
      r.payload['name'] = 'changed again';
      expect(r.payload['name'], 'Kilogram');
      for (final change in [
        {'active': true},
        {'revision': 0},
        {'name_key': 'spoof'},
        {'extra': 1},
        {'kind': 'unknown'},
      ]) {
        expect(
          () => CatalogRemoteRecord(
            farmId: 'farm',
            entity: 'entry',
            targetId: 'kg',
            version: 1,
            operationId: 'op',
            payload: {...payload('kg'), ...change},
          ),
          throwsA(isA<CatalogFailure>()),
        );
      }
    },
  );
  test('atomic stage rolls back a mixed farm page', () async {
    await expectLater(
      stage([record('a'), record('b', farm: 'other')]),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await inbox.staged('farm', 'admin'), isEmpty);
  });
  test(
    'same version replay is idempotent; changed receipt rolls back page',
    () async {
      await stage([record('a')]);
      await stage([record('a')]);
      await expectLater(
        stage([record('b'), record('a', op: 'forged')]),
        throwsA(isA<CatalogFailure>()),
      );
      expect((await inbox.staged('farm', 'admin')).length, 1);
    },
  );
  test('newer remote replaces staging; older page cannot regress it', () async {
    await stage([record('a', version: 3)]);
    await stage([record('a', version: 1)]);
    expect((await inbox.staged('farm', 'admin')).single['cloud_version'], 3);
  });
  test(
    'foreign actor dirty queue is retained; receiving never acknowledges or advances shadow',
    () async {
      await db.transaction(
        (tx) => CatalogSyncJournal.append(
          tx,
          farmId: 'farm',
          actorUid: 'other',
          entity: 'entry',
          targetId: 'a',
          payload: payload('a'),
          reason: 'Offline',
          occurredAt: now,
        ),
      );
      await stage([record('a', version: 2)]);
      expect((await inbox.staged('farm', 'admin')).single['locally_dirty'], 1);
      expect(
        (await db.query(CatalogSyncJournal.outbox)).single['state'],
        'pending',
      );
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect(await db.query(SqliteCompanyCatalog.entriesTable), isEmpty);
    },
  );
  test('private suggestions and inbox readers remain isolated', () async {
    await expectLater(
      stage([request('other')], reader: 'staff', all: false),
      throwsA(isA<CatalogFailure>()),
    );
    await stage([request('staff')], reader: 'staff', all: false);
    expect(await inbox.staged('farm', 'admin'), isEmpty);
    expect((await inbox.staged('farm', 'staff')).length, 1);
  });
  test(
    'authorization rechecked inside transaction rolls back staged writes',
    () async {
      var calls = 0;
      await expectLater(
        stage(
          [record('a')],
          authorize: () {
            if (++calls == 2) {
              throw const CatalogFailure('catalog.denied');
            }
          },
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(await inbox.staged('farm', 'admin'), isEmpty);
    },
  );
  test(
    'bounded pages resume from start without claiming complete farm snapshot',
    () async {
      remote.read = (e, c, a) async => e == 'entry'
          ? CatalogRemotePage(
              records: [record(c == null ? 'a' : 'b')],
              nextCursor: c == null ? 'a' : null,
            )
          : CatalogRemotePage(records: []);
      final result = await receiver.receive(pageSize: 1, maxPages: 1);
      expect(result.complete, isFalse);
      expect(result.records, 1);
      final retry = await receiver.receive(pageSize: 1);
      expect(retry.complete, isTrue);
      expect(retry.records, 2);
      expect((await inbox.staged('farm', 'admin')).length, 2);
    },
  );
  test('staff transport requests own suggestions only', () async {
    subject = actor('staff', manager: false);
    remote.uid = 'staff';
    remote.read = (e, c, a) async =>
        CatalogRemotePage(records: e == 'request' ? [request('staff')] : []);
    expect((await receiver.receive()).complete, isTrue);
    expect(remote.calls.last['all'], isFalse);
    expect(remote.calls.last['uid'], 'staff');
  });
  test('SDK mismatch and lost network never stage a false success', () async {
    remote.uid = 'other';
    await expectLater(
      receiver.receive(),
      throwsA(isA<CatalogSyncUnavailable>()),
    );
    remote.uid = 'admin';
    remote.read = (e, c, a) async => throw const CatalogSyncUnavailable();
    await expectLater(
      receiver.receive(),
      throwsA(isA<CatalogSyncUnavailable>()),
    );
    expect(await inbox.staged('farm', 'admin'), isEmpty);
  });
  test('signout while waiting rejects page before any local write', () async {
    final gate = Completer<CatalogRemotePage>();
    remote.read = (e, c, a) => gate.future;
    final future = receiver.receive();
    final expectation = expectLater(future, throwsA(isA<CatalogFailure>()));
    await Future<void>.delayed(Duration.zero);
    subject = null;
    gate.complete(CatalogRemotePage(records: [record('a')]));
    await expectation;
    expect(await inbox.staged('farm', 'admin'), isEmpty);
  });
  test(
    'disposal and permission revocation during fetch retain prior staged pages',
    () async {
      await stage([record('prior')]);
      remote.read = (e, c, a) async {
        subject = actor('admin', active: false);
        return CatalogRemotePage(records: [record('a')]);
      };
      await expectLater(receiver.receive(), throwsA(isA<CatalogFailure>()));
      expect(
        (await inbox.staged('farm', 'admin')).single['target_id'],
        'prior',
      );
      subject = actor('admin');
      receiver.dispose();
      await expectLater(receiver.receive(), throwsA(isA<CatalogFailure>()));
    },
  );
  test('concurrent receive callers share one download', () async {
    final gate = Completer<CatalogRemotePage>();
    remote.read = (e, c, a) => e == 'entry'
        ? gate.future
        : Future.value(CatalogRemotePage(records: []));
    final first = receiver.receive(), second = receiver.receive();
    expect(identical(first, second), isTrue);
    gate.complete(CatalogRemotePage(records: [record('a')]));
    await first;
    expect(remote.calls.length, 2);
  });
  test('unordered, oversized or dishonest cursor pages are rejected', () async {
    for (final page in [
      CatalogRemotePage(records: [record('b'), record('a')]),
      CatalogRemotePage(records: [record('a')], nextCursor: 'wrong'),
      CatalogRemotePage(records: [], nextCursor: 'a'),
    ]) {
      remote.read = (e, c, a) async => page;
      await expectLater(receiver.receive(), throwsA(isA<CatalogFailure>()));
    }
    expect(await inbox.staged('farm', 'admin'), isEmpty);
  });
  test('restore block remains set after receiving', () async {
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    await stage([record('a')]);
    expect(
      (await db.query(CatalogSyncJournal.device)).single['restore_blocked'],
      1,
    );
    expect(CatalogSyncJournal.tables, contains(CatalogSyncInbox.table));
  });
  test(
    'malformed request timestamps and unauthorized resolution are refused',
    () {
      for (final changes in [
        {'created_at': '2026-02-31T00:00:00.000Z'},
        {
          'status': 'approved',
          'entry_id': 'kg',
          'resolved_by': 'staff',
          'resolved_at': now.toIso8601String(),
          'resolution': 'Approved',
        },
        {'status': 'pending', 'entry_id': 'kg'},
        {'reason': '   '},
      ]) {
        expect(
          () => CatalogRemoteRecord(
            farmId: 'farm',
            entity: 'request',
            targetId: 'req',
            version: 1,
            operationId: 'op',
            payload: {...request('staff').payload, ...changes},
          ),
          throwsA(isA<CatalogFailure>()),
        );
      }
    },
  );
  test('oversized page rejected before staging', () async {
    remote.read = (e, c, a) async =>
        CatalogRemotePage(records: [record('a'), record('b')]);
    await expectLater(
      receiver.receive(pageSize: 1),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await inbox.staged('farm', 'admin'), isEmpty);
  });
  test('Firestore UTF8 ID order supports supplementary characters', () {
    expect(CatalogRemoteRecord.compareIds('\uE000', '😀'), lessThan(0));
  });
}
