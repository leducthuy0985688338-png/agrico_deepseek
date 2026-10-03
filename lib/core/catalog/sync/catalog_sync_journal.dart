import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../permissions/authorization.dart';
import '../company_catalog.dart';

/// Device-only protocol state. Backups deliberately do not carry send authority.
class CatalogSyncJournal {
  const CatalogSyncJournal(this.database);
  final Database database;
  static const outbox = 'company_catalog_sync_outbox_v1';
  static const shadow = 'company_catalog_sync_shadow_v1';
  static const device = 'company_catalog_sync_device_v1';
  static const tables = {outbox, shadow, device};

  static Future<void> createSchema(DatabaseExecutor tx) async {
    await tx.execute('''CREATE TABLE IF NOT EXISTS $outbox (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT NOT NULL UNIQUE,
      farm_id TEXT NOT NULL, actor_uid TEXT NOT NULL,
      entity TEXT NOT NULL CHECK(entity IN ('entry','request')),
      target_id TEXT NOT NULL,
      base_version INTEGER NOT NULL CHECK(base_version >= 0),
      new_version INTEGER NOT NULL CHECK(new_version = base_version + 1),
      payload_json TEXT NOT NULL, reason TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','acked','conflict','blocked')),
      failure TEXT)''');
    await tx.execute('''CREATE TABLE IF NOT EXISTS $shadow (
      farm_id TEXT NOT NULL, entity TEXT NOT NULL, target_id TEXT NOT NULL,
      cloud_version INTEGER NOT NULL CHECK(cloud_version > 0),
      operation_id TEXT NOT NULL, payload_json TEXT NOT NULL,
      PRIMARY KEY(farm_id,entity,target_id))''');
    await tx.execute('''CREATE TABLE IF NOT EXISTS $device (
      farm_id TEXT PRIMARY KEY, restore_blocked INTEGER NOT NULL DEFAULT 0
      CHECK(restore_blocked IN (0,1)))''');
    await tx.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_sync_actor ON '
      '$outbox(farm_id,actor_uid,state,sequence)',
    );
  }

  static Future<void> append(
    DatabaseExecutor tx, {
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
    required Map<String, Object?> payload,
    required String reason,
    required DateTime occurredAt,
  }) async {
    if (!{'entry', 'request'}.contains(entity) ||
        farmId.isEmpty ||
        actorUid.isEmpty ||
        targetId.isEmpty ||
        payload['farm_id'] != farmId ||
        payload['id'] != targetId ||
        reason.trim().isEmpty ||
        reason.length > 500) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    final previous = await tx.query(
      outbox,
      where: 'farm_id=? AND entity=? AND target_id=? AND state<>?',
      whereArgs: [farmId, entity, targetId, 'acked'],
      orderBy: 'sequence DESC',
      limit: 1,
    );
    final remote = await tx.query(
      shadow,
      where: 'farm_id=? AND entity=? AND target_id=?',
      whereArgs: [farmId, entity, targetId],
    );
    final base = previous.isNotEmpty
        ? previous.single['new_version'] as int
        : remote.isEmpty
        ? 0
        : remote.single['cloud_version'] as int;
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}';
    await tx.insert(outbox, {
      'operation_id': id,
      'farm_id': farmId,
      'actor_uid': actorUid,
      'entity': entity,
      'target_id': targetId,
      'base_version': base,
      'new_version': base + 1,
      'payload_json': jsonEncode(payload),
      'reason': reason.trim(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
    });
  }

  void _require(
    AuthorizationSubject subject,
    String permission, {
    DateTime Function()? clock,
    bool own = false,
  }) {
    if (!AuthorizationService(clock: clock).can(
      subject: subject,
      permission: permission,
      resource: ResourceContext(
        farmId: subject.farmId,
        ownerUserId: own ? subject.userId : null,
      ),
    )) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  /// Return only the first unresolved mutation per entity, owned by this actor.
  /// A blocked/conflicted earlier mutation (even by another actor) is a barrier.
  Future<List<Map<String, Object?>>> pending(
    AuthorizationSubject subject, {
    DateTime Function()? clock,
  }) async {
    _require(subject, PermissionCodes.cloudSync, clock: clock, own: true);
    final blocked = await database.query(
      device,
      where: 'farm_id=? AND restore_blocked=1',
      whereArgs: [subject.farmId],
    );
    if (blocked.isNotEmpty) {
      throw const CatalogFailure('catalog.restoreReconcileRequired');
    }
    final rows = await database.rawQuery(
      '''SELECT q.* FROM $outbox q
      WHERE q.farm_id=? AND q.actor_uid=? AND q.state='pending'
      AND NOT EXISTS (SELECT 1 FROM $outbox p
        WHERE p.farm_id=q.farm_id AND p.entity=q.entity AND p.target_id=q.target_id
        AND p.sequence<q.sequence AND p.state<>'acked')
      ORDER BY q.sequence LIMIT 100''',
      [subject.farmId, subject.userId],
    );
    return rows
        .where((row) {
          final isRequest = row['entity'] == 'request';
          final payload = jsonDecode(row['payload_json'] as String) as Map;
          final permission = isRequest && payload['status'] == 'pending'
              ? PermissionCodes.catalogRequest
              : PermissionCodes.catalogManage;
          return AuthorizationService(clock: clock).can(
            subject: subject,
            permission: permission,
            resource: ResourceContext(
              farmId: subject.farmId,
              ownerUserId: isRequest ? subject.userId : null,
            ),
          );
        })
        .toList(growable: false);
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    return value;
  }

  /// A transport must supply an authoritative receipt for this immutable operation.
  Future<void> acknowledge(
    String operationId,
    int cloudVersion,
    Map<String, Object?> acceptedPayload,
  ) async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        outbox,
        where: 'operation_id=?',
        whereArgs: [operationId],
      );
      if (rows.length != 1) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
      final row = rows.single;
      final payload = jsonDecode(row['payload_json'] as String) as Map;
      if (cloudVersion != row['new_version'] ||
          jsonEncode(_canonical(payload)) !=
              jsonEncode(_canonical(acceptedPayload)) ||
          !{'pending', 'acked'}.contains(row['state'])) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
      if (row['state'] == 'acked') {
        return;
      }
      final prior = await tx.query(
        shadow,
        where: 'farm_id=? AND entity=? AND target_id=?',
        whereArgs: [row['farm_id'], row['entity'], row['target_id']],
      );
      final base = prior.isEmpty ? 0 : prior.single['cloud_version'];
      if (base != row['base_version']) {
        throw const CatalogFailure('catalog.changed');
      }
      await tx.insert(shadow, {
        'farm_id': row['farm_id'],
        'entity': row['entity'],
        'target_id': row['target_id'],
        'cloud_version': cloudVersion,
        'operation_id': operationId,
        'payload_json': row['payload_json'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        outbox,
        {'state': 'acked', 'failure': null},
        where: 'operation_id=?',
        whereArgs: [operationId],
      );
    });
  }

  Future<void> fail(
    String operationId, {
    required bool conflict,
    required String code,
  }) async {
    final count = await database.update(
      outbox,
      {'state': conflict ? 'conflict' : 'blocked', 'failure': code},
      where: 'operation_id=? AND state=?',
      whereArgs: [operationId, 'pending'],
    );
    if (count != 1) {
      throw const CatalogFailure('catalog.changed');
    }
  }

  /// Network failures do not call fail(): the exact operation stays pending.
  Future<Map<String, int>> counts(String farmId, String actorUid) async {
    final rows = await database.rawQuery(
      'SELECT state,COUNT(*) AS n FROM '
      '$outbox WHERE farm_id=? AND actor_uid=? GROUP BY state',
      [farmId, actorUid],
    );
    return {for (final r in rows) r['state'] as String: r['n'] as int};
  }
}
