import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_projection.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';

enum CatalogConflictChoice { acceptRemote, keepLocal }

/// Immutable review snapshot. An old review cannot authorize a newer conflict.
class CatalogConflictReview {
  CatalogConflictReview.fromRow(Map<String, Object?> row)
    : farmId = row['farm_id'] as String,
      readerUid = row['reader_uid'] as String,
      entity = row['entity'] as String,
      targetId = row['target_id'] as String,
      version = row['cloud_version'] as int,
      operationId = row['operation_id'] as String,
      remoteJson = row['remote_json'] as String,
      localJson = row['local_json'] as String?;
  final String farmId, readerUid, entity, targetId, operationId, remoteJson;
  final String? localJson;
  final int version;
}

abstract interface class CatalogConflictVerifier {
  Future<String?> currentUserId();

  /// Read this exact target from the server, never from the local cache.
  Future<CatalogRemoteRecord> verify({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  });
}

/// Safe decisions for conflicts with no unresolved outgoing operation. Pending,
/// blocked and conflicted operations require receipt recovery before a choice.
class CatalogConflictDecisions {
  CatalogConflictDecisions({
    required this.database,
    required this.verifier,
    required this.currentSubject,
    this.clock,
  });
  final Database database;
  final CatalogConflictVerifier verifier;
  final AuthorizationSubject? Function() currentSubject;
  final DateTime Function()? clock;
  bool _disposed = false, _busy = false;
  void dispose() {
    _disposed = true;
  }

