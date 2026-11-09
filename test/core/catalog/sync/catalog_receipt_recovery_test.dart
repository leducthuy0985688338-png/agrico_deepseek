import 'dart:async';

import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_receipt_recovery.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> proof(CatalogSyncCommand c) => {
  'operationId': c.operationId,
  'farmId': c.farmId,
  'actorUid': c.actorUid,
  'entity': c.entity,
  'targetId': c.targetId,
  'baseVersion': c.baseVersion,
  'newVersion': c.newVersion,
  'payload': c.payload,
  'reason': c.reason,
  'occurredAt': c.occurredAt,
};

class TestLookup implements CatalogReceiptLookup {
  @override
  String? authenticatedUid = 'admin';
  Future<Map<String, Object?>?> Function(CatalogSyncCommand)? behavior;
  final commands = <CatalogSyncCommand>[];
  @override
  Future<Map<String, Object?>?> lookup(CatalogSyncCommand c) async {
    commands.add(c);
    return behavior == null ? proof(c) : await behavior!(c);
  }
}

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 5);
  AuthorizationSubject actor({String uid = 'admin', bool active = true}) =>
      AuthorizationSubject(
        userId: uid,
        membershipId: uid,
        farmId: 'farm',
        active: active,
        validUntil: now.add(const Duration(days: 7)),
        permissionCodes: {
          PermissionCodes.cloudSync,
          PermissionCodes.catalogManage,
        },
        dataScopes: {DataScope.allFarm},
      );
  late Database db;
  late CatalogSyncJournal journal;
  late TestLookup lookup;
  late AuthorizationSubject current;
  late CatalogReceiptRecovery recovery;
  Future<void> append({String uid = 'admin', String target = 'unit'}) =>
      db.transaction(
        (tx) => CatalogSyncJournal.append(
          tx,
          farmId: 'farm',
          actorUid: uid,
          entity: 'entry',
          targetId: target,
          payload: {'id': target, 'farm_id': 'farm', 'name': 'Kilogram'},
          reason: 'Test receipt',
          occurredAt: now,
        ),
      );
  Future<List<Map<String, Object?>>> rows() =>
      db.query(CatalogSyncJournal.outbox, orderBy: 'sequence');
  final invalid = throwsA(isA<CatalogFailure>());
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.transaction(CatalogSyncJournal.createSchema);
    journal = CatalogSyncJournal(db);
    lookup = TestLookup();
    current = actor();
    recovery = CatalogReceiptRecovery(
      journal: journal,
      lookup: lookup,
      subject: () => current,
      clock: () => now,
    );
  });
  tearDown(() async {
    recovery.dispose();
    await db.close();
  });

  test(
    'lost response recovered without resending or changing business data',
    () async {
      await append();
      final before = (await rows()).single;
      expect((await recovery.recover()).acknowledged, 1);
      final after = (await rows()).single;
      expect(after['state'], 'acked');
      expect(after['operation_id'], before['operation_id']);
      expect(after['payload_json'], before['payload_json']);
      expect(
        (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
        1,
      );
      expect((await recovery.recover()).acknowledged, 0);
    },
  );
  test(
    'absent receipt retains exact pending command and does not block independent recovery',
    () async {
      await append();
      await append(target: 'other');
      final first = (await rows()).first;
      lookup.behavior = (c) async => c.targetId == 'unit' ? null : proof(c);
      final result = await recovery.recover();
      expect(result.absent, 1);
      expect(result.acknowledged, 1);
      expect((await rows()).first, first);
    },
  );
  for (final state in ['blocked', 'conflict']) {
    test('verified receipt recovers $state with expected baseline', () async {
      await append();
      final id = (await rows()).single['operation_id'] as String;
      await journal.fail(
        id,
        conflict: state == 'conflict',
        code: 'catalog.denied',
      );
      expect((await recovery.recover()).acknowledged, 1);
      expect((await rows()).single['failure'], isNull);
    });
    test(
      'absent receipt preserves $state rejection and dependent barrier',
      () async {
        await append();
        final id = (await rows()).single['operation_id'] as String;
        await journal.fail(
          id,
          conflict: state == 'conflict',
          code: 'catalog.changed',
        );
        await append();
        final before = await rows();
        lookup.behavior = (_) async => null;
        expect((await recovery.recover()).absent, 1);
        expect(await rows(), before);
        expect(lookup.commands.length, 1);
      },
    );
  }
  test('dependent accepted receipts acknowledged in sequence', () async {
    await append();
    await append();
    expect((await recovery.recover()).acknowledged, 2);
    expect(lookup.commands.map((c) => c.baseVersion), [0, 1]);
  });
  test('another actors barrier and commands remain untouched', () async {
    await append(uid: 'other');
    await append();
    final before = await rows();
    expect((await recovery.recover()).acknowledged, 0);
    expect(await rows(), before);
    expect(lookup.commands, isEmpty);
  });
  test('network uncertainty preserves command', () async {
    await append();
    final before = await rows();
    lookup.behavior = (_) async => throw const CatalogSyncUnavailable();
    expect((await recovery.recover()).unavailable, isTrue);
    expect(await rows(), before);
  });
  test('every immutable proof field is checked', () async {
    await append();
    final c = CatalogSyncCommand.fromRow((await rows()).single);
    for (final key in proof(c).keys) {
      expect(
        () => CatalogReceiptRecovery.verify(c, {...proof(c), key: null}),
        invalid,
        reason: key,
      );
    }
    CatalogReceiptRecovery.verify(
      c,
      Map.fromEntries(proof(c).entries.toList().reversed),
    );
  });
  test('invalid server proof cannot acknowledge', () async {
    await append();
    lookup.behavior = (c) async => {...proof(c), 'reason': 'wrong'};
    await expectLater(recovery.recover(), invalid);
    expect((await rows()).single['state'], 'pending');
  });
  test('SDK UID mismatch stops before read', () async {
    await append();
    lookup.authenticatedUid = 'other';
    await expectLater(recovery.recover(), invalid);
    expect(lookup.commands, isEmpty);
  });
  test('logout during read retains pending command', () async {
    await append();
    lookup.behavior = (c) async {
      current = actor(uid: 'other');
      return proof(c);
    };
    await expectLater(recovery.recover(), invalid);
    expect((await rows()).single['state'], 'pending');
  });
  test('revocation during read retains command', () async {
    await append();
    lookup.behavior = (c) async {
      current = actor(active: false);
      return proof(c);
    };
    await expectLater(recovery.recover(), invalid);
    expect((await rows()).single['state'], 'pending');
  });
  test('restore barrier stops before read', () async {
    await append();
    await db.insert(CatalogSyncJournal.device, {
      'farm_id': 'farm',
      'restore_blocked': 1,
    });
    await expectLater(recovery.recover(), invalid);
    expect(lookup.commands, isEmpty);
  });
  test('shadow advancement never regresses or falsely acknowledges', () async {
    await append();
    await db.insert(CatalogSyncJournal.shadow, {
      'farm_id': 'farm',
      'entity': 'entry',
      'target_id': 'unit',
      'cloud_version': 9,
      'operation_id': 'newer',
      'payload_json': '{}',
    });
    await expectLater(recovery.recover(), invalid);
    expect(
      (await db.query(CatalogSyncJournal.shadow)).single['cloud_version'],
      9,
    );
    expect((await rows()).single['state'], 'pending');
  });
  test('overlapping calls share lookup and disposal blocks late ack', () async {
    await append();
    final gate = Completer<Map<String, Object?>?>();
    lookup.behavior = (_) => gate.future;
    final first = recovery.recover();
    final second = recovery.recover();
    expect(identical(first, second), isTrue);
    while (lookup.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    recovery.dispose();
    final expectation = expectLater(first, invalid);
    gate.complete(proof(lookup.commands.single));
    await expectation;
    expect((await rows()).single['state'], 'pending');
  });
  test(
    'authorization guard inside ack rolls back all protocol writes',
    () async {
      await append();
      final c = CatalogSyncCommand.fromRow((await rows()).single);
      var calls = 0;
      await expectLater(
        journal.acknowledgeRecovered(
          c.operationId,
          c.newVersion,
          c.payload,
          guard: () {
            if (++calls == 2) {
              throw const CatalogFailure('catalog.denied');
            }
          },
        ),
        invalid,
      );
      expect(await db.query(CatalogSyncJournal.shadow), isEmpty);
      expect((await rows()).single['state'], 'pending');
    },
  );
  test('bounded run keeps remaining commands for next run', () async {
    await append();
    await append();
    final bounded = CatalogReceiptRecovery(
      journal: journal,
      lookup: lookup,
      subject: () => current,
      clock: () => now,
      maxOperations: 1,
    );
    expect((await bounded.recover()).acknowledged, 1);
    expect((await rows()).last['state'], 'pending');
    bounded.dispose();
  });
}
