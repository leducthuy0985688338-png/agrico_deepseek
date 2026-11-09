import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_conflict_decisions.dart';
import 'catalog_initial_publication.dart';
import 'catalog_receipt_recovery.dart';
import 'catalog_restore_reconciliation.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_projection.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';

class CatalogSyncStatus {
  const CatalogSyncStatus({
    required this.counts,
    required this.restoreBlocked,
    required this.canManage,
    required this.farmUnresolved,
    required this.conflicts,
    required this.unpublished,
    required this.labels,
  });
  final Map<String, int> counts;
  final bool restoreBlocked, canManage;
  final int farmUnresolved;
  final List<CatalogConflictReview> conflicts;
  final List<CatalogPublicationReview> unpublished;
  final Map<String, String> labels;
}

abstract interface class CatalogSyncActions {
  Future<CatalogSyncStatus> load();
  Future<bool> synchronize();
  Future<void> decide(
    CatalogConflictReview review,
    CatalogConflictChoice choice,
    String reason,
  );
  Future<void> prepare(CatalogPublicationReview review, String reason);
  Future<CatalogRestoreReview> reviewRestore();
  Future<void> releaseRestore(
    CatalogRestoreReview review,
    String reason,
    Set<String> keepLocalOnly,
  );
  void dispose();
}