  void _authorize(AuthorizationSubject original) {
    final s = currentSubject();
    if (_disposed ||
        s == null ||
        s.userId != original.userId ||
        s.farmId != original.farmId) {
      throw const CatalogFailure('catalog.denied');
    }
    final auth = AuthorizationService(clock: clock),
        resource = ResourceContext(farmId: s.farmId);
    if (!auth.can(
          subject: s,
          permission: PermissionCodes.catalogManage,
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

  static bool _equal(String? a, String? b) => a == null || b == null
      ? a == b
      : jsonEncode(CatalogSyncInbox.canonical(jsonDecode(a))) ==
            jsonEncode(CatalogSyncInbox.canonical(jsonDecode(b)));
  Future<void> decide(
    CatalogConflictReview review, {
    required CatalogConflictChoice choice,
    required String reason,
  }) async {
    if (_busy) {
      throw const CatalogFailure('catalog.changed');
    }
    final text = reason.trim();
    if (text.isEmpty || text.length > 500) {
      throw const CatalogFailure('catalog.reasonRequired');
    }
    final s = currentSubject();
    if (s == null ||
        review.farmId != s.farmId ||
        review.readerUid != s.userId) {
      throw const CatalogFailure('catalog.denied');
    }
    _authorize(s);
    if (choice == CatalogConflictChoice.keepLocal && review.entity != 'entry') {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    _busy = true;
    try {
      if (await verifier.currentUserId() != s.userId) {
        throw const CatalogSyncUnavailable();
      }
      final remote = await verifier.verify(
        farmId: s.farmId,
        actorUid: s.userId,
        entity: review.entity,
        targetId: review.targetId,
      );
      _authorize(s);
      if (await verifier.currentUserId() != s.userId) {
        throw const CatalogSyncUnavailable();
      }
      remote.validate();
      if (remote.farmId != review.farmId ||
          remote.entity != review.entity ||
          remote.targetId != review.targetId ||
          remote.version != review.version ||
          remote.operationId != review.operationId ||
          !_equal(remote.payloadJson, review.remoteJson)) {
        throw const CatalogFailure('catalog.changed');
      }
      await database.transaction((tx) async {
        _authorize(s);
        final args = [s.farmId, s.userId, review.entity, review.targetId];
        final conflicts = await tx.query(
          CatalogSyncJournal.conflicts,
          where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
          whereArgs: args,
        );
        final inbox = await tx.query(
          CatalogSyncJournal.inbox,
          where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
          whereArgs: args,
        );
        if (conflicts.length != 1 || inbox.length != 1) {
          throw const CatalogFailure('catalog.changed');
        }
        final c = conflicts.single, i = inbox.single;
        if (c['cloud_version'] != review.version ||
            c['operation_id'] != review.operationId ||
            !_equal(c['remote_json'] as String, review.remoteJson) ||
            !_equal(c['local_json'] as String?, review.localJson) ||
            i['cloud_version'] != review.version ||
            i['operation_id'] != review.operationId ||
            !_equal(i['payload_json'] as String, review.remoteJson)) {
          throw const CatalogFailure('catalog.changed');
        }
        final table = review.entity == 'entry'
            ? SqliteCompanyCatalog.entriesTable
            : SqliteCompanyCatalog.requestsTable;
        final rows = await tx.query(
          table,
          where: 'id=?',
          whereArgs: [review.targetId],
        );
        final local = rows.isEmpty ? null : rows.single;
        if (local != null && local['farm_id'] != s.farmId) {
          throw const CatalogFailure('catalog.identityConflict');
        }
        if (!_equal(
          local == null ? null : jsonEncode(local),
          review.localJson,
        )) {
          throw const CatalogFailure('catalog.changed');
        }
        final dirty = await tx.query(
          CatalogSyncJournal.outbox,
          columns: ['operation_id'],
          where: "farm_id=? AND entity=? AND target_id=? AND state<>'acked'",
          whereArgs: [s.farmId, review.entity, review.targetId],
          limit: 1,
        );
        if (dirty.isNotEmpty) {
          throw const CatalogFailure('catalog.pendingReconcileRequired');
        }
        final shadows = await tx.query(
          CatalogSyncJournal.shadow,
          where: 'farm_id=? AND entity=? AND target_id=?',
          whereArgs: [s.farmId, review.entity, review.targetId],
        );
        if (shadows.isNotEmpty) {
          final shadow = shadows.single;
          if ((shadow['cloud_version'] as int) > review.version ||
              (shadow['cloud_version'] == review.version &&
                  (shadow['operation_id'] != review.operationId ||
                      !_equal(
                        shadow['payload_json'] as String,
                        remote.payloadJson,
                      )))) {
            throw const CatalogFailure('catalog.changed');
          }
        }
        final p = remote.payload;
        if (local != null &&
            review.entity == 'entry' &&
            (local['kind'] != p['kind'] ||
                local['code'] != p['code'] ||
                (p['kind'] == 'material' &&
                    local['unit_id'] != p['unit_id']))) {
          throw const CatalogFailure('catalog.identityConflict');
        }
        if (choice == CatalogConflictChoice.keepLocal && local == null) {
          throw const CatalogFailure('catalog.changed');
        }
        final selected = choice == CatalogConflictChoice.acceptRemote
            ? p
            : local!;
        if (review.entity == 'entry') {
          CatalogRemoteRecord(
            farmId: s.farmId,
            entity: 'entry',
            targetId: review.targetId,
            version: review.version,
            operationId: review.operationId,
            payload: selected,
          );
        }
        await CatalogSyncProjection.writeBusiness(
          tx,
          selected,
          local,
          review.entity,
        );
        final after = (await tx.query(
          table,
          where: 'id=? AND farm_id=?',
          whereArgs: [review.targetId, s.farmId],
        )).single;
        await tx.insert(CatalogSyncJournal.shadow, {
          'farm_id': s.farmId,
          'entity': review.entity,
          'target_id': review.targetId,
          'cloud_version': review.version,
          'operation_id': review.operationId,
          'payload_json': remote.payloadJson,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (choice == CatalogConflictChoice.keepLocal) {
          await CatalogSyncJournal.append(
            tx,
            farmId: s.farmId,
            actorUid: s.userId,
            entity: review.entity,
            targetId: review.targetId,
            payload: after,
            reason: text,
            occurredAt: (clock ?? DateTime.now)(),
          );
        }
        await tx.insert(SqliteCompanyCatalog.auditTable, {
          'farm_id': s.farmId,
          'actor_uid': s.userId,
          'occurred_at': (clock ?? DateTime.now)().toUtc().toIso8601String(),
          'reason': text,
          'target_id': review.targetId,
          'action': 'conflict.${choice.name}',
          'before_json': local == null ? null : jsonEncode(local),
          'after_json': jsonEncode(after),
        });
        // Durable business audit retains the reviewed remote and local snapshots.
        await tx.insert(SqliteCompanyCatalog.auditTable, {
          'farm_id': s.farmId,
          'actor_uid': s.userId,
          'occurred_at': (clock ?? DateTime.now)().toUtc().toIso8601String(),
          'reason': text,
          'target_id': review.targetId,
          'action': 'conflict.review',
          'before_json': review.localJson,
          'after_json': jsonEncode({
            'entity': review.entity,
            'cloudVersion': review.version,
            'operationId': review.operationId,
            'remote': p,
            'choice': choice.name,
          }),
        });
        await tx.delete(
          CatalogSyncJournal.conflicts,
          where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
          whereArgs: args,
        );
        _authorize(s);
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const CatalogFailure('catalog.duplicate');
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
