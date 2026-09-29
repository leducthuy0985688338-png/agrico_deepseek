import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_v2_report.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('exports scoped v2 documents and separate currency totals', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await SqliteFinanceDocumentRepository.createSchema(db);
      final store = SqliteFinanceDocumentRepository(db);
      Future<void> add(
        String id,
        String organization,
        String currency,
        BusinessDocumentKind kind,
        int amount,
      ) async {
        await store.create(
          id: id,
          organizationId: organization,
          kind: kind,
          occurredAt: DateTime.utc(2026, 9, 29),
          amountMinor: amount,
          currency: currency,
          category: 'ຄ່າແຮງງານ',
        );
      }

      await add('r1', 'agrico', 'LAK', BusinessDocumentKind.receipt, 12000);
      await add('p1', 'agrico', 'LAK', BusinessDocumentKind.payment, 2000);
      await add('p2', 'agrico', 'VND', BusinessDocumentKind.payment, 3000);
      await add('other', 'other', 'LAK', BusinessDocumentKind.receipt, 999999);

      final workbook = await FinanceV2Report(store).workbook('agrico');
      expect(workbook['Finance V2'].rows, hasLength(4));
      expect(workbook['Totals V2'].rows, hasLength(3));
      final totals = workbook['Totals V2'].rows;
      expect((totals[1][1]!.value as IntCellValue).value, 12000);
      expect((totals[1][2]!.value as IntCellValue).value, 2000);
      expect((totals[1][3]!.value as IntCellValue).value, 10000);
      expect((totals[2][3]!.value as IntCellValue).value, -3000);
      expect(workbook.save(), isNotEmpty);
    } finally {
      await db.close();
    }
  });
}
