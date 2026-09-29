import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_summary.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'summarizes only persisted v2 documents per organization and currency',
    () async {
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
            category: 'ບ້ານຕາໂກ',
          );
        }

        await add('r1', 'agrico', 'LAK', BusinessDocumentKind.receipt, 20000);
        await add('r2', 'agrico', 'LAK', BusinessDocumentKind.receipt, 3000);
        await add('p1', 'agrico', 'LAK', BusinessDocumentKind.payment, 500);
        await add('p2', 'agrico', 'VND', BusinessDocumentKind.payment, 7000);
        await add(
          'other',
          'other',
          'LAK',
          BusinessDocumentKind.receipt,
          900000,
        );

        final totals = await FinanceDocumentSummary(
          store,
        ).byOrganization('agrico');
        expect(totals.map((total) => total.currency), ['LAK', 'VND']);
        expect(totals[0].receiptsMinor, 23000);
        expect(totals[0].paymentsMinor, 500);
        expect(totals[0].balanceMinor, 22500);
        expect(totals[1].receiptsMinor, 0);
        expect(totals[1].balanceMinor, -7000);
        expect(
          await FinanceDocumentSummary(store).byOrganization('empty'),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
}
