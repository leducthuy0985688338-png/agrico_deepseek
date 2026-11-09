import 'dart:convert';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CatalogSyncJournal journal;
  final now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject actor(
    String uid, {
    bool manager = true,
    bool active = true,
    String farm = 'farm',
    Set<String> denies = const {},
  }) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: farm,
    active: active,
    validUntil: DateTime.utc(2026, 10, 10),
    permissionScopes: {
      for (final permission in denies) permission: <DataScope>{},
    },
    permissionCodes: {
      PermissionCodes.cloudSync,
      PermissionCodes.catalogView,
      PermissionCodes.catalogRequest,
      if (manager) PermissionCodes.catalogManage,
    },
    dataScopes: {DataScope.allFarm},
  );
  Future<void> append(
    String uid, {
    String id = 'entry',
    String entity = 'entry',
    String status = 'pending',
    String farm = 'farm',
  }) => db.transaction(
    (tx) => CatalogSyncJournal.append(
      tx,
      farmId: farm,
      actorUid: uid,
      entity: entity,
      targetId: id,
      payload: {'id': id, 'farm_id': farm, 'status': status},
      reason: 'Test queue',
      occurredAt: now,
    ),
  );
  Future<List<Map<String, Object?>>> pending(AuthorizationSubject a) =>
      journal.pending(a, clock: () => now);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.transaction(CatalogSyncJournal.createSchema);
    journal = CatalogSyncJournal(db);
  });
  tearDown(() => db.close());

  test(
    'actor and farm separation; inactive/expired/denied cannot send',
    () async {
      await append('admin');
      expect(await pending(actor('other')), isEmpty);
      expect(await pending(actor('admin', farm: 'other-farm')), isEmpty);
      expect(
        () => pending(actor('admin', active: false)),
        throwsA(isA<CatalogFailure>()),
      );
      expect(
        () => pending(actor('admin', denies: {PermissionCodes.cloudSync})),
        throwsA(isA<CatalogFailure>()),
      );
      expect(
        () => journal.pending(
          actor('admin'),
          clock: () => DateTime.utc(2026, 11),
        ),
        throwsA(isA<CatalogFailure>()),
      );
    },
  );
  test(
    'staff sends own suggestion but cannot publish a master or approval',
    () async {
      await append('worker');
      await append('worker', id: 'suggestion', entity: 'request');
      await append(
        'worker',
        id: 'approval',
        entity: 'request',
        status: 'approved',
      );
      final rows = await pending(actor('worker', manager: false));
      expect(rows.map((r) => r['target_id']), ['suggestion']);
    },
  );
  test('business rollback also rolls back its outbox mutation', () async {
    await SqliteCompanyCatalog.createSchema(db);
    final service = CompanyCatalogService(
      repository: SqliteCompanyCatalog(db),
      subject: actor('admin'),
      clock: () => now,
    );
    await service.save(
      const CatalogEntry(
        id: 'unit',
        farmId: 'farm',
        kind: CatalogKind.unit,
        code: 'KG',
        name: 'kg',
      ),
      expectedRevision: null,
      reason: 'Standard',
    );
    expect((await db.query(CatalogSyncJournal.outbox)), hasLength(1));
    await expectLater(
      db.transaction((tx) async {
        await CatalogSyncJournal.append(
          tx,
          farmId: 'farm',
          actorUid: 'admin',
          entity: 'entry',
          targetId: 'rollback',
          payload: {'id': 'rollback', 'farm_id': 'farm'},
          reason: 'Rollback',
          occurredAt: now,
        );
        throw StateError('simulate transaction failure');
      }),
      throwsStateError,
    );
    expect((await db.query(CatalogSyncJournal.outbox)), hasLength(1));
  });
  test(
    'sequential revisions, acknowledgement releases only the next mutation',
    () async {
      await append('admin');
      await append('admin');
      final first = (await pending(actor('admin'))).single;
      expect(first['base_version'], 0);
      expect(first['new_version'], 1);
      final body = Map<String, Object?>.from(
        jsonDecode(first['payload_json'] as String) as Map,
      );
      await journal.acknowledge(first['operation_id'] as String, 1, body);
      final second = (await pending(actor('admin'))).single;
      expect(second['base_version'], 1);
      expect(second['new_version'], 2);
      expect(second['operation_id'], isNot(first['operation_id']));
      await journal.acknowledge(first['operation_id'] as String, 1, body);
      expect(
        (await pending(actor('admin'))).single['operation_id'],
        second['operation_id'],
      );
    },
  );
  test('bad receipts cannot advance shadow or remove pending writes', () async {
    await append('admin');
    final first = (await pending(actor('admin'))).single;
    final id = first['operation_id'] as String;
    final body = Map<String, Object?>.from(
      jsonDecode(first['payload_json'] as String) as Map,
    );
    await expectLater(
      journal.acknowledge(id, 2, body),
      throwsA(isA<CatalogFailure>()),
    );
    await expectLater(
      journal.acknowledge(id, 1, {...body, 'id': 'another'}),
      throwsA(isA<CatalogFailure>()),
    );
    expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
    expect(await pending(actor('admin')), hasLength(1));
  });
  test(
    'network retry keeps identity; conflict blocks dependent writes only',
    () async {
      await append('admin');
      await append('admin');
      await append('admin', id: 'other');
      final original = (await pending(actor('admin'))).first;
      expect(
        (await pending(actor('admin'))).first['operation_id'],
        original['operation_id'],
      );
      await journal.fail(
        original['operation_id'] as String,
        conflict: true,
        code: 'changed',
      );
      expect((await pending(actor('admin'))).map((r) => r['target_id']), [
        'other',
      ]);
      expect((await journal.counts('farm', 'admin'))['conflict'], 1);
    },
  );
  test('an unsent change by another actor is an ordering barrier', () async {
    await append('first');
    await append('second');
    expect(await pending(actor('second')), isEmpty);
    expect(await pending(actor('first')), hasLength(1));
  });
  test(
    'restored device cannot send until authoritative reconciliation',
    () async {
      await append('admin');
      await db.insert(CatalogSyncJournal.device, {
        'farm_id': 'farm',
        'restore_blocked': 1,
      });
      expect(() => pending(actor('admin')), throwsA(isA<CatalogFailure>()));
      expect((await journal.counts('farm', 'admin'))['pending'], 1);
    },
  );
}
