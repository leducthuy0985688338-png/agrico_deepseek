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
    repository = SqliteFinanceDocumentRepository(db);
  });
  tearDown(() async => db.close());

  test('persists Unicode receipt/payment with separate monthly codes and scope', () async {
    final receipt = await repository.create(
      id: 'finance-1', organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 20000, currency: 'LAK', category: 'ຂາຍມັນຕົ້ນ',
      description: 'ບ້ານຕາໂກ',
    );
    expect(receipt.code, 'THU-202609-001');
    expect((await repository.create(
      id: 'finance-2', organizationId: 'farm-a',
      kind: BusinessDocumentKind.payment, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 500, currency: 'LAK', category: 'Lương',
    )).code, 'CHI-202609-001');
    expect((await repository.create(
      id: 'finance-3', organizationId: 'farm-b',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    )).code, 'THU-202609-001');
    final saved = await repository.listByOrganization('farm-a');
    expect(saved.map((value) => value.id), containsAll(['finance-1', 'finance-2']));
    expect(saved.firstWhere((value) => value.id == 'finance-1').description, 'ບ້ານຕາໂກ');
    expect(saved.length, 2);
  });

  test('duplicate document ID rolls back sequence', () async {
    Future<String> create(String id) async => (await repository.create(
      id: id, organizationId: 'farm-a',
      kind: BusinessDocumentKind.receipt, occurredAt: DateTime.utc(2026, 9, 25),
      amountMinor: 100, currency: 'LAK', category: 'Sale',
    )).code;
    expect(await create('finance-1'), 'THU-202609-001');
    await expectLater(create('finance-1'), throwsA(isA<DatabaseException>()));
    expect(await create('finance-2'), 'THU-202609-002');
  });
}
