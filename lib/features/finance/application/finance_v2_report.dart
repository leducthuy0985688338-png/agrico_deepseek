import 'package:excel/excel.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';

import '../domain/finance_document.dart';
import 'finance_document_summary.dart';

/// A report of persisted documents only. Amounts remain integers and each
/// currency has its own subtotal; no exchange rate is assumed.
class FinanceV2Report {
  const FinanceV2Report(this.store);

  final FinanceDocumentStore store;

  Future<Excel> workbook(String organizationId) async {
    if (organizationId.trim().isEmpty) {
      throw const FormatException('Organization is required.');
    }
    final documents = await store.listByOrganization(organizationId);
    final totals = await FinanceDocumentSummary(
      store,
    ).byOrganization(organizationId);
    final excel = Excel.createExcel();
    final sheet = excel['Finance V2'];
    sheet.appendRow([
      TextCellValue('Code'),
      TextCellValue('Date'),
      TextCellValue('Kind'),
      TextCellValue('Currency'),
      TextCellValue('Amount'),
      TextCellValue('Category'),
      TextCellValue('Parcel ID'),
      TextCellValue('Description'),
    ]);
    for (final document in documents) {
      if (document.organizationId != organizationId) {
        throw StateError('Finance document is outside the organization.');
      }
      sheet.appendRow([
        TextCellValue(document.code),
        TextCellValue(document.occurredAt.toIso8601String()),
        TextCellValue(document.kind.prefix),
        TextCellValue(document.currency),
        IntCellValue(document.amountMinor),
        TextCellValue(document.category),
        TextCellValue(document.parcelId ?? ''),
        TextCellValue(document.description ?? ''),
      ]);
    }
    final subtotal = excel['Totals V2'];
    subtotal.appendRow([
      TextCellValue('Currency'),
      TextCellValue('Receipts'),
      TextCellValue('Payments'),
      TextCellValue('Balance'),
    ]);
    for (final total in totals) {
      subtotal.appendRow([
        TextCellValue(total.currency),
        IntCellValue(total.receiptsMinor),
        IntCellValue(total.paymentsMinor),
        IntCellValue(total.balanceMinor),
      ]);
    }
    return excel;
  }
}
