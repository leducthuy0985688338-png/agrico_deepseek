import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import '../../../../support/approval_b_test_support.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/transaction_database.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SyntheticApprovalAuthority authority;
  late SqliteFinanceDocumentRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteFinanceDocumentRepository.createSchema(db);
    await PeriodLock.createSchema(db);
    await SqliteDocumentApproval.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await NativeApprovalGuard.install(db);
    authority = SyntheticApprovalAuthority();
    for (final farm in ['farm-a', 'farm-b']) {
      final party = 'party-$farm';
      authority.partyUsers[party] = {};
      await db.insert('company_catalog_entries_v1', {
        'id': party,
        'farm_id': farm,
        'kind': 'supplier',
        'code': party,
        'name': party,
        'name_key': party,
        'active': 1,
        'revision': 1,
      });
      for (final kind in [ApprovalKind.cashPayment, ApprovalKind.cashReceipt]) {
        await syntheticPolicy(db, authority, kind, 'LAK', farm: farm);
      }
    }
    repository = SqliteFinanceDocumentRepository(db);
  });
  tearDown(() async => db.close());

  Future<FinanceDocument> post({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? description,
  }) async {
    final maker = approvalUser('maker', farm: organizationId);
    final reviewer = approvalUser('reviewer', farm: organizationId);
    NativeApprovalRepository workflow(AuthorizationSubject actor) => NativeApprovalRepository(
      SqliteApprovalPolicyStore(
        db,
        opened: actor,
        currentSubject: () => actor,
        authority: authority,
      ),
    );
    final ref = NativeApprovalRef(NativeApprovalType.finance, id);
    await repository.createPendingFinance(
      creator: maker,
      currentSubject: () => maker,
      id: id,
      organizationId: organizationId,
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      description: description,
      beneficiaryPartyId: 'party-$organizationId',
    );
    if ((await repository.listByOrganization(organizationId))
        .every((document) => document.id != id)) {
      await workflow(maker).submit(ref);
    }
    final decision = await workflow(reviewer).approve(ref, 'Independent review');
    expect(decision.allowed, isTrue);
    return (await repository.listByOrganization(organizationId))
        .singleWhere((document) => document.id == id);
  }

  test('denied posting in a borrowed transaction does not reserve a number', () async {
    await db.transaction((tx) async {
      final bound = SqliteFinanceDocumentRepository(TransactionDatabase(tx));
      await expectLater(
        bound.create(
          id: 'denied',
          organizationId: 'farm-a',
          kind: BusinessDocumentKind.receipt,
          occurredAt: DateTime.utc(2026, 9, 25),
          amountMinor: 100,
          currency: 'LAK',
          category: 'Sale',
        ),
        throwsStateError,
      );
    });
    expect(await db.query('monthly_document_sequences'), isEmpty);
    expect(await repository.listByOrganization('farm-a'), isEmpty);
  });

  test('actor and document IDs alone cannot issue a native lease', () async {
    await db.transaction((tx) async {
      expect(
        () => Function.apply(NativeApprovalGuard.authorized<void>, [tx], {
          #farm: 'farm-a',
          #actor: 'reviewer',
          #writes: <String>{},
          #financeIds: {'forged'},
          #apply: () async {},
        }),
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(await tx.query(NativeApprovalGuard.lease), isEmpty);
    });
  });

  test('a persisted lease alone cannot authorize a direct write', () async {
    await db.insert(NativeApprovalGuard.lease, {
      'singleton': 1,
      'farm_id': 'farm-a',
      'actor_id': 'forged',
      'writes_json': '[]',
      'finance_json': '["forged"]',
    });
    await expectLater(repository.create(
      id: 'forged', organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    ), throwsStateError);
    expect(await repository.listByOrganization('farm-a'), isEmpty);
  });

  test('persists Unicode receipt/payment with separate monthly codes and scope', () async {
    final receipt = await post(
      id: 'finance-1', organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 20000, currency: 'LAK', category: 'ຂາຍມັນຕົ້ນ',
      description: 'ບ້ານຕາໂກ',
    );
    expect(receipt.code, 'THU-202609-001');
    expect((await post(
      id: 'finance-2', organizationId: 'farm-a',
      kind: BusinessDocumentKind.payment, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 500, currency: 'LAK', category: 'Lương',
    )).code, 'CHI-202609-001');
    expect((await post(
      id: 'finance-3', organizationId: 'farm-b',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    )).code, 'THU-202609-001');
    final saved = await repository.listByOrganization('farm-a');
    expect(saved.map((value) => value.id), containsAll(['finance-1', 'finance-2']));
    expect(saved.firstWhere((value) => value.id == 'finance-1').description, 'ບ້ານຕາໂກ');
    expect(saved.length, 2);
  });

  test('rejects missing or replaced finance guards without consuming a code', () async {
    const trigger = 'period_guard_finance_documents_v2_insert';
    Future<FinanceDocument> create() => post(
      id: 'guard-test',
      organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt,
      occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100,
      currency: 'LAK',
      category: 'Sale',
    );

    await db.execute('DROP TRIGGER $trigger');
    await expectLater(create(), throwsStateError);
    await db.execute(
      'CREATE TRIGGER $trigger BEFORE INSERT ON finance_documents_v2 '
      'BEGIN SELECT 1; END',
    );
    await expectLater(create(), throwsStateError);
    expect(await repository.listByOrganization('farm-a'), isEmpty);

    await db.execute('DROP TRIGGER $trigger');
    await PeriodLock.install(db);
    expect((await create()).code, 'THU-202609-001');
  });

  test('rejects a replaced period state table with the same columns', () async {
    await db.execute('DROP TABLE ${PeriodLock.states}');
    await db.execute(
      'CREATE TABLE ${PeriodLock.states}(farm_id, period, revision, status, event_id)',
    );
    await expectLater(
      post(
        id: 'replaced-state',
        organizationId: 'farm-a',
        kind: BusinessDocumentKind.receipt,
        occurredAt: DateTime.utc(2026, 9, 25),
        amountMinor: 100,
        currency: 'LAK',
        category: 'Sale',
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Finance period state table failed verification.',
      )),
    );
    expect(await repository.listByOrganization('farm-a'), isEmpty);
  });

  test('failed Finance insert rolls back sequence and approval', () async {
    Future<String> create(String id) async => (await post(
      id: id, organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    )).code;
    expect(await create('finance-1'), 'THU-202609-001');
    await db.execute(
      "CREATE TRIGGER fail_test_post BEFORE INSERT ON finance_documents_v2 "
      "WHEN NEW.id='rejected-post' BEGIN SELECT RAISE(ABORT,'test insert failure'); END",
    );
    await expectLater(create('rejected-post'), throwsA(isA<DatabaseException>()));
    expect(await repository.listByOrganization('farm-a'), hasLength(1));
    expect(await create('finance-2'), 'THU-202609-002');
  });
}
