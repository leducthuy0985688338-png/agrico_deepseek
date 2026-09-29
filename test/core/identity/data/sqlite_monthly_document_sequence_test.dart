import 'package:agrico_deepseek/core/identity/data/sqlite_monthly_document_sequence.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  final allocator = SqliteMonthlyDocumentSequence();

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteMonthlyDocumentSequence.createSchema(database);
    await database.execute('CREATE TABLE documents (code TEXT PRIMARY KEY)');
  });
  tearDown(() async => database.close());

  Future<String> save(String organization, BusinessDocumentKind kind, DateTime date) =>
      database.transaction((tx) => allocator.saveWithCode(
        transaction: tx,
        organizationId: organization,
        kind: kind,
        documentDate: date,
        save: (code) async {
          await tx.insert('documents', {'code': code});
          return code;
        },
      ));

  test('increments within a month and separates type, month and organization', () async {
    expect(await save('farm-a', BusinessDocumentKind.receipt, DateTime(2026, 9)), 'THU-202609-001');
    expect(await save('farm-a', BusinessDocumentKind.receipt, DateTime(2026, 9)), 'THU-202609-002');
    expect(await save('farm-a', BusinessDocumentKind.payment, DateTime(2026, 9)), 'CHI-202609-001');
    expect(await save('farm-a', BusinessDocumentKind.receipt, DateTime(2026, 10)), 'THU-202610-001');
    // Document uniqueness is per organization; test another organization's counter
    // without writing to the deliberately global test table.
    final other = await database.transaction((tx) => allocator.saveWithCode(
      transaction: tx,
      organizationId: 'farm-b',
      kind: BusinessDocumentKind.receipt,
      documentDate: DateTime(2026, 9),
      save: (code) async => code,
    ));
    expect(other, 'THU-202609-001');
  });

  test('failed document write rolls back number allocation', () async {
    await expectLater(database.transaction((tx) => allocator.saveWithCode(
      transaction: tx,
      organizationId: 'farm-a',
      kind: BusinessDocumentKind.stockOut,
      documentDate: DateTime(2026, 9),
      save: (_) async => throw StateError('document rejected'),
    )), throwsStateError);
    expect(await save('farm-a', BusinessDocumentKind.stockOut, DateTime(2026, 9)), 'XUAT-202609-001');
  });

  test('full monthly range fails without wrapping to a duplicate', () async {
    await database.insert(SqliteMonthlyDocumentSequence.table, {
      'organization_id': 'farm-a',
      'kind': 'NHAP',
      'year_month': '202609',
      'last_sequence': 999,
    });
    await expectLater(save('farm-a', BusinessDocumentKind.stockIn, DateTime(2026, 9)), throwsFormatException);
  });
}