/// Manual, session-owned workspace. No timer, background send or automatic upload.
class CatalogSyncWorkspace implements CatalogSyncActions {
  CatalogSyncWorkspace({
    required this.database,
    required this.currentSubject,
    required this.sendTransport,
    required CatalogReceiveTransport receiveTransport,
    required CatalogReceiptLookup receiptLookup,
    required CatalogConflictVerifier conflictVerifier,
    required CatalogPublicationVerifier publicationVerifier,
    required CatalogRestoreTransport restoreTransport,
    this.clock,
  }) {
    journal = CatalogSyncJournal(database);
    sender = CatalogSyncSender(
      journal: journal,
      transport: sendTransport,
      subject: _subject,
      clock: clock,
    );
    recovery = CatalogReceiptRecovery(
      journal: journal,
      lookup: receiptLookup,
      subject: _subject,
      clock: clock,
    );
    receiver = CatalogSyncReceiver(
      inbox: CatalogSyncInbox(database),
      transport: receiveTransport,
      currentSubject: _current,
      clock: clock,
    );
    projection = CatalogSyncProjection(
      database: database,
      currentSubject: _current,
      clock: clock,
    );
    decisions = CatalogConflictDecisions(
      database: database,
      verifier: conflictVerifier,
      currentSubject: _current,
      clock: clock,
    );
    publication = CatalogInitialPublication(
      database: database,
      verifier: publicationVerifier,
      subject: _subject,
      clock: clock,
    );
    restore = CatalogRestoreReconciliation(
      database: database,
      transport: restoreTransport,
      subject: _subject,
      clock: clock,
    );
  }
  final Database database;
  final AuthorizationSubject? Function() currentSubject;
  final CatalogSyncTransport sendTransport;
  final DateTime Function()? clock;
  late final CatalogSyncJournal journal;
  late final CatalogSyncSender sender;
  late final CatalogReceiptRecovery recovery;
  late final CatalogSyncReceiver receiver;
  late final CatalogSyncProjection projection;
  late final CatalogConflictDecisions decisions;
  late final CatalogInitialPublication publication;
  late final CatalogRestoreReconciliation restore;
  bool _disposed = false, _busy = false;
  AuthorizationSubject? _current() => _disposed ? null : currentSubject();
  AuthorizationSubject _subject() =>
      _current() ?? (throw const CatalogFailure('catalog.denied'));
  bool _can(AuthorizationSubject s, String permission) =>
      AuthorizationService(clock: clock).can(
        subject: s,
        permission: permission,
        resource: ResourceContext(farmId: s.farmId),
      );
  void _guard(AuthorizationSubject initial, {bool manage = false}) {
    final s = _subject();
    if (s.userId != initial.userId ||
        s.membershipId != initial.membershipId ||
        s.farmId != initial.farmId ||
        !_can(s, PermissionCodes.cloudSync) ||
        !_can(s, PermissionCodes.catalogView) ||
        (manage && !_can(s, PermissionCodes.catalogManage))) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  Future<T> _run<T>(
    Future<T> Function(AuthorizationSubject) work, {
    bool manage = false,
  }) async {
    if (_busy) {
      throw const CatalogFailure('catalog.changed');
    }
    final s = _subject();
    _guard(s, manage: manage);
    _busy = true;
    try {
      if (await sendTransport.currentUserId() != s.userId) {
        throw const CatalogFailure('catalog.denied');
      }
      final result = await work(s);
      _guard(s, manage: manage);
      if (await sendTransport.currentUserId() != s.userId) {
        throw const CatalogFailure('catalog.denied');
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<CatalogSyncStatus> load() => _run((s) async {
    final manage = _can(s, PermissionCodes.catalogManage);
    final blocked = (await database.query(
      CatalogSyncJournal.device,
      where: 'farm_id=? AND restore_blocked=1',
      whereArgs: [s.farmId],
    )).isNotEmpty;
    final conflicts = (await projection.conflicts())
        .map(CatalogConflictReview.fromRow)
        .toList();
    final unpublished = <CatalogPublicationReview>[];
    if (manage && !blocked) {
      final rows = await database.rawQuery(
        '''SELECT e.* FROM ${SqliteCompanyCatalog.entriesTable} e WHERE e.farm_id=?
      AND NOT EXISTS (SELECT 1 FROM ${CatalogSyncJournal.outbox} q WHERE q.farm_id=e.farm_id AND q.entity='entry' AND q.target_id=e.id)
      AND NOT EXISTS (SELECT 1 FROM ${CatalogSyncJournal.shadow} q WHERE q.farm_id=e.farm_id AND q.entity='entry' AND q.target_id=e.id)
      AND NOT EXISTS (SELECT 1 FROM ${CatalogSyncJournal.inbox} q WHERE q.farm_id=e.farm_id AND q.entity='entry' AND q.target_id=e.id)
      AND NOT EXISTS (SELECT 1 FROM ${CatalogSyncJournal.conflicts} q WHERE q.farm_id=e.farm_id AND q.entity='entry' AND q.target_id=e.id)
      ORDER BY CASE WHEN e.kind='unit' THEN 0 ELSE 1 END,e.name LIMIT 200''',
        [s.farmId],
      );
      unpublished.addAll(rows.map(CatalogPublicationReview.fromRow));
    }
    final labels = <String, String>{};
    for (final entity in ['entry', 'request']) {
      final table = entity == 'entry'
          ? SqliteCompanyCatalog.entriesTable
          : SqliteCompanyCatalog.requestsTable;
      final rows = await database.query(
        table,
        where: manage || entity == 'entry'
            ? 'farm_id=?'
            : 'farm_id=? AND actor_uid=?',
        whereArgs: manage || entity == 'entry'
            ? [s.farmId]
            : [s.farmId, s.userId],
      );
      for (final r in rows) {
        labels['$entity/${r['id']}'] = '${r['code']} · ${r['name']}';
      }
    }
    final count = manage
        ? (await database.rawQuery(
                "SELECT COUNT(*) AS n FROM ${CatalogSyncJournal.outbox} WHERE farm_id=? AND state<>'acked'",
                [s.farmId],
              )).single['n']
              as int
        : 0;
    return CatalogSyncStatus(
      counts: Map.unmodifiable(await journal.counts(s.farmId, s.userId)),
      restoreBlocked: blocked,
      canManage: manage,
      farmUnresolved: count,
      conflicts: List.unmodifiable(conflicts),
      unpublished: List.unmodifiable(unpublished),
      labels: Map.unmodifiable(labels),
    );
  });
  @override
  Future<bool> synchronize() => _run((s) async {
    var complete = true;
    final blocked = (await database.query(
      CatalogSyncJournal.device,
      where: 'farm_id=? AND restore_blocked=1',
      whereArgs: [s.farmId],
    )).isNotEmpty;
    if (!blocked) {
      final receipts = await recovery.recover();
      if (receipts.unavailable) {
        throw const CatalogSyncUnavailable();
      }
      final sent = await sender.synchronize();
      if (sent.unavailable) {
        throw const CatalogSyncUnavailable();
      }
      if (sent.sessionChanged) {
        throw const CatalogFailure('catalog.denied');
      }
      complete = sent.blocked == 0 && sent.conflicts == 0;
    }
    final received = await receiver.receive(maxPages: 100);
    final applied = await projection.apply(maxRecords: 5000);
    final counts = await journal.counts(s.farmId, s.userId);
    final remaining = [
      'pending',
      'blocked',
      'conflict',
    ].any((key) => (counts[key] ?? 0) > 0);
    final conflicts = await projection.conflicts();
    return complete &&
        received.complete &&
        applied.complete &&
        applied.conflicts == 0 &&
        conflicts.isEmpty &&
        !remaining &&
        !blocked;
  });
  @override
  Future<void> decide(
    CatalogConflictReview review,
    CatalogConflictChoice choice,
    String reason,
  ) => _run((_) async {
    if (choice == CatalogConflictChoice.keepLocal &&
        (await database.query(
          CatalogSyncJournal.device,
          where: 'farm_id=? AND restore_blocked=1',
          whereArgs: [review.farmId],
        )).isNotEmpty) {
      throw const CatalogFailure('catalog.restoreReconcileRequired');
    }
    await decisions.decide(review, choice: choice, reason: reason);
  }, manage: true);
  @override
  Future<void> prepare(CatalogPublicationReview review, String reason) =>
      _run((_) => publication.prepare(review, reason: reason), manage: true);
  @override
  Future<CatalogRestoreReview> reviewRestore() =>
      _run((_) => restore.review(), manage: true);
  @override
  Future<void> releaseRestore(
    CatalogRestoreReview review,
    String reason,
    Set<String> keepLocalOnly,
  ) => _run(
    (_) => restore.unlock(review, reason: reason, keepLocalOnly: keepLocalOnly),
    manage: true,
  );
  @override
  void dispose() {
    _disposed = true;
    sender.dispose();
    recovery.dispose();
    receiver.dispose();
    projection.dispose();
    decisions.dispose();
    publication.dispose();
    restore.dispose();
  }
}
