import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_receiver.dart';

/// A server-only exact-target read. Absence is advisory; sender CAS is final.
abstract interface class CatalogPublicationVerifier {
  String? get authenticatedUid;
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String targetId,
  });
}

/// The selected business snapshot must still match when preparation commits.
class CatalogPublicationReview {
  CatalogPublicationReview.fromRow(Map<String, Object?> row)
    : payloadJson = jsonEncode(row) {
    CatalogRemoteRecord(
      farmId: farmId,
      entity: 'entry',
      targetId: targetId,
      version: 1,
      operationId: 'review',
      payload: payload,
    );
  }
  final String payloadJson;
  Map<String, Object?> get payload =>
      (jsonDecode(payloadJson) as Map).cast<String, Object?>();
  String get farmId => payload['farm_id'] as String;
  String get targetId => payload['id'] as String;
}

/// Enqueues one reviewed existing master, never publishes directly to Firebase.
/// Units must be prepared first. Suggestions are outside this checkpoint.
class CatalogInitialPublication {
  CatalogInitialPublication({
    required this.database,
    required this.verifier,
    required this.subject,
    this.clock,
  });
  final Database database;
  final CatalogPublicationVerifier verifier;
  final AuthorizationSubject Function() subject;
  final DateTime Function()? clock;
  bool _busy = false, _disposed = false;
  void dispose() {
    _disposed = true;
  }

