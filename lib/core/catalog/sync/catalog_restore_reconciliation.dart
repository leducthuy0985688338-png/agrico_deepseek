import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_receiver.dart';

abstract interface class CatalogRestoreTransport
    implements CatalogReceiveTransport {
  String? get authenticatedUid;
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  });
}

/// A complete, actor-bound review. Lists and fingerprints cannot be mutated.
class CatalogRestoreReview {
  CatalogRestoreReview._({
    required this.farmId,
    required this.actorUid,
    required this.membershipId,
    required this.stateJson,
    required this.remoteJson,
    required List<String> localOnly,
    required List<String> divergent,
    required List<String> remoteOnly,
    required this.matched,
  }) : localOnly = List.unmodifiable(localOnly),
       divergent = List.unmodifiable(divergent),
       remoteOnly = List.unmodifiable(remoteOnly);
  final String farmId, actorUid, membershipId, stateJson, remoteJson;
  final List<String> localOnly, divergent, remoteOnly;
  final int matched;
}

/// A conservative restore gate. No cloud writes or restored-command replay.
class CatalogRestoreReconciliation {
  CatalogRestoreReconciliation({
    required this.database,
    required this.transport,
    required this.subject,
    this.clock,
    this.pageSize = 100,
    this.maxPages = 20,
    this.maxRecords = 5000,
  }) {
    if (pageSize < 1 ||
        pageSize > 200 ||
        maxPages < 2 ||
        maxPages > 1000 ||
        maxRecords < 1 ||
        maxRecords > 5000) {
      throw ArgumentError('Invalid restore review budget');
    }
  }
  final Database database;
  final CatalogRestoreTransport transport;
  final AuthorizationSubject Function() subject;
  final DateTime Function()? clock;
  final int pageSize, maxPages, maxRecords;
  bool _busy = false, _disposed = false;
  void dispose() {
    _disposed = true;
  }

