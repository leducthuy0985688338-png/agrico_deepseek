import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../permissions/authorization.dart';
import '../permissions/live_authorization.dart';
import '../periods/period_lock.dart';
import 'approval_policy.dart';
import 'sqlite_approval_policy_store.dart';

typedef ApprovalSourceReader =
    Future<ApprovalContext> Function(DatabaseExecutor tx);

/// Approval metadata, not a financial journal. Native repositories own amounts,
/// source state and posting. Callbacks must read/write that SAME transaction.
class SqliteDocumentApproval {
  const SqliteDocumentApproval(this.policies);
  final SqliteApprovalPolicyStore policies;
  // Additive schema: preserve existing test metadata; attempts bind a policy
  // version without inventing a new business source/revision.
  static const requests = 'document_approval_requests_v3';
  static const audit = 'document_approval_audit_v2';
  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteApprovalPolicyStore.createSchema(db);
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $requests(
      farm_id TEXT NOT NULL,kind TEXT NOT NULL,source_id TEXT NOT NULL,
      source_revision INTEGER NOT NULL CHECK(source_revision>=0),source_digest TEXT NOT NULL,
      currency TEXT NOT NULL,policy_version INTEGER NOT NULL,creator TEXT NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('pending','approved','rejected')),
      submitted_at TEXT NOT NULL,decided_by TEXT,decided_at TEXT,reason TEXT,
      evidence_json TEXT NOT NULL,
      PRIMARY KEY(farm_id,kind,source_id,source_revision,policy_version,source_digest))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $audit(
      id INTEGER PRIMARY KEY,farm_id TEXT NOT NULL,kind TEXT NOT NULL,source_id TEXT NOT NULL,
      source_revision INTEGER NOT NULL,source_digest TEXT NOT NULL,policy_version INTEGER NOT NULL,
      action TEXT NOT NULL,actor_id TEXT NOT NULL,occurred_at TEXT NOT NULL,reason TEXT NOT NULL,
      before_json TEXT NOT NULL,after_json TEXT NOT NULL,previous_digest TEXT NOT NULL,event_digest TEXT NOT NULL)''',
    );
    for (final op in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS document_approval_audit_${op.toLowerCase()} BEFORE $op ON $audit BEGIN SELECT RAISE(ABORT,'IMMUTABLE_APPROVAL_AUDIT'); END",
      );
    }
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS document_approval_no_delete_v3 BEFORE DELETE ON $requests BEGIN SELECT RAISE(ABORT,'IMMUTABLE_APPROVAL_REQUEST'); END",
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS document_approval_transition_v3 BEFORE UPDATE ON $requests
      WHEN OLD.state<>'pending' OR NEW.state NOT IN ('approved','rejected')
      OR OLD.farm_id<>NEW.farm_id OR OLD.kind<>NEW.kind OR OLD.source_id<>NEW.source_id
      OR OLD.source_revision<>NEW.source_revision OR OLD.source_digest<>NEW.source_digest
      OR OLD.currency<>NEW.currency OR OLD.policy_version<>NEW.policy_version
      OR OLD.creator<>NEW.creator OR OLD.submitted_at<>NEW.submitted_at
      OR NEW.decided_by IS NULL OR NEW.decided_at IS NULL OR NEW.reason IS NULL OR length(trim(NEW.reason))=0
      BEGIN SELECT RAISE(ABORT,'INVALID_APPROVAL_TRANSITION'); END''',
    );
  }

  AuthorizationSubject actor(String permission, [ResourceContext? resource]) =>
      policies.require(permission, resource: resource);
  List<Object?> key(ApprovalContext c) => [
    c.farm,
    c.kind.name,
    c.sourceId,
    c.revision,
    c.policyVersion,
    c.digest,
  ];
  static const predicate =
      'farm_id=? AND kind=? AND source_id=? AND source_revision=? AND policy_version=? AND source_digest=?';
  Future<Map<String, Object?>?> row(
    DatabaseExecutor tx,
    ApprovalContext c,
  ) async => (await tx.query(
    requests,
    where: predicate,
    whereArgs: key(c),
  )).singleOrNull;
  void match(Map<String, Object?> r, ApprovalContext c) {
    if (r['farm_id'] != c.farm ||
        r['kind'] != c.kind.name ||
        r['source_id'] != c.sourceId ||
        r['source_revision'] != c.revision ||
        r['source_digest'] != c.digest ||
        r['currency'] != c.currency ||
        r['creator'] != c.creator ||
        r['policy_version'] != c.policyVersion) {
      throw StateError(
        'Approval source or policy changed; submit a new revision.',
      );
    }
  }

  String exposure(ApprovalContext c) => PeriodLock.digest({
    'total': c.total,
    'relatedTotal': c.relatedTotal,
    'relatedKey': c.relatedKey,
    'relatedDocuments': c.relatedDocuments,
    'beneficiaries': c.beneficiaries.toList()..sort(),
    'beneficiariesVerified': c.beneficiariesVerified,
    'linkEvidenceVerified': c.linkEvidenceVerified,
    'createdAt': c.createdAt,
    'permissions': c.requiredPermissions.toList()..sort(),
    'scope': [
      c.resource?.farmId,
      c.resource?.machineId,
      c.resource?.warehouseId,
      c.resource?.departmentId,
      c.resource?.fieldId,
      c.resource?.ownerUserId,
    ],
    'metadataComplete': c.metadataComplete,
  });
  String evidence(
    ApprovalContext c,
    DocumentApprovalPolicy? p, {
    ApprovalDecision? decision,
  }) => PeriodLock.encode({
    'sourceDigest': c.digest,
    'policyVersion': c.policyVersion,
    'policyAuthority': p?.authorityReference,
    'total': c.total,
    'currency': c.currency,
    'relatedTotal': c.relatedTotal,
    'relatedKey': c.relatedKey,
    'relatedDocuments': c.relatedDocuments,
    'beneficiaries': c.beneficiaries.toList()..sort(),
    'beneficiariesVerified': c.beneficiariesVerified,
    'linkEvidenceVerified': c.linkEvidenceVerified,
    'resource': [
      c.resource?.farmId,
      c.resource?.machineId,
      c.resource?.warehouseId,
      c.resource?.departmentId,
      c.resource?.fieldId,
    ],
    'decision': decision?.reason,
    'aggregate': decision?.aggregate,
  });
  Future<void> submit(ApprovalSourceReader read) =>
      policies.db.transaction((tx) async {
        final authorization = LiveAuthorization(policies.currentSubject),
            stamp = LiveAuthorization(
              policies.currentSubject,
            ).stamp(policies.opened);
        final c = await read(tx),
            s = actor(ApprovalRules.nativeCreatePermission(c.kind), c.resource);
        if (s.userId != c.creator ||
            s.farmId != c.farm ||
            c.state != 'pending' ||
            !c.metadataComplete ||
            !c.periodOpen ||
            c.revision < 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(c.digest)) {
          throw StateError('Only creator can submit a complete open source.');
        }
        final p = await policies.effective(tx, c.farm, c.kind, c.currency);
        if (p == null || p.version != c.policyVersion) {
          throw StateError('No current trusted policy.');
        }
        final old = await row(tx, c);
        if (old != null) {
          match(old, c);
          if (old['state'] != 'pending') throw StateError('Terminal request.');
          authorization.requireStamp(policies.opened, stamp);
          return;
        }
        final next = <String, Object?>{
          'farm_id': c.farm,
          'kind': c.kind.name,
          'source_id': c.sourceId,
          'source_revision': c.revision,
          'source_digest': c.digest,
          'currency': c.currency,
          'policy_version': c.policyVersion,
          'creator': c.creator,
          'state': 'pending',
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
          'decided_by': null,
          'decided_at': null,
          'reason': null,
          'evidence_json': evidence(c, p),
        };
        await tx.insert(requests, next);
        await event(
          tx,
          next,
          'submit',
          s.userId,
          'Explicit submission',
          null,
          next,
        );
        actor(ApprovalRules.nativeCreatePermission(c.kind), c.resource);
        final check = await read(tx);
        match(next, check);
        authorization.requireStamp(policies.opened, stamp);
        if (!check.periodOpen || check.state != 'pending') {
          throw StateError('Source no longer open.');
        }
      });

  /// Each native adapter supplies its source reader, exact native write and
  /// postcondition. No approval is committed separately from business posting.
  Future<ApprovalDecision> approve({
    required ApprovalSourceReader read,
    required Future<void> Function(Transaction tx) apply,
    required Future<bool> Function(
      Transaction tx,
      ApprovalContext before,
      String actor,
    )
    verifyApplied,
    required String reason,
  }) => policies.db.transaction((tx) async {
    final authorization = LiveAuthorization(policies.currentSubject),
        stamp = LiveAuthorization(
          policies.currentSubject,
        ).stamp(policies.opened);
    if (reason.trim().isEmpty) throw StateError('Approval reason required.');
    final c = await read(tx),
        s = actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource);
    final request = await row(tx, c);
    if (request == null) throw StateError('Explicit submission required.');
    match(request, c);
    if (request['state'] == 'approved') {
      final replayPolicy = await policies.effective(
        tx,
        c.farm,
        c.kind,
        c.currency,
      );
      if (replayPolicy == null || replayPolicy.version != c.policyVersion) {
        throw StateError('Replay requires current verified authority.');
      }
      if (request['decided_by'] != s.userId ||
          !await verifyApplied(tx, c, s.userId)) {
        throw StateError('Replay does not match native approval.');
      }
      authorization.requireStamp(policies.opened, stamp);
      return const ApprovalDecision(
        ApprovalOutcome.allowed,
        'idempotentReplay',
      );
    }
    if (request['state'] != 'pending') throw StateError('Request is terminal.');
    Future<ApprovalDecision> decision() async {
      final source = await read(tx);
      final policy = await policies.effective(tx, c.farm, c.kind, c.currency);
      if (policy == null) {
        throw StateError('Verified approval authority unavailable.');
      }
      return ApprovalRules.evaluate(
        source,
        policy,
        actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource),
      );
    }

    final d = await decision();
    if (!d.allowed) {
      await event(tx, request, 'blocked', s.userId, d.reason, request, request);
      authorization.requireStamp(policies.opened, stamp);
      return d;
    }
    match(request, await read(tx));
    await apply(tx);
    if (!await verifyApplied(tx, c, s.userId)) {
      throw StateError('Native approval postcondition failed.');
    }
    final live = actor(
      ApprovalRules.nativeApprovePermission(c.kind),
      c.resource,
    );
    final p = await policies.effective(tx, c.farm, c.kind, c.currency);
    final post = await read(tx);
    match(request, post);
    if (!post.periodOpen || exposure(post) != exposure(c)) {
      throw StateError(
        'Source period or related exposure changed during write.',
      );
    }
    final finalDecision = ApprovalRules.evaluate(c, p, live);
    if (!finalDecision.allowed) {
      throw StateError('Approval authority changed during write.');
    }
    final next = <String, Object?>{
      ...request,
      'state': 'approved',
      'decided_by': s.userId,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason.trim(),
      'evidence_json': evidence(c, p, decision: finalDecision),
    };
    final n = await tx.update(
      requests,
      next,
      where: '$predicate AND state=?',
      whereArgs: [...key(c), 'pending'],
    );
    if (n != 1) throw StateError('Concurrent approval conflict.');
    await event(tx, next, d.reason, s.userId, reason, request, next);
    actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource);
    authorization.requireStamp(policies.opened, stamp);
    return d;
  });

  Future<void> reject(
    ApprovalSourceReader read,
    String reason, {
    Future<void> Function(Transaction)? apply,
  }) => policies.db.transaction((tx) async {
    final authorization = LiveAuthorization(policies.currentSubject),
        stamp = LiveAuthorization(
          policies.currentSubject,
        ).stamp(policies.opened);
    final c = await read(tx),
        s = actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource);
    if (reason.trim().isEmpty ||
        s.userId == c.creator ||
        !c.periodOpen ||
        c.state != 'pending') {
      throw StateError('Independent rejection and explicit reason required.');
    }
    final old = await row(tx, c);
    if (old == null || old['state'] != 'pending') {
      throw StateError('Pending request required.');
    }
    match(old, c);
    final p = await policies.effective(tx, c.farm, c.kind, c.currency);
    final d = ApprovalRules.evaluate(c, p, s);
    if (!d.allowed) {
      throw StateError('Rejection authority unavailable: ${d.reason}');
    }
    final next = <String, Object?>{
      ...old,
      'state': 'rejected',
      'decided_by': s.userId,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason.trim(),
      'evidence_json': evidence(c, p, decision: d),
    };
    await tx.update(requests, next, where: predicate, whereArgs: key(c));
    await event(tx, next, 'reject', s.userId, reason, old, next);
    actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource);
    authorization.requireStamp(policies.opened, stamp);
    final post = await read(tx);
    match(old, post);
    if (!post.periodOpen ||
        exposure(post) != exposure(c) ||
        !ApprovalRules.evaluate(
          post,
          await policies.effective(tx, c.farm, c.kind, c.currency),
          actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource),
        ).allowed) {
      throw StateError('Rejection authority or source changed.');
    }
    if (apply != null) {
      await apply(tx);
      final finalSource = await read(tx);
      match(old, finalSource);
      if (!finalSource.periodOpen ||
          exposure(finalSource) != exposure(c) ||
          !ApprovalRules.evaluate(
            c,
            await policies.effective(tx, c.farm, c.kind, c.currency),
            actor(ApprovalRules.nativeApprovePermission(c.kind), c.resource),
          ).allowed) {
        throw StateError(
          'Rejection authorization changed during native write.',
        );
      }
    }
    authorization.requireStamp(policies.opened, stamp);
  });
  Future<List<Map<String, Object?>>> history() async {
    final s = actor(ApprovalRules.auditView);
    final result = await policies.db.query(
      audit,
      where: 'farm_id=?',
      whereArgs: [s.farmId],
      orderBy: 'id',
    );
    actor(ApprovalRules.auditView);
    return result;
  }

  static Future<void> validate(DatabaseExecutor tx) async {
    await SqliteApprovalPolicyStore.validate(tx);
    if ((await tx.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [requests],
    )).isEmpty) {
      return;
    }
    final previous = <Object?, Object?>{};
    for (final row in await tx.query(audit, orderBy: 'id')) {
      final event = Map<String, Object?>.from(row)
        ..remove('id')
        ..remove('event_digest');
      if (row['previous_digest'] != (previous[row['farm_id']] ?? '') ||
          row['event_digest'] != PeriodLock.digest(event)) {
        throw StateError('Document approval audit chain mismatch.');
      }
      previous[row['farm_id']] = row['event_digest'];
    }
    for (final request in await tx.query(requests)) {
      final history = await tx.query(
        audit,
        where: predicate,
        whereArgs: [
          request['farm_id'],
          request['kind'],
          request['source_id'],
          request['source_revision'],
          request['policy_version'],
          request['source_digest'],
        ],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (history.isEmpty ||
          PeriodLock.digest(
                jsonDecode(history.single['after_json'] as String),
              ) !=
              PeriodLock.digest(request)) {
        throw StateError('Document approval state has no matching audit.');
      }
    }
  }

  static Future<void> event(
    DatabaseExecutor tx,
    Map<String, Object?> identity,
    String action,
    String actor,
    String reason,
    Object? before,
    Object? after,
  ) async {
    final previous = await tx.query(
      audit,
      where: 'farm_id=?',
      whereArgs: [identity['farm_id']],
      orderBy: 'id DESC',
      limit: 1,
    );
    final e = <String, Object?>{
      for (final k in [
        'farm_id',
        'kind',
        'source_id',
        'source_revision',
        'source_digest',
        'policy_version',
      ])
        k: identity[k],
      'action': action,
      'actor_id': actor,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason.trim(),
      'before_json': PeriodLock.encode(before),
      'after_json': PeriodLock.encode(after),
      'previous_digest': previous.firstOrNull?['event_digest'] ?? '',
    };
    await tx.insert(audit, {...e, 'event_digest': PeriodLock.digest(e)});
  }
}
