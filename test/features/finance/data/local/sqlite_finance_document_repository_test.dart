import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/transaction_database.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteFinanceDocumentRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteFinanceDocumentRepository.createSchema(db);
    await PeriodLock.createSchema(db);
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
  }) => db.transaction((tx) => NativeApprovalGuard.authorized(
    tx,
    farm: organizationId,
    actor: 'reviewer',
    writes: const {},
    financeIds: {id},
    apply: () => SqliteFinanceDocumentRepository(TransactionDatabase(tx)).create(
      id: id,
      organizationId: organizationId,
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      description: description,
    ),
  ));

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

  test('duplicate document ID rolls back sequence', () async {
    Future<String> create(String id) async => (await post(
      id: id, organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    )).code;
    expect(await create('finance-1'), 'THU-202609-001');
    await expectLater(create('finance-1'), throwsA(isA<DatabaseException>()));
    expect(await create('finance-2'), 'THU-202609-002');
  });
}