  void _guard(AuthorizationSubject original) {
    final s = subject();
    final auth = AuthorizationService(clock: clock),
        resource = ResourceContext(farmId: original.farmId);
    if (_disposed ||
        s.userId != original.userId ||
        s.membershipId != original.membershipId ||
        s.farmId != original.farmId ||
        transport.authenticatedUid != original.userId ||
        !auth.can(
          subject: s,
          permission: PermissionCodes.catalogManage,
          resource: resource,
        ) ||
        !auth.can(
          subject: s,
          permission: PermissionCodes.catalogView,
          resource: resource,
        ) ||
        !auth.can(
          subject: s,
          permission: PermissionCodes.cloudSync,
          resource: resource,
        )) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  static String _json(Object? value) =>
      jsonEncode(CatalogSyncInbox.canonical(value));
  static String _key(String entity, String id) => '$entity/$id';
  static Map<String, Object?> _business(Map<String, Object?> p, String entity) {
    final result = Map<String, Object?>.from(p);
    if (entity == 'entry') {
      result.remove('revision');
    } else {
      for (final key in [
        'entry_id',
        'resolved_by',
        'resolved_at',
        'resolution',
      ]) {
        result.putIfAbsent(key, () => null);
      }
    }
    return result;
  }

  Future<void> _blocked(DatabaseExecutor tx, String farm) async {
    if ((await tx.query(
          CatalogSyncJournal.device,
          where: 'farm_id=? AND restore_blocked=1',
          whereArgs: [farm],
        )).length !=
        1) {
      throw const CatalogFailure('catalog.changed');
    }
  }

  Future<Map<String, Object?>> _state(DatabaseExecutor tx, String farm) async {
    final result = <String, Object?>{};
    for (final table in [
      SqliteCompanyCatalog.entriesTable,
      SqliteCompanyCatalog.requestsTable,
      CatalogSyncJournal.device,
      CatalogSyncJournal.outbox,
      CatalogSyncJournal.shadow,
      CatalogSyncJournal.inbox,
      CatalogSyncJournal.conflicts,
    ]) {
      final rows = await tx.query(table, where: 'farm_id=?', whereArgs: [farm]);
      final sorted = rows.map((r) => Map<String, Object?>.from(r)).toList()
        ..sort((a, b) => _json(a).compareTo(_json(b)));
      result[table] = sorted;
    }
    return result;
  }

  Map<String, Map<String, Object?>> _locals(
    Map<String, Object?> state,
    String farm,
  ) {
    final result = <String, Map<String, Object?>>{};
    for (final entity in ['entry', 'request']) {
      final table = entity == 'entry'
          ? SqliteCompanyCatalog.entriesTable
          : SqliteCompanyCatalog.requestsTable;
      for (final value in state[table] as List) {
        final row = (value as Map).cast<String, Object?>();
        final id = row['id'] as String;
        CatalogRemoteRecord(
          farmId: farm,
          entity: entity,
          targetId: id,
          version: 1,
          operationId: 'restore-review',
          payload: row,
        );
        result[_key(entity, id)] = row;
      }
    }
    return result;
  }

  Future<Map<String, CatalogRemoteRecord>> _scan(AuthorizationSubject s) async {
    final records = <String, CatalogRemoteRecord>{};
    var pages = 0;
    for (final entity in ['entry', 'request']) {
      String? cursor;
      while (true) {
        if (pages++ >= maxPages) {
          throw const CatalogFailure('catalog.restoreReconcileRequired');
        }
        _guard(s);
        if (await transport.currentUserId() != s.userId) {
          throw const CatalogFailure('catalog.denied');
        }
        final page = await transport.fetch(
          farmId: s.farmId,
          actorUid: s.userId,
          entity: entity,
          allRequests: true,
          limit: pageSize,
          cursor: cursor,
        );
        _guard(s);
        if (page.records.length > pageSize ||
            (page.nextCursor != null &&
                (page.records.isEmpty ||
                    page.nextCursor != page.records.last.targetId ||
                    page.records.length != pageSize))) {
          throw const CatalogFailure('catalog.syncInvalid');
        }
        var last = cursor;
        for (final r in page.records) {
          r.validate();
          if (r.farmId != s.farmId ||
              r.entity != entity ||
              (last != null &&
                  CatalogRemoteRecord.compareIds(r.targetId, last) <= 0)) {
            throw const CatalogFailure('catalog.syncInvalid');
          }
          last = r.targetId;
          records[_key(entity, r.targetId)] = r;
          if (records.length > maxRecords) {
            throw const CatalogFailure('catalog.restoreReconcileRequired');
          }
        }
        if (page.nextCursor == null) {
          // A full page requires another read, including a terminal empty page.
          if (page.records.length == pageSize) {
            throw const CatalogFailure('catalog.syncInvalid');
          }
          break;
        }
        cursor = page.nextCursor;
      }
    }
    return records;
  }

  static Map<String, Object?> _manifest(
    Map<String, CatalogRemoteRecord> records,
  ) => {
    for (final e in records.entries)
      e.key: {
        'version': e.value.version,
        'operationId': e.value.operationId,
        'payload': e.value.payload,
      },
  };

  Future<CatalogRestoreReview> review() async {
    if (_busy) {
      throw const CatalogFailure('catalog.changed');
    }
    final s = subject();
    _guard(s);
    _busy = true;
    try {
      await _blocked(database, s.farmId);
      final remote = await _scan(s);
      // Only a complete validated scan is staged. No business rows are changed.
      final list = remote.values.toList();
      for (var offset = 0; offset < list.length; offset += 200) {
        await CatalogSyncInbox(database).stage(
          list.skip(offset).take(200).toList(),
          farmId: s.farmId,
          readerUid: s.userId,
          allRequests: true,
          authorize: () => _guard(s),
        );
      }
      return await database.transaction((tx) async {
        _guard(s);
        await _blocked(tx, s.farmId);
        final state = await _state(tx, s.farmId);
        final local = _locals(state, s.farmId);
        final localOnly = <String>[],
            divergent = <String>[],
            remoteOnly = <String>[];
        var matched = 0;
        for (final e in local.entries) {
          final r = remote[e.key];
          if (r == null) {
            localOnly.add(e.key);
          } else if (_json(_business(e.value, r.entity)) !=
              _json(_business(r.payload, r.entity))) {
            divergent.add(e.key);
          } else {
            matched++;
          }
        }
        for (final key in remote.keys) {
          if (!local.containsKey(key)) {
            remoteOnly.add(key);
          }
        }
        localOnly.sort();
        divergent.sort();
        remoteOnly.sort();
        _guard(s);
        return CatalogRestoreReview._(
          farmId: s.farmId,
          actorUid: s.userId,
          membershipId: s.membershipId,
          stateJson: _json(state),
          remoteJson: _json(_manifest(remote)),
          localOnly: localOnly,
          divergent: divergent,
          remoteOnly: remoteOnly,
          matched: matched,
        );
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> unlock(
    CatalogRestoreReview review, {
    required String reason,
    required Set<String> keepLocalOnly,
  }) async {
    if (_busy) {
      throw const CatalogFailure('catalog.changed');
    }
    final s = subject();
    _guard(s);
    if (review.farmId != s.farmId ||
        review.actorUid != s.userId ||
        review.membershipId != s.membershipId) {
      throw const CatalogFailure('catalog.denied');
    }
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw const CatalogFailure('catalog.invalid');
    }
    if (review.divergent.isNotEmpty ||
        review.remoteOnly.isNotEmpty ||
        keepLocalOnly.length != review.localOnly.length ||
        !keepLocalOnly.containsAll(review.localOnly)) {
      throw const CatalogFailure('catalog.restoreReconcileRequired');
    }
    _busy = true;
    try {
      final remote = await _scan(s);
      if (_json(_manifest(remote)) != review.remoteJson) {
        throw const CatalogFailure('catalog.changed');
      }
      final state = (jsonDecode(review.stateJson) as Map)
          .cast<String, Object?>();
      final local = _locals(state, s.farmId);
      // Close pagination gaps for every local target with an exact server read.
      for (final e in local.entries) {
        final entity = e.key.startsWith('entry/') ? 'entry' : 'request';
        _guard(s);
        final fresh = await transport.read(
          farmId: s.farmId,
          actorUid: s.userId,
          entity: entity,
          targetId: e.value['id'] as String,
        );
        _guard(s);
        final expected = remote[e.key];
        if ((fresh == null) != (expected == null) ||
            (fresh != null &&
                (fresh.farmId != s.farmId ||
                    fresh.entity != entity ||
                    fresh.targetId != e.value['id'] ||
                    _json(_manifest({e.key: fresh})) !=
                        _json(_manifest({e.key: expected!}))))) {
          throw const CatalogFailure('catalog.changed');
        }
      }
      await database.transaction((tx) async {
        _guard(s);
        await _blocked(tx, s.farmId);
        if (_json(await _state(tx, s.farmId)) != review.stateJson) {
          throw const CatalogFailure('catalog.changed');
        }
        final queue = state[CatalogSyncJournal.outbox] as List;
        if (queue.any((r) => (r as Map)['state'] != 'acked') ||
            (state[CatalogSyncJournal.conflicts] as List).isNotEmpty) {
          throw const CatalogFailure('catalog.pendingReconcileRequired');
        }
        for (final value in state[CatalogSyncJournal.inbox] as List) {
          final row = (value as Map).cast<String, Object?>();
          final r =
              remote[_key(row['entity'] as String, row['target_id'] as String)];
          if (r == null ||
              row['cloud_version'] != r.version ||
              row['operation_id'] != r.operationId ||
              _json(jsonDecode(row['payload_json'] as String)) !=
                  _json(r.payload)) {
            throw const CatalogFailure('catalog.changed');
          }
        }
        for (final value in state[CatalogSyncJournal.shadow] as List) {
          final row = (value as Map).cast<String, Object?>();
          final r =
              remote[_key(row['entity'] as String, row['target_id'] as String)];
          if (r == null ||
              (row['cloud_version'] as int) > r.version ||
              (row['cloud_version'] == r.version &&
                  (row['operation_id'] != r.operationId ||
                      _json(jsonDecode(row['payload_json'] as String)) !=
                          _json(r.payload)))) {
            throw const CatalogFailure('catalog.changed');
          }
        }
        for (final r in remote.values) {
          await tx.insert(CatalogSyncJournal.shadow, {
            'farm_id': s.farmId,
            'entity': r.entity,
            'target_id': r.targetId,
            'cloud_version': r.version,
            'operation_id': r.operationId,
            'payload_json': r.payloadJson,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await tx.insert(SqliteCompanyCatalog.auditTable, {
          'farm_id': s.farmId,
          'actor_uid': s.userId,
          'occurred_at': (clock ?? DateTime.now)().toUtc().toIso8601String(),
          'reason': reason.trim(),
          'target_id': 'restore-reconciliation',
          'action': 'sync.restoreReviewed',
          'before_json': _json({'restoreBlocked': true}),
          'after_json': _json({
            'restoreBlocked': false,
            'matched': review.matched,
            'keptLocalOnly': review.localOnly,
            'remote': jsonDecode(review.remoteJson),
          }),
        });
        final changed = await tx.update(
          CatalogSyncJournal.device,
          {'restore_blocked': 0},
          where: 'farm_id=? AND restore_blocked=1',
          whereArgs: [s.farmId],
        );
        if (changed != 1) {
          throw const CatalogFailure('catalog.changed');
        }
        _guard(s);
      });
    } finally {
      _busy = false;
    }
  }
}
