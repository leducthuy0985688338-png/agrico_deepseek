import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';

class _Authority implements ApprovalAuthority {
  _Authority({this.beforeReturn});
  final void Function()? beforeReturn;
  @override
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy policy,
    String digest,
  ) async => policy.authorityReference == 'TEST-ONLY-authority:$digest';
  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy p,
    String digest,
  ) async {
    beforeReturn?.call();
    return 'TEST-ONLY-authority:$digest';
  }
}

void main() {
  sqfliteFfiInit();
  AuthorizationSubject user(String id, {Set<String>? permissions}) =>
      AuthorizationSubject(
        userId: id,
        membershipId: id,
        farmId: 'f',
        permissionCodes: permissions ?? PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
  DocumentApprovalPolicy policy({
    ApprovalKind kind = ApprovalKind.materialIssue,
    String currency = 'VND',
    String? selfLimit = '100',
    String? independentLimit = '1000',
    bool selfEnabled = true,
    int version = 1,
  }) => DocumentApprovalPolicy(
    farm: 'f',
    kind: kind,
    currency: currency,
    version: version,
    selfEnabled: selfEnabled,
    selfLimit: selfLimit,
    independentLimit: independentLimit,
    createPermission: PermissionCodes.inventoryManage,
    approvePermission: PermissionCodes.financeApprove,
    changedBy: 'manager',
    active: true,
    activatedBy: 'authority',
    activatedAt: '2026-10-01T00:00:00Z',
    authorityReference: 'TEST-ONLY',
  );
  ApprovalContext context({
    ApprovalKind kind = ApprovalKind.materialIssue,
    String total = '99',
    String currency = 'VND',
    String state = 'pending',
    bool periodOpen = true,
    bool complete = true,
    int version = 1,
    Set<String> beneficiaries = const {},
    int related = 1,
    String? exposure,
    String creator = 'maker',
    String createdAt = '2026-10-20T00:00:00Z',
  }) => ApprovalContext(
    farm: 'f',
    kind: kind,
    sourceId: 'source',
    revision: 1,
    digest: '0' * 64,
    creator: creator,
    createdAt: createdAt,
    currency: currency,
    total: total,
    policyVersion: version,
    state: state,
    periodOpen: periodOpen,
    metadataComplete: complete,
    relatedKey: 'contract-verified',
    linkEvidenceVerified: true,
    beneficiariesVerified: true,
    beneficiaries: beneficiaries,
    relatedTotal: exposure,
    relatedDocuments: related,
  );
  test('creator with no approve permission is not implicitly approved', () {
    expect(
      ApprovalRules.evaluate(
        context(),
        policy(),
        user('maker', permissions: {PermissionCodes.inventoryManage}),
      ).allowed,
      isFalse,
    );
  });
  test('missing policy is safe and never self enables', () {
    expect(
      ApprovalRules.evaluate(context(), null, user('maker')).reason,
      'noActivePolicy',
    );
  });
  test(
    'explicit self policy plus live create approve and self permission permits exact total',
    () {
      expect(
        ApprovalRules.evaluate(
          context(total: '100'),
          policy(),
          user('maker'),
        ).reason,
        'explicitSelfApproval',
      );
    },
  );
  test('ordinary approve does not include explicit self permission', () {
    expect(
      ApprovalRules.evaluate(
        context(),
        policy(),
        user(
          'maker',
          permissions: {
            PermissionCodes.inventoryManage,
            PermissionCodes.financeApprove,
          },
        ),
      ).reason,
      'selfPermissionMissing',
    );
  });
  test('policy can disable self without hiding an independent route', () {
    expect(
      ApprovalRules.evaluate(
        context(),
        policy(selfEnabled: false),
        user('maker'),
      ).outcome,
      ApprovalOutcome.independentRequired,
    );
  });
  test('limit comparison is exact above fifteen digits', () {
    final p = policy(selfLimit: '9007199254740993.01');
    expect(
      ApprovalRules.evaluate(
        context(total: '9007199254740993.01'),
        p,
        user('maker'),
      ).allowed,
      isTrue,
    );
    expect(
      ApprovalRules.evaluate(
        context(total: '9007199254740993.02'),
        p,
        user('maker'),
      ).reason,
      'selfLimitExceeded',
    );
  });
  test('missing self limit does not mean infinity', () {
    expect(
      ApprovalRules.evaluate(
        context(),
        policy(selfLimit: null),
        user('maker'),
      ).allowed,
      isFalse,
    );
  });
  test('VND policy cannot be used for LAK', () {
    expect(
      ApprovalRules.evaluate(
        context(currency: 'LAK'),
        policy(),
        user('maker'),
      ).reason,
      'policyScopeMismatch',
    );
  });
  test('multiple lines use full source exposure, never a line subtotal', () {
    expect(
      ApprovalRules.evaluate(
        context(total: '120'),
        policy(),
        user('maker'),
      ).reason,
      'selfLimitExceeded',
    );
  });
  test('related documents require review and are not labelled fraud', () {
    final d = ApprovalRules.evaluate(
      context(total: '50', related: 2, exposure: '100'),
      policy(),
      user('maker'),
    );
    expect(d.outcome, ApprovalOutcome.independentRequired);
    expect(d.reason, 'relatedDocumentsRequireIndependentReview');
  });
  test('independent cap uses related aggregate', () {
    expect(
      ApprovalRules.evaluate(
        context(total: '50', related: 2, exposure: '1001'),
        policy(),
        user('reviewer'),
      ).reason,
      'independentLimitExceeded',
    );
  });
  test('beneficiary cannot independently approve either', () {
    expect(
      ApprovalRules.evaluate(
        context(beneficiaries: {'reviewer'}),
        policy(),
        user('reviewer'),
      ).reason,
      'conflictOfInterest',
    );
  });
  for (final kind in ApprovalKind.values.where(
    (k) => !DocumentApprovalPolicy.selfKinds.contains(k),
  )) {
    test(
      'mandatory independent ${kind.name} rejects even full permission actor',
      () {
        final d = ApprovalRules.evaluate(
          context(kind: kind),
          policy(kind: kind, selfEnabled: false),
          user('maker'),
        );
        expect(d.outcome, ApprovalOutcome.independentRequired);
      },
    );
  }
  test(
    'technical admin does not receive policy or self authority by template',
    () {
      expect(
        CompanyRolePolicy.permissions(
          CompanyRole.systemAdmin,
        ).intersection(PermissionCodes.guardedApprovalPermissions),
        isEmpty,
      );
    },
  );
  test('independent reviewer passes with separate configured cap', () {
    expect(
      ApprovalRules.evaluate(context(), policy(), user('reviewer')).reason,
      'independentApproval',
    );
  });
  test(
    'missing independent cap refuses instead of assuming a business limit',
    () {
      expect(
        ApprovalRules.evaluate(
          context(),
          policy(independentLimit: null),
          user('reviewer'),
        ).reason,
        'independentLimitNotConfigured',
      );
    },
  );
  test('policy version change fails closed', () {
    expect(
      ApprovalRules.evaluate(
        context(version: 1),
        policy(version: 2),
        user('reviewer'),
      ).reason,
      'policyChanged',
    );
  });
  test('policy activation cannot upgrade old pending self sources', () {
    expect(
      ApprovalRules.evaluate(
        context(createdAt: '2026-09-30T00:00:00Z'),
        policy(),
        user('maker'),
      ).reason,
      'policyCannotUpgradePendingSelf',
    );
  });
  for (final state in ['approved', 'cancelled', 'void']) {
    test('terminal $state cannot be approved again', () {
      expect(
        ApprovalRules.evaluate(
          context(state: state),
          policy(),
          user('reviewer'),
        ).reason,
        'notPending',
      );
    });
  }
  test('closed period and incomplete source are denied', () {
    expect(
      ApprovalRules.evaluate(
        context(periodOpen: false),
        policy(),
        user('reviewer'),
      ).reason,
      'periodClosed',
    );
    expect(
      ApprovalRules.evaluate(
        context(complete: false),
        policy(),
        user('reviewer'),
      ).reason,
      'incompleteSource',
    );
  });
  test('signed correction cap uses absolute exposure', () {
    expect(
      ApprovalRules.evaluate(
        context(kind: ApprovalKind.correction, total: '-1001'),
        policy(kind: ApprovalKind.correction, selfEnabled: false),
        user('reviewer'),
      ).reason,
      'independentLimitExceeded',
    );
  });

  group('SQLite controlled configuration', () {
    late Database db;
    late AuthorizationSubject? live;
    SqliteApprovalPolicyStore store({ApprovalAuthority? authority}) =>
        SqliteApprovalPolicyStore(
          db,
          opened: live!,
          currentSubject: () => live,
          authority: authority,
        );
    DocumentApprovalPolicy draft(int version) => DocumentApprovalPolicy(
      farm: 'f',
      kind: ApprovalKind.materialIssue,
      currency: 'VND',
      version: version,
      selfEnabled: true,
      selfLimit: '100',
      independentLimit: '1000',
      createPermission: PermissionCodes.inventoryManage,
      approvePermission: PermissionCodes.financeApprove,
      changedBy: 'manager',
    );
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await SqliteApprovalPolicyStore.createSchema(db);
      live = user('manager');
    });
    tearDown(() async {
      await db.close();
    });
    test(
      'draft records exact limits, before/after and does not become effective',
      () async {
        await store().propose(draft(1), 'Test policy');
        expect(
          await SqliteApprovalPolicyStore.active(
            db,
            'f',
            ApprovalKind.materialIssue,
            'VND',
          ),
          isNull,
        );
        await SqliteApprovalPolicyStore.validate(db);
        expect((await db.query(SqliteApprovalPolicyStore.audit)).length, 1);
      },
    );
    test(
      'missing trusted authority blocks activation despite permission',
      () async {
        await store().propose(draft(1), 'Test policy');
        live = user('authority');
        await expectLater(
          store().activate(ApprovalKind.materialIssue, 'VND', 1, 0, 'Review'),
          throwsStateError,
        );
        expect(
          (await db.query(SqliteApprovalPolicyStore.policies)).single['state'],
          'draft',
        );
      },
    );
    test(
      'manager cannot activate own higher limit even with injected authority',
      () async {
        await store().propose(draft(1), 'Test policy');
        await expectLater(
          store(
            authority: _Authority(),
          ).activate(ApprovalKind.materialIssue, 'VND', 1, 0, 'Self upgrade'),
          throwsStateError,
        );
      },
    );
    test(
      'separate trusted activation and supersession keep complete immutable audit',
      () async {
        await store().propose(draft(1), 'Version 1');
        live = user('authority');
        await store(authority: _Authority()).activate(
          ApprovalKind.materialIssue,
          'VND',
          1,
          0,
          'Independent review',
        );
        live = user('manager');
        await store().propose(draft(2), 'Version 2');
        live = user('authority');
        await store(authority: _Authority()).activate(
          ApprovalKind.materialIssue,
          'VND',
          2,
          1,
          'Independent second review',
        );
        expect(
          (await SqliteApprovalPolicyStore.active(
            db,
            'f',
            ApprovalKind.materialIssue,
            'VND',
          ))!.version,
          2,
        );
        await SqliteApprovalPolicyStore.validate(db);
        await expectLater(
          db.delete(SqliteApprovalPolicyStore.audit),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
    test('revocation while authority resolves rolls back activation', () async {
      await store().propose(draft(1), 'Test policy');
      live = user('authority');
      final s = store(
        authority: _Authority(
          beforeReturn: () {
            live = null;
          },
        ),
      );
      await expectLater(
        s.activate(ApprovalKind.materialIssue, 'VND', 1, 0, 'Review'),
        throwsStateError,
      );
      expect(
        (await db.query(SqliteApprovalPolicyStore.policies)).single['state'],
        'draft',
      );
    });
    test(
      'concurrent draft replay creates one configuration and one event',
      () async {
        final s = store();
        await Future.wait([
          s.propose(draft(1), 'Test policy'),
          s.propose(draft(1), 'Test policy'),
        ]);
        expect((await db.query(SqliteApprovalPolicyStore.policies)).length, 1);
        expect((await db.query(SqliteApprovalPolicyStore.audit)).length, 1);
      },
    );
    test(
      'new schema installation is idempotent and preserves test rows',
      () async {
        await store().propose(draft(1), 'Test policy');
        final before = await db.query(SqliteApprovalPolicyStore.policies);
        await SqliteApprovalPolicyStore.createSchema(db);
        expect(await db.query(SqliteApprovalPolicyStore.policies), before);
      },
    );
    test(
      'policy identity columns must match the canonical signed payload',
      () async {
        await store().propose(draft(1), 'Synthetic policy');
        final row = (await db.query(SqliteApprovalPolicyStore.policies)).single;
        await db.insert(SqliteApprovalPolicyStore.policies, {
          ...row,
          'farm_id': 'other',
        });
        await expectLater(
          SqliteApprovalPolicyStore.validate(db),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'integrity reason',
              'Policy digest mismatch.',
            ),
          ),
        );
      },
    );
  });
}
