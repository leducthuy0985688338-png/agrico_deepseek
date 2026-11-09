import 'dart:async';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestTransport implements CatalogSyncTransport {
  String? uid = 'admin';
  final commands = <CatalogSyncCommand>[];
  final receipts = <String, CatalogSyncReceipt>{};
  final versions = <String, int>{};
  Future<CatalogSyncReceipt> Function(CatalogSyncCommand)? behavior;
  int commits = 0;

  @override
  Future<String?> currentUserId() async => uid;

  CatalogSyncReceipt commit(CatalogSyncCommand command) {
    final existing = receipts[command.operationId];
    if (existing != null) {
      return existing;
    }
    final key = '${command.farmId}/${command.entity}/${command.targetId}';
    if ((versions[key] ?? 0) != command.baseVersion) {
      throw const CatalogSyncRejected('catalog.changed', conflict: true);
    }
    final receipt = CatalogSyncReceipt(
      operationId: command.operationId,
      farmId: command.farmId,
      actorUid: command.actorUid,
      entity: command.entity,
      targetId: command.targetId,
      cloudVersion: command.newVersion,
      payload: command.payload,
    );
    receipts[command.operationId] = receipt;
    versions[key] = command.newVersion;
    commits++;
    return receipt;
  }

  @override
  Future<CatalogSyncReceipt> send(CatalogSyncCommand command) async {
    commands.add(command);
    return behavior == null ? commit(command) : await behavior!(command);
  }
}

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject actor({String uid = 'admin', bool active = true}) =>
      AuthorizationSubject(
        userId: uid,
        membershipId: uid,
        farmId: 'farm',
        active: active,
        validUntil: now.add(const Duration(days: 7)),
        permissionCodes: {
          PermissionCodes.cloudSync,
          PermissionCodes.catalogView,
          PermissionCodes.catalogManage,
          PermissionCodes.catalogRequest,
        },
        dataScopes: {DataScope.allFarm},
      );
  late Database db;
  late CatalogSyncJournal journal;
  late TestTransport transport;
  late AuthorizationSubject current;
  late CatalogSyncSender sender;
  Future<void> append({String target = 'unit', String uid = 'admin'}) =>
      db.transaction(
        (tx) => CatalogSyncJournal.append(
          tx,
          farmId: 'farm',
          actorUid: uid,
          entity: 'entry',
          targetId: target,
          payload: {'id': target, 'farm_id': 'farm', 'name': 'Kilogram'},
          reason: 'Test transport',
          occurredAt: now,
        ),
      );
  Future<Map<String, int>> counts() => journal.counts('farm', 'admin');
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.transaction(CatalogSyncJournal.createSchema);
    journal = CatalogSyncJournal(db);
    transport = TestTransport();
    current = actor();
    sender = CatalogSyncSender(
      journal: journal,
      transport: transport,
      subject: () => current,
      clock: () => now,
    );
  });
  tearDown(() async {
    sender.dispose();
    await db.close();
  });

  test('success drains dependent versions in order', () async {
    await append();
    await append();
    final result = await sender.synchronize();
    expect(result.acknowledged, 2);
    expect(transport.commands.map((c) => c.baseVersion), [0, 1]);
    expect(await counts(), {'acked': 2});
  });

  test('network outage preserves exact operation for next run', () async {
    await append();
    transport.behavior = (_) async => throw const CatalogSyncUnavailable();
    expect((await sender.synchronize()).unavailable, isTrue);
    expect(await counts(), {'pending': 1});
    final firstId = transport.commands.single.operationId;
    transport.behavior = null;
    expect((await sender.synchronize()).acknowledged, 1);
    expect(transport.commands.last.operationId, firstId);
  });

  test(
    'lost response after commit does not create a second remote change',
    () async {
      await append();
      transport.behavior = (command) async {
        transport.commit(command);
        throw const CatalogSyncUnavailable();
      };
      await sender.synchronize();
      expect(transport.commits, 1);
      expect(await counts(), {'pending': 1});
      transport.behavior = null;
      await sender.synchronize();
      expect(transport.commits, 1);
      expect(await counts(), {'acked': 1});
    },
  );

  test('conflict blocks dependent chain but sends independent entry', () async {
    await append();
    await append();
    await append(target: 'other');
    transport.versions['farm/entry/unit'] = 9;
    final result = await sender.synchronize();
    expect(result.conflicts, 1);
    expect(result.acknowledged, 1);
    expect(await counts(), {'conflict': 1, 'pending': 1, 'acked': 1});
    expect(transport.commands.map((c) => c.targetId), ['unit', 'other']);
  });

  test('definitive denial is retained as blocked', () async {
    await append();
    transport.behavior = (_) async =>
        throw const CatalogSyncRejected('catalog.denied', conflict: false);
    expect((await sender.synchronize()).blocked, 1);
    expect(await counts(), {'blocked': 1});
  });

  test('SDK auth mismatch never sends local actor command', () async {
    await append();
    transport.uid = 'other';
    expect((await sender.synchronize()).sessionChanged, isTrue);
    expect(transport.commands, isEmpty);
    expect(await counts(), {'pending': 1});
  });

  test(
    'logout after server commit leaves receipt reconciliation pending',
    () async {
      await append();
      transport.behavior = (command) async {
        final receipt = transport.commit(command);
        current = actor(uid: 'other');
        transport.uid = 'other';
        return receipt;
      };
      expect((await sender.synchronize()).sessionChanged, isTrue);
      expect(await counts(), {'pending': 1});
      current = actor();
      transport.uid = 'admin';
      transport.behavior = null;
      await sender.synchronize();
      expect(transport.commits, 1);
      expect(await counts(), {'acked': 1});
    },
  );

  test('forged receipt identity cannot acknowledge', () async {
    await append();
    transport.behavior = (command) async => CatalogSyncReceipt(
      operationId: 'other-operation',
      farmId: command.farmId,
      actorUid: command.actorUid,
      entity: command.entity,
      targetId: command.targetId,
      cloudVersion: command.newVersion,
      payload: command.payload,
    );
    await expectLater(sender.synchronize(), throwsA(isA<CatalogFailure>()));
    expect(await counts(), {'pending': 1});
  });

  test('forged payload cannot acknowledge', () async {
    await append();
    transport.behavior = (command) async => CatalogSyncReceipt(
      operationId: command.operationId,
      farmId: command.farmId,
      actorUid: command.actorUid,
      entity: command.entity,
      targetId: command.targetId,
      cloudVersion: command.newVersion,
      payload: {...command.payload, 'name': 'Forged'},
    );
    await expectLater(sender.synchronize(), throwsA(isA<CatalogFailure>()));
    expect(await counts(), {'pending': 1});
  });

  test('concurrent calls share one in-flight send', () async {
    await append();
    final entered = Completer<void>();
    final released = Completer<void>();
    transport.behavior = (command) async {
      entered.complete();
      await released.future;
      return transport.commit(command);
    };
    final first = sender.synchronize();
    await entered.future;
    final second = sender.synchronize();
    expect(identical(first, second), isTrue);
    released.complete();
    await Future.wait([first, second]);
    expect(transport.commands, hasLength(1));
  });

  test('permission loss is checked before the next queued command', () async {
    await append();
    await append(target: 'other');
    transport.behavior = (command) async {
      current = actor(active: false);
      return transport.commit(command);
    };
    await expectLater(sender.synchronize(), throwsA(isA<CatalogFailure>()));
    expect(transport.commands, hasLength(1));
    expect(await counts(), {'acked': 1, 'pending': 1});
  });

  test('dispose during send leaves pending and rejects new runs', () async {
    await append();
    transport.behavior = (command) async {
      sender.dispose();
      return transport.commit(command);
    };
    expect((await sender.synchronize()).sessionChanged, isTrue);
    expect(await counts(), {'pending': 1});
    await expectLater(sender.synchronize(), throwsA(isA<CatalogFailure>()));
  });

  test('unexpected error preserves pending and releases coordinator', () async {
    await append();
    transport.behavior = (_) async => throw StateError('unexpected');
    await expectLater(sender.synchronize(), throwsStateError);
    expect(await counts(), {'pending': 1});
    transport.behavior = null;
    expect((await sender.synchronize()).acknowledged, 1);
  });

  test('operation budget limits one run', () async {
    await append();
    await append();
    sender.dispose();
    sender = CatalogSyncSender(
      journal: journal,
      transport: transport,
      subject: () => current,
      clock: () => now,
      maxOperations: 1,
    );
    expect((await sender.synchronize()).acknowledged, 1);
    expect(await counts(), {'acked': 1, 'pending': 1});
  });

  test('restore barrier prevents transport access', () async {
    await append();
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    await expectLater(sender.synchronize(), throwsA(isA<CatalogFailure>()));
    expect(transport.commands, isEmpty);
  });
}
