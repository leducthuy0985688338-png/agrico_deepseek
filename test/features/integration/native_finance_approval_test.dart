import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import 'package:agrico_deepseek/features/integration/data/integration_cash.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import '../../support/approval_b_test_support.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late AuthorizationSubject live;
  late SyntheticApprovalAuthority authority;
  NativeApprovalRepository workflow() => NativeApprovalRepository(
    SqliteApprovalPolicyStore(
      db,
      opened: live,
      currentSubject: () => live,
      authority: authority,
    ),
  );
  FinanceDocumentService finance() => FinanceDocumentService(
    repository: SqliteFinanceDocumentRepository(db),
    subject: live,
    currentSubject: () => live,
  );
  const ref = NativeApprovalRef(NativeApprovalType.finance, 'cash-1');
  Future<void> create({String currency = 'VND', int amount = 800000}) async {
    await finance().create(
      id: ref.id,
      organizationId: 'f',
      kind: BusinessDocumentKind.payment,
      occurredAt: DateTime(2026, 10, 20),
      amountMinor: amount,
      currency: currency,
      category: 'SYNTHETIC',
      beneficiaryPartyId: 'test-supplier',
      description: 'Native fixture',
    );
  }

  Future<void> prepare() async {
    live = approvalUser('maker');
    await create();
    await workflow().submit(ref);
    live = approvalUser('reviewer');
  }

  Future<int> ledgerCount() async =>
      (await db.query(SqliteFinanceDocumentRepository.table)).length;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    live = approvalUser('maker');
    authority = SyntheticApprovalAuthority();
    authority.partyUsers['test-supplier'] = {};
    await SqliteCompanyCatalog.createSchema(db);
    await db.insert('company_catalog_entries_v1', {
      'id': 'test-supplier',
      'farm_id': 'f',
      'kind': 'supplier',
      'code': 'NCC-TEST',
      'name': 'Synthetic external payee',
      'name_key': 'synthetic external payee',
      'active': 1,
      'revision': 1,
    });
    await SqliteFinanceDocumentRepository.createSchema(db);
    await SqliteDocumentApproval.createSchema(db);
    await PeriodLock.createSchema(db);
    await NativeApprovalGuard.install(db);
    for (final c in ['VND', 'LAK'])
      await syntheticPolicy(db, authority, ApprovalKind.cashPayment, c);
  });
  tearDown(() async => db.close());
  test(
    'actual FinanceDocumentService persists pending with real creator and no ledger before review',
    () async {
      await create();
      expect(await ledgerCount(), 0);
      final pending = (await db.query(NativeApprovalGuard.pending)).single;
      expect(pending['creator'], 'maker');
      expect(pending['revision'], 1);
      expect((pending['digest'] as String).length, 64);
      expect(
        (await workflow().list({
          NativeApprovalType.finance,
        })).single.source.total,
        '800000',
      );
    },
  );
  test(
    'cash creator including technical admin cannot approve own financial document',
    () async {
      await create();
      await workflow().submit(ref);
      final d = await workflow().approve(ref, 'Explicit self attempt');
      expect(d.allowed, isFalse);
      expect(d.reason, 'independentApprovalRequired');
      expect(await ledgerCount(), 0);
    },
  );
  test(
    'native independent approval posts atomically with source state audit and exact money',
    () async {
      await prepare();
      expect(
        (await workflow().approve(
          ref,
          'Invoice independently verified',
        )).allowed,
        isTrue,
      );
      expect(await ledgerCount(), 1);
      final row = (await db.query(
        SqliteFinanceDocumentRepository.table,
      )).single;
      expect(row['amount_minor'], 800000);
      expect(row['currency'], 'VND');
      expect(
        (await db.query(NativeApprovalGuard.pending)).single['status'],
        'approved',
      );
      expect(
        (await db.query(SqliteDocumentApproval.requests)).single['decided_by'],
        'reviewer',
      );
      expect(await db.query(NativeApprovalGuard.lease), isEmpty);
      await SqliteDocumentApproval.validate(db);
    },
  );
  test('reject has a reason and never inserts ledger', () async {
    await prepare();
    await workflow().reject(ref, 'Source evidence rejected');
    expect(await ledgerCount(), 0);
    expect(
      (await db.query(SqliteDocumentApproval.requests)).single['state'],
      'rejected',
    );
    expect(
      (await db.query(NativeApprovalGuard.pending)).single['status'],
      'rejected',
    );
    await expectLater(
      workflow().approve(ref, 'Retry rejection'),
      throwsStateError,
    );
  });
  test(
    'retry and concurrent native approvals create one ledger record',
    () async {
      await prepare();
      final results = await Future.wait([
        workflow().approve(ref, 'Reviewed once'),
        workflow().approve(ref, 'Retry same source'),
      ]);
      expect(results.every((r) => r.allowed), isTrue);
      expect(await ledgerCount(), 1);
      expect(
        (await db.query(
          SqliteDocumentApproval.audit,
        )).where((r) => r['action'] == 'independentApproval'),
        hasLength(1),
      );
    },
  );
  test(
    'raw Finance repository and both direct cash writers cannot bypass application guards',
    () async {
      await expectLater(
        SqliteFinanceDocumentRepository(db).create(
          id: 'bypass',
          organizationId: 'f',
          kind: BusinessDocumentKind.payment,
          occurredAt: DateTime(2026, 10, 20),
          amountMinor: 1,
          currency: 'VND',
          category: 'BYPASS',
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.transaction(
          (tx) => IntegrationCash.write(
            tx,
            id: 'bypass-2',
            farm: 'f',
            day: '2026-10-20',
            amountText: '1',
            currency: 'VND',
            category: 'BYPASS',
            note: 'Direct helper',
            receipt: false,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.transaction(
          (tx) => SqliteTradeRepository.cash(
            tx,
            id: 'bypass-3',
            farm: 'f',
            receipt: false,
            amount: '1',
            currency: 'VND',
            day: '2026-10-20',
            description: 'Direct trade helper',
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await ledgerCount(), 0);
    },
  );
  test(
    'policy change resubmits same business source without inventing source revision or ledger',
    () async {
      await prepare();
      await syntheticPolicy(
        db,
        authority,
        ApprovalKind.cashPayment,
        'VND',
        version: 2,
      );
      await expectLater(
        workflow().approve(ref, 'Stale request'),
        throwsStateError,
      );
      live = approvalUser('maker');
      await workflow().submit(ref);
      live = approvalUser('reviewer');
      expect(
        (await workflow().approve(
          ref,
          'Explicit review under policy 2',
        )).allowed,
        isTrue,
      );
      expect((await db.query(NativeApprovalGuard.pending)), hasLength(1));
      final attempts = await db.query(
        SqliteDocumentApproval.requests,
        orderBy: 'policy_version',
      );
      expect(attempts.map((r) => r['source_revision']), [1, 1]);
      expect(attempts.map((r) => r['policy_version']), [1, 2]);
      expect(await ledgerCount(), 1);
    },
  );
  test('closed period denies late offline approval without posting', () async {
    await prepare();
    await db.insert(PeriodLock.states, {
      'farm_id': 'f',
      'period': '2026-10',
      'revision': 1,
      'status': 'closed',
      'event_id': 'synthetic-lock',
    });
    expect(
      (await workflow().approve(ref, 'Offline delivery after close')).reason,
      'periodClosed',
    );
    expect(await ledgerCount(), 0);
  });
  test(
    'VND and LAK stay separate and exact large integer is not converted through double',
    () async {
      await create(currency: 'LAK', amount: 9007199254740991);
      await workflow().submit(ref);
      live = approvalUser('reviewer');
      expect(
        (await workflow().approve(ref, 'Exact LAK reviewed')).allowed,
        isTrue,
      );
      final posted = (await SqliteFinanceDocumentRepository(
        db,
      ).listByOrganization('f')).single;
      expect(posted.amountText, '9007199254740991');
      expect(posted.currency, 'LAK');
    },
  );
  test(
    'revocation during server-authority recheck rolls back native transaction',
    () async {
      await prepare();
      var calls = 0;
      authority.onVerify = () {
        calls++;
        if (calls == 2) live = approvalUser('reviewer', active: false);
      };
      await expectLater(
        workflow().approve(ref, 'Permission revoked while awaiting authority'),
        throwsStateError,
      );
      expect(await ledgerCount(), 0);
      expect(await db.query(NativeApprovalGuard.lease), isEmpty);
    },
  );
  test('cross farm subject cannot approve another farms source', () async {
    await prepare();
    live = approvalUser('reviewer', farm: 'other');
    await expectLater(workflow().approve(ref, 'Cross farm'), throwsStateError);
    expect(await ledgerCount(), 0);
  });
  test(
    'withdrawing authority before approval denies and leaves pending retry intact',
    () async {
      await prepare();
      authority.current = false;
      await expectLater(
        workflow().approve(ref, 'Withdrawn authority'),
        throwsStateError,
      );
      expect(await ledgerCount(), 0);
      authority.current = true;
      expect(
        (await workflow().approve(
          ref,
          'Authority independently restored',
        )).allowed,
        isTrue,
      );
    },
  );
  test(
    'native payee binding blocks a beneficiary reviewer and permits a different reviewer',
    () async {
      await prepare();
      authority.partyUsers['test-supplier'] = {'reviewer'};
      expect(
        (await workflow().approve(
          ref,
          'Reviewer is the actual beneficiary',
        )).reason,
        'conflictOfInterest',
      );
      expect(await ledgerCount(), 0);
      live = approvalUser('third-party-reviewer');
      expect(
        (await workflow().approve(
          ref,
          'Independent from maker and beneficiary',
        )).allowed,
        isTrue,
      );
    },
  );
  test(
    'unresolved native payee binding fails closed instead of assuming no conflict',
    () async {
      await create();
      authority.partyUsers.clear();
      await expectLater(workflow().submit(ref), throwsStateError);
      expect(await ledgerCount(), 0);
    },
  );
  test(
    'finance reversal requires independent B, preserves original and retries exactly once',
    () async {
      await prepare();
      expect(
        (await workflow().approve(
          ref,
          'Original independently approved',
        )).allowed,
        isTrue,
      );
      await syntheticPolicy(db, authority, ApprovalKind.correction, 'VND');
      live = approvalUser('maker');
      await workflow().proposeCommand(
        id: 'reverse-1',
        operation: 'financeReverse',
        target: ref,
        payload: {'day': '2026-10-22', 'reason': 'Synthetic correction'},
      );
      const reversal = NativeApprovalRef(
        NativeApprovalType.command,
        'reverse-1',
      );
      await workflow().submit(reversal);
      expect(
        (await workflow().approve(reversal, 'Self correction denied')).allowed,
        isFalse,
      );
      expect(await ledgerCount(), 1);
      live = approvalUser('reviewer');
      expect(
        (await workflow().approve(reversal, 'Independent correction')).allowed,
        isTrue,
      );
      expect(
        (await workflow().approve(reversal, 'Retry same operation')).allowed,
        isTrue,
      );
      expect(await ledgerCount(), 2);
      final rows = await db.query(SqliteFinanceDocumentRepository.table);
      expect(rows.singleWhere((r) => r['id'] == ref.id)['kind'], 'CHI');
      final corrected = rows.singleWhere(
        (r) => r['id'] == 'finance-reversal:reverse-1',
      );
      expect(corrected['kind'], 'THU');
      expect(corrected['amount_minor'], 800000);
      expect(corrected['currency'], 'VND');
      expect((await db.query(NativeApprovalGuard.reversals)).length, 1);
      await NativeApprovalGuard.validate(db);
      await SqliteDocumentApproval.validate(db);
      await NativeApprovalGuard.removeForRestore(db);
      await db.update(
        SqliteFinanceDocumentRepository.table,
        {'amount_minor': 1},
        where: 'id=?',
        whereArgs: ['finance-reversal:reverse-1'],
      );
      await expectLater(NativeApprovalGuard.validate(db), throwsStateError);
    },
  );
  test('partial finance reversal is rejected without new ledger', () async {
    await prepare();
    await workflow().approve(ref, 'Original reviewed');
    live = approvalUser('maker');
    await expectLater(
      workflow().proposeCommand(
        id: 'partial',
        operation: 'financeReverse',
        target: ref,
        payload: {
          'day': '2026-10-22',
          'reason': 'Partial attempt',
          'amount': '1',
        },
      ),
      throwsFormatException,
    );
    expect(await ledgerCount(), 1);
    expect(await db.query(NativeApprovalGuard.commands), isEmpty);
  });
  test('unknown outcome replay cannot reuse a withdrawn authority', () async {
    await prepare();
    await workflow().approve(ref, 'Original approved');
    authority.current = false;
    await expectLater(
      workflow().approve(ref, 'Replay after revocation'),
      throwsStateError,
    );
    expect(await ledgerCount(), 1);
    authority.current = true;
    expect(
      (await workflow().approve(
        ref,
        'Authority restored for verification',
      )).allowed,
      isTrue,
    );
    expect(await ledgerCount(), 1);
  });
}
