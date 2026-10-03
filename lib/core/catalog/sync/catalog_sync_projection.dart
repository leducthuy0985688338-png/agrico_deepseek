import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_receiver.dart';

class CatalogProjectionResult {
  const CatalogProjectionResult({
    required this.applied,
    required this.unchanged,
    required this.conflicts,
    required this.complete,
  });
  final int applied, unchanged, conflicts;
  final bool complete;
}

/// Apply only clean, validated staged records. Conflict decisions never discard
/// pending operations or impersonate their original actor.
class CatalogSyncProjection {
  CatalogSyncProjection({
    required this.database,
    required this.currentSubject,
    this.clock,
  });
  final Database database;
  final AuthorizationSubject? Function() currentSubject;
  final DateTime Function()? clock;
  Future<CatalogProjectionResult>? _running;
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  void _authorize(
    AuthorizationSubject original,
    String entity, {
    String? owner,
  }) {
    final s = currentSubject();
    if (_disposed ||
        s == null ||
        s.userId != original.userId ||
        s.farmId != original.farmId) {
      throw const CatalogFailure('catalog.denied');
    }
    final auth = AuthorizationService(clock: clock);
    final resource = ResourceContext(farmId: s.farmId, ownerUserId: s.userId);
    if (!auth.can(
          subject: s,
          permission: PermissionCodes.cloudSync,
          resource: resource,
        ) ||
        (entity == 'entry'
            ? !auth.can(
                subject: s,
                permission: PermissionCodes.catalogView,
                resource: ResourceContext(farmId: s.farmId),
              )
            : !(auth.can(
                    subject: s,
                    permission: PermissionCodes.catalogManage,
                    resource: ResourceContext(farmId: s.farmId),
                  ) ||
                  (owner == s.userId &&
                      auth.can(
                        subject: s,
                        permission: PermissionCodes.catalogRequest,
                        resource: resource,
                      ))))) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  static Map<String, Object?> _business(
    Map<String, Object?> p,
    String entity,
  ) => {
    for (final key
        in entity == 'entry'
            ? [
                'id',
                'farm_id',
                'kind',
                'code',
                'name',
                'name_key',
                'unit_id',
                'active',
              ]
            : [
                'id',
                'farm_id',
                'actor_uid',
                'kind',
                'code',
                'name',
                'reason',
                'created_at',
                'status',
                'entry_id',
                'resolved_by',
                'resolved_at',
                'resolution',
              ])
      key: p[key],
  };
  static bool _same(
    Map<String, Object?> a,
    Map<String, Object?> b,
    String entity,
  ) =>
      jsonEncode(CatalogSyncInbox.canonical(_business(a, entity))) ==
      jsonEncode(CatalogSyncInbox.canonical(_business(b, entity)));
  static Map<String, Object?> _decode(Object? json) =>
      (jsonDecode(json as String) as Map).cast<String, Object?>();
  Future<CatalogProjectionResult> apply({int maxRecords = 500}) {
    if (maxRecords < 1 || maxRecords > 5000) {
      throw ArgumentError('Invalid projection budget');
    }
    return _running ??= _apply(maxRecords).whenComplete(() {
      _running = null;
    });
  }

  Future<CatalogProjectionResult> _apply(int budget) async {
    final s = currentSubject();
    if (s == null) {
      throw const CatalogFailure('catalog.denied');
    }
    _authorize(s, 'entry');
    final rows = await database.query(
      CatalogSyncJournal.inbox,
      where: 'farm_id=? AND reader_uid=?',
      whereArgs: [s.farmId, s.userId],
      orderBy:
          r"CASE WHEN entity='request' THEN 3 WHEN json_extract(payload_json,'$.kind')='unit' AND json_extract(payload_json,'$.active')=1 THEN 0 WHEN json_extract(payload_json,'$.kind')='unit' THEN 2 ELSE 1 END, target_id",
      limit: budget + 1,
    );
    var applied = 0, unchanged = 0, conflicts = 0;
    for (final row in rows.take(budget)) {
      try {
        final changed = await _applyOne(s, row);
        if (changed) {
          applied++;
        } else {
          unchanged++;
        }
      } on CatalogFailure catch (e) {
        if (e.code == 'catalog.denied') {
          rethrow;
        }
        await _conflict(s, row, e.code);
        conflicts++;
      } on DatabaseException catch (e) {
        if (!e.isUniqueConstraintError()) {
          rethrow;
        }
        await _conflict(s, row, 'catalog.duplicate');
        conflicts++;
      }
    }
    return CatalogProjectionResult(
      applied: applied,
      unchanged: unchanged,
      conflicts: conflicts,
      complete: rows.length <= budget,
    );
  }

  Future<bool> _applyOne(
    AuthorizationSubject s,
    Map<String, Object?> staged,
  ) => database.transaction((tx) async {
    final entity = staged['entity'] as String,
        id = staged['target_id'] as String;
    final rows = await tx.query(
      CatalogSyncJournal.inbox,
      where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
      whereArgs: [s.farmId, s.userId, entity, id],
    );
    if (rows.isEmpty) {
      throw const CatalogFailure('catalog.changed');
    }
    final row = rows.single;
    if (row['cloud_version'] != staged['cloud_version'] ||
        row['operation_id'] != staged['operation_id']) {
      throw const CatalogFailure('catalog.changed');
    }
    final remote = CatalogRemoteRecord(
      farmId: s.farmId,
      entity: entity,
      targetId: id,
      version: row['cloud_version'] as int,
      operationId: row['operation_id'] as String,
      payload: _decode(row['payload_json']),
    );
    final p = remote.payload;
    void authorize() => _authorize(s, entity, owner: p['actor_uid'] as String?);
    authorize();
    final localTable = entity == 'entry'
        ? SqliteCompanyCatalog.entriesTable
        : SqliteCompanyCatalog.requestsTable;
    final locals = await tx.query(localTable, where: 'id=?', whereArgs: [id]);
    final local = locals.isEmpty ? null : locals.single;
    if (local != null && local['farm_id'] != s.farmId) {
      throw const CatalogFailure('catalog.identityConflict');
    }
    final dirty = await tx.query(
      CatalogSyncJournal.outbox,
      columns: ['operation_id'],
      where: "farm_id=? AND entity=? AND target_id=? AND state<>'acked'",
      whereArgs: [s.farmId, entity, id],
      limit: 1,
    );
    if (dirty.isNotEmpty) {
      throw const CatalogFailure('catalog.offlineEditConflict');
    }
    final shadows = await tx.query(
      CatalogSyncJournal.shadow,
      where: 'farm_id=? AND entity=? AND target_id=?',
      whereArgs: [s.farmId, entity, id],
    );
    final shadow = shadows.isEmpty ? null : shadows.single;
    if (shadow != null) {
      final v = shadow['cloud_version'] as int;
      if (v > remote.version) {
        return false;
      }
      if (v == remote.version &&
          (shadow['operation_id'] != remote.operationId ||
              jsonEncode(
                    CatalogSyncInbox.canonical(_decode(shadow['payload_json'])),
                  ) !=
                  jsonEncode(CatalogSyncInbox.canonical(p)))) {
        throw const CatalogFailure('catalog.changed');
      }
      if (local == null ||
          !_same(local, _decode(shadow['payload_json']), entity)) {
        throw const CatalogFailure('catalog.localBaselineConflict');
      }
      if (v == remote.version) {
        await _clear(tx, s, entity, id);
        authorize();
        return false;
      }
    } else if (local != null) {
      throw const CatalogFailure('catalog.unpublishedLocalConflict');
    }
    if (entity == 'entry') {
      await _entry(tx, p, local);
    } else {
      await _request(tx, p, local);
    }
    final projected = (await tx.query(
      localTable,
      where: 'id=? AND farm_id=?',
      whereArgs: [id, s.farmId],
    )).single;
    await tx.insert(SqliteCompanyCatalog.auditTable, {
      'farm_id': s.farmId,
      'actor_uid': s.userId,
      'occurred_at': (clock ?? DateTime.now)().toUtc().toIso8601String(),
      'reason': 'Received server operation ${remote.operationId}',
      'target_id': id,
      'action': 'remoteApply',
      'before_json': local == null ? null : jsonEncode(local),
      'after_json': jsonEncode(projected),
    });
    await tx.insert(CatalogSyncJournal.shadow, {
      'farm_id': s.farmId,
      'entity': entity,
      'target_id': id,
      'cloud_version': remote.version,
      'operation_id': remote.operationId,
      'payload_json': remote.payloadJson,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _clear(tx, s, entity, id);
    authorize();
    return true;
  });
  Future<void> _entry(
    DatabaseExecutor tx,
    Map<String, Object?> p,
    Map<String, Object?>? old,
  ) async {
    if (old != null &&
        (old['code'] != p['code'] ||
            old['kind'] != p['kind'] ||
            (p['kind'] == 'material' && old['unit_id'] != p['unit_id']))) {
      throw const CatalogFailure('catalog.identityConflict');
    }
    if (old == null && {'machine', 'worker', 'material'}.contains(p['kind'])) {
      final legacyTable = p['kind'] == 'material'
          ? 'inventory_items_v2'
          : 'parcel_work_resources';
      if ((await tx.query(
        legacyTable,
        columns: ['id'],
        where: 'id=?',
        whereArgs: [p['id']],
        limit: 1,
      )).isNotEmpty) {
        throw const CatalogFailure('catalog.unpublishedLocalConflict');
      }
    }
    if (p['unit_id'] != null) {
      final units = await tx.query(
        SqliteCompanyCatalog.entriesTable,
        where: 'id=? AND farm_id=? AND kind=?',
        whereArgs: [p['unit_id'], p['farm_id'], 'unit'],
      );
      if (units.isEmpty || (p['active'] == 1 && units.single['active'] != 1)) {
        throw const CatalogFailure('catalog.unitRequired');
      }
    }
    if (p['kind'] == 'unit' &&
        (p['active'] == 0 || (old != null && p['name'] != old['name']))) {
      final refs = await tx.query(
        SqliteCompanyCatalog.entriesTable,
        columns: ['id'],
        where: p['active'] == 0 ? 'unit_id=? AND active=1' : 'unit_id=?',
        whereArgs: [p['id']],
        limit: 1,
      );
      if (refs.isNotEmpty) {
        throw const CatalogFailure('catalog.unitInUse');
      }
    }
    final next = {
      ...p,
      'revision': old == null ? 1 : (old['revision'] as int) + 1,
    };
    if (old == null) {
      await tx.insert(SqliteCompanyCatalog.entriesTable, next);
    } else {
      await tx.update(
        SqliteCompanyCatalog.entriesTable,
        next,
        where: 'id=? AND farm_id=?',
        whereArgs: [p['id'], p['farm_id']],
      );
    }
    await SqliteCompanyCatalog.projectEntry(
      tx,
      CatalogEntry(
        id: p['id'] as String,
        farmId: p['farm_id'] as String,
        kind: CatalogKind.values.byName(p['kind'] as String),
        code: p['code'] as String,
        name: p['name'] as String,
        unitId: p['unit_id'] as String?,
        active: p['active'] == 1,
        revision: next['revision'] as int,
      ),
    );
  }

  Future<void> _request(
    DatabaseExecutor tx,
    Map<String, Object?> p,
    Map<String, Object?>? old,
  ) async {
    if (old != null &&
        [
          'actor_uid',
          'kind',
          'code',
          'name',
          'reason',
          'created_at',
        ].any((k) => old[k] != p[k])) {
      throw const CatalogFailure('catalog.identityConflict');
    }
    if (old != null &&
        old['status'] != 'pending' &&
        old['status'] != p['status']) {
      throw const CatalogFailure('catalog.identityConflict');
    }
    if (p['status'] == 'approved') {
      final entries = await tx.query(
        SqliteCompanyCatalog.entriesTable,
        where: 'id=? AND farm_id=? AND kind=?',
        whereArgs: [p['entry_id'], p['farm_id'], p['kind']],
      );
      if (entries.isEmpty) {
        throw const CatalogFailure('catalog.unitRequired');
      }
    }
    final next = {
      ...p,
      for (final k in ['entry_id', 'resolved_by', 'resolved_at', 'resolution'])
        k: p[k],
    };
    if (old == null) {
      await tx.insert(SqliteCompanyCatalog.requestsTable, next);
    } else {
      await tx.update(
        SqliteCompanyCatalog.requestsTable,
        next,
        where: 'id=? AND farm_id=?',
        whereArgs: [p['id'], p['farm_id']],
      );
    }
  }

  Future<void> _clear(
    DatabaseExecutor tx,
    AuthorizationSubject s,
    String entity,
    String id,
  ) => tx
      .delete(
        CatalogSyncJournal.conflicts,
        where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
        whereArgs: [s.farmId, s.userId, entity, id],
      )
      .then((_) {});
  Future<void> _conflict(
    AuthorizationSubject s,
    Map<String, Object?> row,
    String code,
  ) => database.transaction((tx) async {
    final entity = row['entity'] as String, p = _decode(row['payload_json']);
    _authorize(s, entity, owner: p['actor_uid'] as String?);
    final current = await tx.query(
      CatalogSyncJournal.inbox,
      where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
      whereArgs: [s.farmId, s.userId, entity, row['target_id']],
    );
    if (current.isEmpty ||
        current.single['cloud_version'] != row['cloud_version'] ||
        current.single['operation_id'] != row['operation_id'] ||
        current.single['payload_json'] != row['payload_json']) {
      return;
    }
    final local = await tx.query(
      entity == 'entry'
          ? SqliteCompanyCatalog.entriesTable
          : SqliteCompanyCatalog.requestsTable,
      where: 'id=?',
      whereArgs: [row['target_id']],
    );
    await tx.insert(CatalogSyncJournal.conflicts, {
      'farm_id': s.farmId,
      'reader_uid': s.userId,
      'entity': entity,
      'target_id': row['target_id'],
      'cloud_version': row['cloud_version'],
      'operation_id': row['operation_id'],
      'remote_json': row['payload_json'],
      'local_json': local.isEmpty || local.single['farm_id'] != s.farmId
          ? null
          : jsonEncode(local.single),
      'failure': code,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _authorize(s, entity, owner: p['actor_uid'] as String?);
  });
  Future<List<Map<String, Object?>>> conflicts() async {
    final s = currentSubject();
    if (s == null) {
      throw const CatalogFailure('catalog.denied');
    }
    _authorize(s, 'entry');
    final rows = await database.query(
      CatalogSyncJournal.conflicts,
      where: 'farm_id=? AND reader_uid=?',
      whereArgs: [s.farmId, s.userId],
    );
    final visible = <Map<String, Object?>>[];
    for (final row in rows) {
      _authorize(
        s,
        row['entity'] as String,
        owner: _decode(row['remote_json'])['actor_uid'] as String?,
      );
      visible.add(row);
    }
    return visible;
  }
}