  void _guard(AuthorizationSubject initial) {
    final current = subject();
    final auth = AuthorizationService(clock: clock);
    final resource = ResourceContext(farmId: initial.farmId);
    if (_disposed ||
        current.userId != initial.userId ||
        current.membershipId != initial.membershipId ||
        current.farmId != initial.farmId ||
        verifier.authenticatedUid != initial.userId ||
        !auth.can(
          subject: current,
          permission: PermissionCodes.catalogManage,
          resource: resource,
        ) ||
        !auth.can(
          subject: current,
          permission: PermissionCodes.cloudSync,
          resource: resource,
        )) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) {
      return v.map(_canonical).toList();
    }
    return v;
  }

  static bool _same(Object? a, Object? b) =>
      jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

  Future<CatalogPublicationReview> review(String targetId) async {
    final initial = subject();
    _guard(initial);
    final rows = await database.query(
      SqliteCompanyCatalog.entriesTable,
      where: 'id=? AND farm_id=?',
      whereArgs: [targetId, initial.farmId],
    );
    _guard(initial);
    if (rows.length != 1) {
      throw const CatalogFailure('catalog.changed');
    }
    return CatalogPublicationReview.fromRow(rows.single);
  }

  Future<void> prepare(
    CatalogPublicationReview review, {
    required String reason,
  }) async {
    if (_busy) {
      throw const CatalogFailure('catalog.changed');
    }
    final initial = subject();
    _guard(initial);
    if (review.farmId != initial.farmId) {
      throw const CatalogFailure('catalog.denied');
    }
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw const CatalogFailure('catalog.invalid');
    }
    _busy = true;
    try {
      final local = review.payload;
      final unitId = local['unit_id'] as String?;
      Map<String, Object?>? unit;
      if (unitId != null) {
        final rows = await database.query(
          SqliteCompanyCatalog.entriesTable,
          where: 'id=? AND farm_id=? AND kind=? AND active=1',
          whereArgs: [unitId, initial.farmId, 'unit'],
        );
        if (rows.length != 1) {
          throw const CatalogFailure('catalog.unitRequired');
        }
        unit = rows.single;
      }
      final existing = await verifier.read(
        farmId: initial.farmId,
        actorUid: initial.userId,
        targetId: review.targetId,
      );
      _guard(initial);
      if (existing != null) {
        throw const CatalogFailure('catalog.changed');
      }
      final remoteUnit = unitId == null
          ? null
          : await verifier.read(
              farmId: initial.farmId,
              actorUid: initial.userId,
              targetId: unitId,
            );
      _guard(initial);
      if (remoteUnit != null &&
          (remoteUnit.farmId != initial.farmId ||
              remoteUnit.entity != 'entry' ||
              remoteUnit.targetId != unitId ||
              remoteUnit.payload['kind'] != 'unit' ||
              remoteUnit.payload['active'] != 1)) {
        throw const CatalogFailure('catalog.unitRequired');
      }
      await database.transaction((tx) async {
        _guard(initial);
        final restored = await tx.query(
          CatalogSyncJournal.device,
          where: 'farm_id=? AND restore_blocked=1',
          whereArgs: [initial.farmId],
        );
        if (restored.isNotEmpty) {
          throw const CatalogFailure('catalog.restoreReconcileRequired');
        }
        final rows = await tx.query(
          SqliteCompanyCatalog.entriesTable,
          where: 'id=? AND farm_id=?',
          whereArgs: [review.targetId, initial.farmId],
        );
        if (rows.length != 1 || !_same(rows.single, local)) {
          throw const CatalogFailure('catalog.changed');
        }
        for (final table in [
          CatalogSyncJournal.outbox,
          CatalogSyncJournal.shadow,
          CatalogSyncJournal.inbox,
          CatalogSyncJournal.conflicts,
        ]) {
          final known = await tx.query(
            table,
            where: 'farm_id=? AND entity=? AND target_id=?',
            whereArgs: [initial.farmId, 'entry', review.targetId],
            limit: 1,
          );
          if (known.isNotEmpty) {
            throw const CatalogFailure('catalog.pendingReconcileRequired');
          }
        }
        if (unitId != null) {
          final units = await tx.query(
            SqliteCompanyCatalog.entriesTable,
            where: 'id=? AND farm_id=?',
            whereArgs: [unitId, initial.farmId],
          );
          if (units.length != 1 || !_same(units.single, unit)) {
            throw const CatalogFailure('catalog.changed');
          }
          final queue = await tx.query(
            CatalogSyncJournal.outbox,
            where: 'farm_id=? AND entity=? AND target_id=? AND state<>?',
            whereArgs: [initial.farmId, 'entry', unitId, 'acked'],
            orderBy: 'sequence',
          );
          final shadow = await tx.query(
            CatalogSyncJournal.shadow,
            where: 'farm_id=? AND entity=? AND target_id=?',
            whereArgs: [initial.farmId, 'entry', unitId],
          );
          if (remoteUnit == null) {
            if (shadow.isNotEmpty ||
                queue.length != 1 ||
                queue.single['state'] != 'pending' ||
                queue.single['actor_uid'] != initial.userId ||
                queue.single['base_version'] != 0 ||
                queue.single['new_version'] != 1 ||
                !_same(
                  jsonDecode(queue.single['payload_json'] as String),
                  unit,
                )) {
              throw const CatalogFailure('catalog.unitRequired');
            }
          } else {
            if (queue.isNotEmpty ||
                shadow.length != 1 ||
                shadow.single['cloud_version'] != remoteUnit.version ||
                shadow.single['operation_id'] != remoteUnit.operationId ||
                !_same(
                  jsonDecode(shadow.single['payload_json'] as String),
                  remoteUnit.payload,
                )) {
              throw const CatalogFailure('catalog.pendingReconcileRequired');
            }
            final business = Map<String, Object?>.from(unit!)
              ..remove('revision');
            final remoteBusiness = remoteUnit.payload..remove('revision');
            if (!_same(business, remoteBusiness)) {
              throw const CatalogFailure('catalog.changed');
            }
          }
        }
        final time = (clock ?? DateTime.now)();
        await CatalogSyncJournal.append(
          tx,
          farmId: initial.farmId,
          actorUid: initial.userId,
          entity: 'entry',
          targetId: review.targetId,
          payload: local,
          reason: reason.trim(),
          occurredAt: time,
        );
        await tx.insert(SqliteCompanyCatalog.auditTable, {
          'farm_id': initial.farmId,
          'actor_uid': initial.userId,
          'occurred_at': time.toUtc().toIso8601String(),
          'reason': reason.trim(),
          'target_id': review.targetId,
          'action': 'sync.prepareInitial',
          'before_json': review.payloadJson,
          'after_json': review.payloadJson,
        });
        _guard(initial);
      });
    } finally {
      _busy = false;
    }
  }
}
