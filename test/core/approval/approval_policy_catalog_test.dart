import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/approval_policy_catalog.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';

DocumentApprovalPolicy proposal({String limit = '100'}) =>
    DocumentApprovalPolicy(
      farm: 'f',
      kind: ApprovalKind.machineRun,
      currency: 'VND',
      version: 1,
      selfEnabled: false,
      createPermission: 'machine.log',
      approvePermission: 'machine.verify',
      changedBy: 'author',
      independentLimit: limit,
    );
AuthorizationSubject subject(String uid) => AuthorizationSubject(
  userId: uid,
  membershipId: uid,
  farmId: 'f',
  permissionCodes: PermissionCodes.values,
  dataScopes: const {DataScope.allFarm},
);

class Server
    implements
        ApprovalAuthority,
        ApprovalDraftAuthority,
        ApprovalPolicyCatalogAuthority {
  Map<String, dynamic>? draft, activated;
  bool offline = false, revoked = false, tamper = false;
  Future<void> Function()? beforeReply;
  @override
  Future<void> publishDraft(
    AuthorizationSubject actor,
    DocumentApprovalPolicy p,
    String digest,
  ) async {
    if (offline) throw const SocketException('offline');
    draft = {
      'policy': p.toJson(),
      'digest': digest,
      'version': p.version,
      'authorityRevision': 1,
      'proposedBy': actor.userId,
      'proposedAt': '2026-11-01T00:00:00Z',
    };
  }

  @override
  Future<ApprovalPolicyCatalog> catalog(
    AuthorizationSubject actor,
    ApprovalKind kind,
    String currency,
  ) async {
    if (offline) throw const SocketException('offline');
    if (revoked) throw StateError('revoked');
    await beforeReply?.call();
    final d = draft == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(draft)) as Map);
    if (tamper) d!['proposedBy'] = 'forged';
    return ApprovalPolicyCatalog(
      {
        'farm': 'f',
        'kind': kind.name,
        'currency': currency,
        'authorityRevision': 1,
        'head': d == null
            ? null
            : {'version': d['version'], 'digest': d['digest']},
        'expectedActive': activated == null
            ? null
            : {
                'version': activated!['version'],
                'digest': activated!['digest'],
              },
        'drafts': activated == null && d != null ? [d] : [],
        'active': activated,
      },
      'f',
      kind,
      currency,
    );
  }

  @override
  Future<String?> activateCatalog(
    AuthorizationSubject actor,
    DocumentApprovalPolicy p,
    String digest,
    int expectedLocalActive,
  ) async {
    if (offline ||
        revoked ||
        actor.userId == p.changedBy ||
        activated != null ||
        draft?['digest'] != digest ||
        expectedLocalActive != 0) {
      throw StateError('CAS denied');
    }
    final ref = jsonEncode({
      'activatedAt': '2026-11-01T00:01:00Z',
      'digest': digest,
    });
    activated = {
      ...draft!,
      'activatedBy': actor.userId,
      'activatedAt': '2026-11-01T00:01:00Z',
      'reference': ref,
    };
    return ref;
  }

  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy p,
    String digest,
  ) => activateCatalog(actor, p, digest, 0);
  @override
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy p,
    String digest,
  ) async =>
      !offline &&
      !revoked &&
      activated?['digest'] == digest &&
      activated?['reference'] == p.authorityReference;
}

