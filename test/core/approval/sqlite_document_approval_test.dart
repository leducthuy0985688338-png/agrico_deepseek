import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';

class TestAuthority implements ApprovalAuthority {
  bool trusted = true;
  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  ) async => 'TEST-ONLY:$digest';
  @override
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy policy,
    String digest,
  ) async => trusted && policy.authorityReference == 'TEST-ONLY:$digest';
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late TestAuthority authority;
  late AuthorizationSubject live;
  AuthorizationSubject user(String id, {bool active = true}) =>
      AuthorizationSubject(
        userId: id,
        membershipId: id,
        farmId: 'farm',
        active: active,
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
  SqliteApprovalPolicyStore policies({bool trusted = true}) =>
      SqliteApprovalPolicyStore(
        db,
        opened: live,
        currentSubject: () => live,
        authority: trusted ? authority : null,
      );
  SqliteDocumentApproval engine() => SqliteDocumentApproval(policies());
  Future<ApprovalContext> read(DatabaseExecutor tx) async {
    final r = (await tx.query('native_source')).single;
    return ApprovalContext(
      farm: 'farm',
      kind: ApprovalKind.materialIssue,
      sourceId: 'issue',
      revision: r['revision'] as int,
      digest: PeriodLock.digest({
        'amount': r['amount'],
        'currency': r['currency'],
      }),
      creator: 'maker',
      createdAt: r['created_at'] as String,
      currency: r['currency'] as String,
      total: r['amount'] as String,
      policyVersion: r['policy_version'] as int,
      state: r['state'] as String,
      periodOpen: r['period_open'] == 1,
      metadataComplete: true,
      relatedKey: 'job:1',
      linkEvidenceVerified: true,
      beneficiariesVerified: true,
    );
  }

  Future<void> apply(Transaction tx) async {
    await tx.insert('native_posting', {'source_id': 'issue'});
    await tx.update('native_source', {
      'state': 'approved',
      'approver': live.userId,
    });
  }

  Future<bool> verify(
    Transaction tx,
    ApprovalContext before,
    String actor,
  ) async {
    final r = (await tx.query('native_source')).single;
    return r['state'] == 'approved' &&
        r['approver'] == actor &&
        (await tx.query('native_posting')).length == 1;
  }

  Future<ApprovalDecision> approve({
    Future<void> Function(Transaction)? write,
  }) => engine().approve(
    read: read,
    apply: write ?? apply,
    verifyApplied: verify,
    reason: 'Reviewed source evidence',
  );
  Future<void> submit() async {
    live = user('maker');
    await engine().submit(read);
  }

  Future<int> postings() async => (await db.query('native_posting')).length;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    authority = TestAuthority();
    live = user('manager');
    await SqliteDocumentApproval.createSchema(db);
    await db.execute(
      'CREATE TABLE native_source(revision INTEGER,amount TEXT,currency TEXT,state TEXT,approver TEXT,created_at TEXT,period_open INTEGER,policy_version INTEGER)',
    );
    await db.execute('CREATE TABLE native_posting(source_id TEXT PRIMARY KEY)');
    await policies().propose(
      const DocumentApprovalPolicy(
        farm: 'farm',
        kind: ApprovalKind.materialIssue,
        currency: 'VND',
        version: 1,
        selfEnabled: true,
        selfLimit: '100',
        independentLimit: '1000',
        createPermission: PermissionCodes.inventoryManage,
        approvePermission: PermissionCodes.financeApprove,
        changedBy: 'manager',
      ),
      'Synthetic test limits; not business configuration',
    );
    live = user('authority');
    await policies().activate(
      ApprovalKind.materialIssue,
      'VND',
      1,
      0,
      'Synthetic independent activation',
    );
    await db.insert('native_source', {
      'revision': 1,
      'amount': '100',
      'currency': 'VND',
      'state': 'pending',
      'approver': null,
      'created_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 1))
          .toIso8601String(),
      'period_open': 1,
      'policy_version': 1,
    });
  });
  tearDown(() async => db.close());
  test(
    'explicit submit and independent approve post native source once with audit',
    () async {
      await submit();
      live = user('reviewer');
      expect((await approve()).reason, 'independentApproval');
      expect(await postings(), 1);
      await SqliteDocumentApproval.validate(db);
      expect((await engine().history()).map((r) => r['action']), [
        'submit',
        'independentApproval',
      ]);
    },
  );
  test(
    'creator self approval requires separate explicit action and exact configured cap',
    () async {
      await submit();
      expect(await postings(), 0);
      expect((await approve()).reason, 'explicitSelfApproval');
      expect(await postings(), 1);
    },
  );
  test(
    'retry and concurrent approval do not duplicate native posting',
    () async {
      await submit();
      live = user('reviewer');
      final outcomes = await Future.wait([approve(), approve()]);
      expect(outcomes.map((r) => r.reason), [
        'independentApproval',
        'idempotentReplay',
      ]);
      expect(await postings(), 1);
      expect((await db.query(SqliteDocumentApproval.audit)).length, 2);
    },
  );
  test('no implicit submission when approver invokes approval', () async {
    live = user('reviewer');
    await expectLater(approve(), throwsStateError);
    expect(await postings(), 0);
  });
  test(
    'changed payload after offline submission is rejected without posting',
    () async {
      await submit();
      await db.update('native_source', {'amount': '101'});
      live = user('reviewer');
      await expectLater(approve(), throwsStateError);
      expect(await postings(), 0);
    },
  );
  test(
    'changed source revision or policy version rejects stale pending request',
    () async {
      await submit();
      await db.update('native_source', {'policy_version': 2});
      live = user('reviewer');
      await expectLater(approve(), throwsStateError);
      expect(await postings(), 0);
      await db.update('native_source', {'policy_version': 1, 'revision': 2});
      await expectLater(approve(), throwsStateError);
      expect(await postings(), 0);
    },
  );
  test('late offline approval after period closure does not post', () async {
    await submit();
    await db.update('native_source', {'period_open': 0});
    live = user('reviewer');
    expect((await approve()).reason, 'periodClosed');
    expect(await postings(), 0);
    await SqliteDocumentApproval.validate(db);
  });
  test(
    'revocation during native write rolls back posting, state and approval audit',
    () async {
      await submit();
      live = user('reviewer');
      await expectLater(
        approve(
          write: (tx) async {
            await apply(tx);
            live = user('reviewer', active: false);
          },
        ),
        throwsStateError,
      );
      expect(await postings(), 0);
      expect((await db.query('native_source')).single['state'], 'pending');
      expect((await db.query(SqliteDocumentApproval.audit)).length, 1);
    },
  );
  test('authority withdrawal during write rolls back native posting', () async {
    await submit();
    live = user('reviewer');
    await expectLater(
      approve(
        write: (tx) async {
          await apply(tx);
          authority.trusted = false;
        },
      ),
      throwsStateError,
    );
    expect(await postings(), 0);
  });
  test('period closure during write rolls back native posting', () async {
    await submit();
    live = user('reviewer');
    await expectLater(
      approve(
        write: (tx) async {
          await apply(tx);
          await tx.update('native_source', {'period_open': 0});
        },
      ),
      throwsStateError,
    );
    expect(await postings(), 0);
  });
  test(
    'financial payload change during write rolls back rather than approving old digest',
    () async {
      await submit();
      live = user('reviewer');
      await expectLater(
        approve(
          write: (tx) async {
            await apply(tx);
            await tx.update('native_source', {'amount': '99'});
          },
        ),
        throwsStateError,
      );
      expect(await postings(), 0);
    },
  );
  test(
    'rejection is independent, requires reason, is terminal and audited',
    () async {
      await submit();
      await expectLater(
        engine().reject(read, 'Creator rejected own request'),
        throwsStateError,
      );
      live = user('reviewer');
      await expectLater(engine().reject(read, ' '), throwsStateError);
      await engine().reject(read, 'Insufficient source evidence');
      await expectLater(approve(), throwsStateError);
      expect(await postings(), 0);
      await SqliteDocumentApproval.validate(db);
      expect(
        (await db.query(SqliteDocumentApproval.requests)).single['reason'],
        'Insufficient source evidence',
      );
    },
  );
  test(
    'failed native network/IO outcome rolls back request and retains pending retry',
    () async {
      await submit();
      live = user('reviewer');
      await expectLater(
        approve(
          write: (tx) async {
            await apply(tx);
            throw StateError('Simulated IO failure');
          },
        ),
        throwsStateError,
      );
      expect(
        (await db.query(SqliteDocumentApproval.requests)).single['state'],
        'pending',
      );
      expect((await approve()).allowed, isTrue);
      expect(await postings(), 1);
    },
  );
  test(
    'restored active policy cannot authorize without live trusted authority',
    () async {
      expect(
        await policies(
          trusted: false,
        ).effective(db, 'farm', ApprovalKind.materialIssue, 'VND'),
        isNull,
      );
      authority.trusted = false;
      expect(
        await policies().effective(
          db,
          'farm',
          ApprovalKind.materialIssue,
          'VND',
        ),
        isNull,
      );
    },
  );
  test(
    'audit cannot be mutated and schema reinstallation preserves requests',
    () async {
      await submit();
      await SqliteDocumentApproval.createSchema(db);
      expect((await db.query(SqliteDocumentApproval.requests)).length, 1);
      await expectLater(
        db.delete(SqliteDocumentApproval.audit),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update(SqliteDocumentApproval.requests, {'creator': 'attacker'}),
        throwsA(isA<DatabaseException>()),
      );
      await SqliteDocumentApproval.validate(db);
    },
  );
  test(
    'activation-only member may read policy drafts but cannot author or manage limits',
    () async {
      live = AuthorizationSubject(
        userId: 'independent-activator',
        membershipId: 'independent-activator',
        farmId: 'farm',
        permissionCodes: const {ApprovalRules.policyActivate},
        dataScopes: const {DataScope.allFarm},
      );
      final rows = await policies().list();
      expect(rows, isNotEmpty);
      await expectLater(
        policies().propose(
          DocumentApprovalPolicy(
            farm: 'farm',
            kind: ApprovalKind.materialIssue,
            currency: 'VND',
            version: 2,
            selfEnabled: false,
            createPermission: 'inventory.manage',
            approvePermission: 'finance.approve',
            changedBy: live.userId,
          ),
          'Not authorized to author',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'policy inspection denies a withdrawn activator and account switch',
    () async {
      live = const AuthorizationSubject(
        userId: 'activator',
        membershipId: 'activator',
        farmId: 'farm',
        permissionCodes: {ApprovalRules.policyActivate},
        dataScopes: {DataScope.allFarm},
      );
      final store = policies();
      expect(await store.list(), isNotEmpty);
      live = const AuthorizationSubject(
        userId: 'activator',
        membershipId: 'activator',
        farmId: 'farm',
        permissionCodes: {ApprovalRules.policyActivate},
        dataScopes: {DataScope.own},
      );
      await expectLater(store.list(), throwsStateError);
      live = user('other-account');
      await expectLater(store.list(), throwsStateError);
    },
  );
}
