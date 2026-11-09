import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../periods/period_lock.dart';
import '../permissions/authorization.dart';
import 'approval_policy.dart';
import 'approval_administration.dart';
import 'approval_policy_catalog.dart';

/// Must resolve a separately provisioned authority, never infer it from admin.
abstract interface class ApprovalAuthority {
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  );
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy policy,
    String digest,
  );
}

abstract interface class ApprovalRelationsAuthority {
  /// null is unresolved; an empty set is an explicitly verified external party.
  Future<Set<String>?> beneficiaryUsers(String farm, String partyId);
}

abstract interface class ApprovalDraftAuthority {
  Future<void> publishDraft(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  );
}

class SqliteApprovalPolicyStore
    implements ApprovalAdministration, RemoteApprovalAdministration {
  const SqliteApprovalPolicyStore(
    this.db, {
    required this.opened,
    required this.currentSubject,
    this.authority,
  });
  final Database db;
  final AuthorizationSubject opened;
  final AuthorizationSubject? Function() currentSubject;
  final ApprovalAuthority? authority;
  static String? serverActivationTime(String reference) {
    try {
      final value = (jsonDecode(reference) as Map)['activatedAt'];
      return value is String && DateTime.tryParse(value) != null ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<DocumentApprovalPolicy?> effective(
    DatabaseExecutor tx,
    String farm,
    ApprovalKind kind,
    String currency,
  ) async {
    final p = await active(tx, farm, kind, currency);
    if (p == null || authority == null) return null;
    await validate(tx);
    return await authority!.isActivationCurrent(
          p,
          PeriodLock.digest(p.toJson()),
        )
        ? p
        : null;
  }

  static const policies = 'approval_policies_v2',
      audit = 'approval_policy_audit_v2';
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $policies(farm_id TEXT NOT NULL,kind TEXT NOT NULL,
      currency TEXT NOT NULL,version INTEGER NOT NULL CHECK(version>0),payload TEXT NOT NULL,digest TEXT NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('draft','active','superseded')),changed_by TEXT NOT NULL,
      changed_at TEXT NOT NULL,activated_by TEXT,activated_at TEXT,authority_reference TEXT,
      PRIMARY KEY(farm_id,kind,currency,version))''',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS approval_one_active_v2 ON $policies(farm_id,kind,currency) WHERE state='active'",
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $audit(id INTEGER PRIMARY KEY,farm_id TEXT NOT NULL,
      kind TEXT NOT NULL,currency TEXT NOT NULL,version INTEGER NOT NULL,action TEXT NOT NULL,
      actor_id TEXT NOT NULL,occurred_at TEXT NOT NULL,reason TEXT NOT NULL,before_json TEXT NOT NULL,
      after_json TEXT NOT NULL,previous_digest TEXT NOT NULL,event_digest TEXT NOT NULL)''',
    );
    for (final op in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS approval_audit_${op.toLowerCase()} BEFORE $op ON $audit BEGIN SELECT RAISE(ABORT,'IMMUTABLE_APPROVAL_AUDIT'); END",
      );
    }
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS approval_policy_no_delete BEFORE DELETE ON $policies BEGIN SELECT RAISE(ABORT,'IMMUTABLE_POLICY_HISTORY'); END",
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS approval_policy_transition BEFORE UPDATE ON $policies
      WHEN OLD.farm_id<>NEW.farm_id OR OLD.kind<>NEW.kind OR OLD.currency<>NEW.currency
      OR OLD.version<>NEW.version OR OLD.payload<>NEW.payload OR OLD.digest<>NEW.digest
      OR OLD.changed_by<>NEW.changed_by OR OLD.changed_at<>NEW.changed_at
      OR NOT ((OLD.state='draft' AND NEW.state='active') OR (OLD.state='active' AND NEW.state='superseded'))
      BEGIN SELECT RAISE(ABORT,'INVALID_POLICY_TRANSITION'); END''',
    );
  }

  AuthorizationSubject require(String permission, {ResourceContext? resource}) {
    final s = currentSubject();
    if (s == null ||
        s.userId != opened.userId ||
        s.membershipId != opened.membershipId ||
        s.farmId != opened.farmId ||
        !const AuthorizationService().can(
          subject: s,
          permission: permission,
          resource: resource ?? ResourceContext(farmId: opened.farmId),
        )) {
      throw StateError('Approval policy permission denied.');
    }
    return s;
  }

  static DocumentApprovalPolicy decode(Map<String, Object?> r) {
    final p = jsonDecode(r['payload'] as String) as Map;
    return DocumentApprovalPolicy(
      farm: r['farm_id'] as String,
      kind: ApprovalKind.values.byName(r['kind'] as String),
      currency: r['currency'] as String,
      version: r['version'] as int,
      selfEnabled: p['selfEnabled'] as bool,
      selfLimit: p['selfLimit'] as String?,
      independentLimit: p['independentLimit'] as String?,
      createPermission: p['createPermission'] as String,
      approvePermission: p['approvePermission'] as String,
      changedBy: r['changed_by'] as String,
      active: r['state'] == 'active',
      activatedBy: r['activated_by'] as String?,
      activatedAt: r['activated_at'] as String?,
      authorityReference: r['authority_reference'] as String?,
    );
  }

  @override
  Future<void> syncPolicy(ApprovalKind kind, String currency) async {
    requirePolicyRead();
    final actor = currentSubject()!, a = authority;
    if (a is! ApprovalPolicyCatalogAuthority) {
      throw StateError('Authenticated catalog unavailable.');
    }
    final snapshot = await (a as ApprovalPolicyCatalogAuthority).catalog(
      actor,
      kind,
      currency,
    );
    requirePolicyRead();
    final remote = snapshot.active;
    if (remote != null &&
        !(await a!.isActivationCurrent(remote.policy, remote.digest))) {
      throw StateError('Remote activation withdrawn.');
    }
    requirePolicyRead();
    await db.transaction((tx) async {
      requirePolicyRead();
      final old = await active(tx, actor.farmId, kind, currency);
      if (old != null &&
          old.version > (snapshot.expectedActive?['version'] as int? ?? 0)) {
        throw StateError('Stale catalog cannot roll back local policy.');
      }
      if (old != null &&
          (remote == null || old.version != remote.policy.version)) {
        final row = (await tx.query(
          policies,
          where: "farm_id=? AND kind=? AND currency=? AND state='active'",
          whereArgs: [actor.farmId, kind.name, currency],
        )).single;
        await tx.update(
          policies,
          {'state': 'superseded'},
          where: "farm_id=? AND kind=? AND currency=? AND state='active'",
          whereArgs: [actor.farmId, kind.name, currency],
        );
        await event(
          tx,
          row,
          'remoteSupersede',
          actor.userId,
          'Authenticated server snapshot replaced local metadata',
          row,
          {...row, 'state': 'superseded'},
        );
      }
      for (final item in [?remote, ...snapshot.drafts]) {
        final p = item.policy;
        final row = <String, Object?>{
          'farm_id': p.farm,
          'kind': p.kind.name,
          'currency': p.currency,
          'version': p.version,
          'payload': PeriodLock.encode(p.toJson()),
          'digest': item.digest,
          'state': p.active ? 'active' : 'draft',
          'changed_by': p.changedBy,
          'changed_at': item.proposedAt,
          'activated_by': p.activatedBy,
          'activated_at': p.activatedAt,
          'authority_reference': p.authorityReference,
        };
        final existing = await tx.query(
          policies,
          where: 'farm_id=? AND kind=? AND currency=? AND version=?',
          whereArgs: [p.farm, p.kind.name, p.currency, p.version],
        );
        if (existing.isNotEmpty) {
          final before = existing.single;
          if (before['digest'] != item.digest ||
              before['payload'] != row['payload'] ||
              before['changed_by'] != p.changedBy ||
              before['state'] == 'superseded') {
            throw StateError('Local/remote policy identity conflict.');
          }
          if (before['state'] == row['state']) {
            if (p.active &&
                before['authority_reference'] != p.authorityReference) {
              throw StateError('Activation identity conflict.');
            }
            continue;
          }
          if (!p.active || before['state'] != 'draft') {
            throw StateError('Policy state cannot be rolled back.');
          }
          await tx.update(
            policies,
            {
              'state': 'active',
              'activated_by': p.activatedBy,
              'activated_at': p.activatedAt,
              'authority_reference': p.authorityReference,
            },
            where: 'farm_id=? AND kind=? AND currency=? AND version=?',
            whereArgs: [p.farm, p.kind.name, p.currency, p.version],
          );
        } else {
          await tx.insert(policies, row);
        }
        await event(
          tx,
          row,
          'remoteImport',
          actor.userId,
          'Authenticated metadata import revision ${item.authorityRevision}, server proposal ${item.proposedAt}; author preserved',
          existing.firstOrNull,
          (await tx.query(
            policies,
            where: 'farm_id=? AND kind=? AND currency=? AND version=?',
            whereArgs: [p.farm, p.kind.name, p.currency, p.version],
          )).single,
        );
      }
      requirePolicyRead();
      await validate(tx);
    });
  }

  static Future<DocumentApprovalPolicy?> active(
    DatabaseExecutor db,
    String farm,
    ApprovalKind kind,
    String currency,
  ) async {
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [policies],
    )).isEmpty) {
      return null;
    }
    final rows = await db.query(
      policies,
      where: "farm_id=? AND kind=? AND currency=? AND state='active'",
      whereArgs: [farm, kind.name, currency],
    );
    return rows.isEmpty ? null : decode(rows.single);
  }

  void requirePolicyRead() {
    try {
      require(ApprovalRules.policyManage);
    } on StateError {
      require(ApprovalRules.policyActivate);
    }
  }

  @override
  Future<List<Map<String, Object?>>> list() async {
    requirePolicyRead();
    final a = authority;
    if (a is ApprovalPolicyCatalogAuthority) {
      await (a as ApprovalPolicyCatalogAuthority).catalog(
        currentSubject()!,
        ApprovalKind.machineRun,
        'VND',
      );
      requirePolicyRead();
    }
    final rows = await db.query(
      policies,
      where: 'farm_id=?',
      whereArgs: [opened.farmId],
      orderBy: 'kind,currency,version',
    );
    requirePolicyRead();
    return rows;
  }

  @override
  Future<void> publishDraft(
    ApprovalKind kind,
    String currency,
    int version,
  ) => db.transaction((tx) async {
    final actor = require(ApprovalRules.policyManage);
    require(ApprovalRules.limitManage);
    await validate(tx);
    final rows = await tx.query(
      policies,
      where:
          "farm_id=? AND kind=? AND currency=? AND version=? AND state='draft'",
      whereArgs: [actor.farmId, kind.name, currency, version],
    );
    if (rows.length != 1 || rows.single['changed_by'] != actor.userId) {
      throw StateError('Only the actual policy author may publish its draft.');
    }
    final a = authority;
    if (a is! ApprovalDraftAuthority) {
      throw StateError('Trusted policy proposal service is not provisioned.');
    }
    await (a as ApprovalDraftAuthority).publishDraft(
      actor,
      decode(rows.single),
      rows.single['digest'] as String,
    );
    require(ApprovalRules.policyManage);
    require(ApprovalRules.limitManage);
    await event(
      tx,
      rows.single,
      'publish',
      actor.userId,
      'Authenticated policy author published draft',
      rows.single,
      rows.single,
    );
  });

  @override
  Future<List<Map<String, Object?>>> policyHistory() async {
    final s = require(ApprovalRules.auditView);
    final result = await db.query(
      audit,
      where: 'farm_id=?',
      whereArgs: [s.farmId],
      orderBy: 'id',
    );
    require(ApprovalRules.auditView);
    return result;
  }

  @override
  Future<void> propose(
    DocumentApprovalPolicy p,
    String reason,
  ) => db.transaction((tx) async {
    final actor = require(ApprovalRules.policyManage);
    require(ApprovalRules.limitManage);
    p.validate();
    if (p.active ||
        p.farm != actor.farmId ||
        p.changedBy != actor.userId ||
        reason.trim().isEmpty) {
      throw StateError('Explicit scoped proposal and reason required.');
    }
    final old = await tx.query(
      policies,
      where: 'farm_id=? AND kind=? AND currency=?',
      whereArgs: [p.farm, p.kind.name, p.currency],
      orderBy: 'version DESC',
    );
    final payload = PeriodLock.encode(p.toJson()),
        digest = PeriodLock.digest(p.toJson());
    if (old.isNotEmpty &&
        old.first['version'] == p.version &&
        old.first['digest'] == digest) {
      return;
    }
    if (p.version != (old.isEmpty ? 1 : (old.first['version'] as int) + 1)) {
      throw StateError('Stale policy proposal.');
    }
    final row = <String, Object?>{
      'farm_id': p.farm,
      'kind': p.kind.name,
      'currency': p.currency,
      'version': p.version,
      'payload': payload,
      'digest': digest,
      'state': 'draft',
      'changed_by': actor.userId,
      'changed_at': DateTime.now().toUtc().toIso8601String(),
      'activated_by': null,
      'activated_at': null,
      'authority_reference': null,
    };
    await tx.insert(policies, row);
    await event(tx, row, 'propose', actor.userId, reason, old.firstOrNull, row);
    require(ApprovalRules.policyManage);
    require(ApprovalRules.limitManage);
  });
  @override
  Future<void> activate(
    ApprovalKind kind,
    String currency,
    int version,
    int expectedActive,
    String reason,
  ) => db.transaction((tx) async {
    final actor = require(ApprovalRules.policyActivate);
    await validate(tx);
    final rows = await tx.query(
      policies,
      where: 'farm_id=? AND kind=? AND currency=? AND version=?',
      whereArgs: [actor.farmId, kind.name, currency, version],
    );
    if (rows.length != 1 ||
        rows.single['state'] != 'draft' ||
        reason.trim().isEmpty) {
      throw StateError('Draft and activation reason required.');
    }
    final row = rows.single, p = decode(row);
    if (p.changedBy == actor.userId) {
      throw StateError('Policy author cannot activate own changes.');
    }
    final current = await active(tx, actor.farmId, kind, currency);
    if ((current?.version ?? 0) != expectedActive) {
      throw StateError('Active policy changed.');
    }
    final a = authority;
    final reference = a is ApprovalPolicyCatalogAuthority
        ? await (a as ApprovalPolicyCatalogAuthority).activateCatalog(
            actor,
            p,
            row['digest'] as String,
            expectedActive,
          )
        : await a?.activationReference(actor, p, row['digest'] as String);
    if (reference == null || reference.trim().isEmpty) {
      throw StateError(
        'Trusted policy activation authority is not provisioned.',
      );
    }
    require(ApprovalRules.policyActivate);
    if (current != null) {
      final old = (await tx.query(
        policies,
        where: "farm_id=? AND kind=? AND currency=? AND state='active'",
        whereArgs: [actor.farmId, kind.name, currency],
      )).single;
      await tx.update(
        policies,
        {'state': 'superseded'},
        where: "farm_id=? AND kind=? AND currency=? AND state='active'",
        whereArgs: [actor.farmId, kind.name, currency],
      );
      await event(tx, old, 'supersede', actor.userId, reason, old, {
        ...old,
        'state': 'superseded',
      });
    }
    final after = <String, Object?>{
      ...row,
      'state': 'active',
      'activated_by': actor.userId,
      'activated_at':
          serverActivationTime(reference) ??
          DateTime.now().toUtc().toIso8601String(),
      'authority_reference': reference,
    };
    await tx.update(
      policies,
      {
        'state': 'active',
        'activated_by': actor.userId,
        'activated_at': after['activated_at'],
        'authority_reference': reference,
      },
      where: 'farm_id=? AND kind=? AND currency=? AND version=?',
      whereArgs: [actor.farmId, kind.name, currency, version],
    );
    await event(tx, row, 'activate', actor.userId, reason, row, after);
    require(ApprovalRules.policyActivate);
  });
  static Future<void> event(
    DatabaseExecutor db,
    Map<String, Object?> identity,
    String action,
    String actor,
    String reason,
    Object? before,
    Object? after,
  ) async {
    final history = await db.query(
      audit,
      where: 'farm_id=?',
      whereArgs: [identity['farm_id']],
      orderBy: 'id DESC',
      limit: 1,
    );
    final row = <String, Object?>{
      'farm_id': identity['farm_id'],
      'kind': identity['kind'],
      'currency': identity['currency'],
      'version': identity['version'],
      'action': action,
      'actor_id': actor,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason.trim(),
      'before_json': PeriodLock.encode(before),
      'after_json': PeriodLock.encode(after),
      'previous_digest': history.firstOrNull?['event_digest'] ?? '',
    };
    await db.insert(audit, {...row, 'event_digest': PeriodLock.digest(row)});
  }

  static Future<void> validate(DatabaseExecutor db) async {
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [policies],
    )).isEmpty) {
      return;
    }
    for (final row in await db.query(policies)) {
      decode(row).validate();
      if (row['digest'] !=
              PeriodLock.digest(jsonDecode(row['payload'] as String)) ||
          row['digest'] != PeriodLock.digest(decode(row).toJson())) {
        throw StateError('Policy digest mismatch.');
      }
      if (row['state'] != 'draft' &&
          (row['activated_by'] == row['changed_by'] ||
              row['authority_reference'] == null ||
              row['activated_at'] == null)) {
        throw StateError('Invalid activation authority.');
      }
      final history = await db.query(
        audit,
        where: 'farm_id=? AND kind=? AND currency=? AND version=?',
        whereArgs: [
          row['farm_id'],
          row['kind'],
          row['currency'],
          row['version'],
        ],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (history.isEmpty ||
          PeriodLock.digest(
                jsonDecode(history.single['after_json'] as String),
              ) !=
              PeriodLock.digest(row)) {
        throw StateError('Policy state has no matching audit.');
      }
    }
    final previous = <Object?, Object?>{};
    for (final row in await db.query(audit, orderBy: 'id')) {
      final event = Map<String, Object?>.from(row)
        ..remove('id')
        ..remove('event_digest');
      if (row['previous_digest'] != (previous[row['farm_id']] ?? '') ||
          row['event_digest'] != PeriodLock.digest(event)) {
        throw StateError('Approval audit chain mismatch.');
      }
      previous[row['farm_id']] = row['event_digest'];
    }
  }
}