void main() {
  for (final change in ['scope', 'missingKey', 'head', 'revision']) {
    test('catalog rejects malformed authenticated envelope $change', () {
      final p = proposal(), digest = PeriodLock.digest(proposal().toJson());
      final payload = Map<String, Object?>.from(p.toJson());
      final record = <String, dynamic>{
        'policy': payload,
        'digest': digest,
        'version': 1,
        'authorityRevision': 1,
        'proposedBy': 'author',
        'proposedAt': '2026-11-01T00:00:00Z',
      };
      final data = <String, dynamic>{
        'farm': 'f',
        'kind': 'machineRun',
        'currency': 'VND',
        'authorityRevision': 1,
        'head': {'version': 1, 'digest': digest},
        'expectedActive': null,
        'drafts': [record],
        'active': null,
      };
      if (change == 'scope') data['farm'] = 'other';
      if (change == 'missingKey') payload.remove('selfLimit');
      if (change == 'head') data['head'] = {'version': 2, 'digest': digest};
      if (change == 'revision') record['authorityRevision'] = 2;
      expect(
        () => ApprovalPolicyCatalog(data, 'f', ApprovalKind.machineRun, 'VND'),
        throwsFormatException,
      );
    });
  }

  sqfliteFfiInit();
  Future<Database> database() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await SqliteApprovalPolicyStore.createSchema(db);
    return db;
  }

  test(
    'two independent SQLite clients preserve server author, activate and import active proof',
    () async {
      final a = await database(), b = await database();
      addTearDown(a.close);
      addTearDown(b.close);
      final server = Server();
      final author = subject('author'), reviewer = subject('reviewer');
      final first = SqliteApprovalPolicyStore(
        a,
        opened: author,
        currentSubject: () => author,
        authority: server,
      );
      final second = SqliteApprovalPolicyStore(
        b,
        opened: reviewer,
        currentSubject: () => reviewer,
        authority: server,
      );
      await first.propose(proposal(), 'New draft');
      await first.publishDraft(ApprovalKind.machineRun, 'VND', 1);
      expect(await b.query(SqliteApprovalPolicyStore.policies), isEmpty);
      await second.syncPolicy(ApprovalKind.machineRun, 'VND');
      final imported = (await second.list()).single;
      expect(imported['changed_by'], 'author');
      expect(imported['changed_at'], '2026-11-01T00:00:00Z');
      expect(imported['digest'], PeriodLock.digest(proposal().toJson()));
      await second.activate(
        ApprovalKind.machineRun,
        'VND',
        1,
        0,
        'Independent review',
      );
      await first.syncPolicy(ApprovalKind.machineRun, 'VND');
      expect((await first.list()).single['activated_by'], 'reviewer');
      expect(
        await first.effective(a, 'f', ApprovalKind.machineRun, 'VND'),
        isNotNull,
      );
      expect(
        (await b.query(
          SqliteApprovalPolicyStore.audit,
        )).where((r) => r['action'] == 'remoteImport').length,
        1,
      );
      await expectLater(
        second.activate(ApprovalKind.machineRun, 'VND', 1, 1, 'Replay'),
        throwsStateError,
      );
    },
  );
  test(
    'offline and revocation fail closed without deleting an existing draft or granting posting',
    () async {
      final db = await database();
      addTearDown(db.close);
      final server = Server(), actor = subject('author');
      final store = SqliteApprovalPolicyStore(
        db,
        opened: actor,
        currentSubject: () => actor,
        authority: server,
      );
      await store.propose(proposal(), 'Draft');
      await store.publishDraft(ApprovalKind.machineRun, 'VND', 1);
      server.offline = true;
      await expectLater(
        store.syncPolicy(ApprovalKind.machineRun, 'VND'),
        throwsA(isA<SocketException>()),
      );
      await expectLater(store.list(), throwsA(isA<SocketException>()));
      expect(
        (await db.query(SqliteApprovalPolicyStore.policies)).single['state'],
        'draft',
      );
      expect(
        await store.effective(db, 'f', ApprovalKind.machineRun, 'VND'),
        isNull,
      );
      server.offline = false;
      server.revoked = true;
      await expectLater(store.list(), throwsStateError);
    },
  );
  test(
    'account change during response imports no old account metadata',
    () async {
      final db = await database();
      addTearDown(db.close);
      final server = Server();
      await server.publishDraft(
        subject('author'),
        proposal(),
        PeriodLock.digest(proposal().toJson()),
      );
      AuthorizationSubject? current = subject('reviewer');
      final store = SqliteApprovalPolicyStore(
        db,
        opened: current,
        currentSubject: () => current,
        authority: server,
      );
      server.beforeReply = () async {
        current = subject('other');
      };
      await expectLater(
        store.syncPolicy(ApprovalKind.machineRun, 'VND'),
        throwsStateError,
      );
      expect(await db.query(SqliteApprovalPolicyStore.policies), isEmpty);
      current = null;
      await expectLater(store.list(), throwsStateError);
    },
  );
  test(
    'tampered provenance and same-version conflicts never overwrite local draft',
    () async {
      final db = await database();
      addTearDown(db.close);
      final server = Server(), actor = subject('author');
      final store = SqliteApprovalPolicyStore(
        db,
        opened: actor,
        currentSubject: () => actor,
        authority: server,
      );
      await store.propose(proposal(), 'Local');
      await server.publishDraft(
        actor,
        proposal(limit: '999'),
        PeriodLock.digest(proposal(limit: '999').toJson()),
      );
      await expectLater(
        store.syncPolicy(ApprovalKind.machineRun, 'VND'),
        throwsStateError,
      );
      expect(
        (await db.query(SqliteApprovalPolicyStore.policies)).single['digest'],
        PeriodLock.digest(proposal().toJson()),
      );
      server.tamper = true;
      await expectLater(
        store.syncPolicy(ApprovalKind.machineRun, 'VND'),
        throwsFormatException,
      );
    },
  );
}
