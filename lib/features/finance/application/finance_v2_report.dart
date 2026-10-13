import 'finance_document_filter.dart';
import 'package:excel/excel.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';

import '../domain/finance_document.dart';
import 'finance_document_summary.dart';

/// A report of persisted documents only. Amounts remain integers and each
/// currency has its own subtotal; no exchange rate is assumed.
class FinanceV2Report {
  const FinanceV2Report(this.store);

  final FinanceDocumentStore store;

  Future<Excel> workbook(
    String organizationId, {
    FinanceDocumentFilter filter = const FinanceDocumentFilter(),
  }) async {
    filter.validate();
    if (organizationId.trim().isEmpty) {
      throw const FormatException('Organization is required.');
    }
    final allDocuments = await store.listByOrganization(organizationId);
    // Validate all scoped rows before filtering so invalid rows cannot be hidden.
    FinanceDocumentSummary.fromDocuments(allDocuments, organizationId);
    final documents = allDocuments.where(filter.matches).toList();
    final totals = FinanceDocumentSummary.fromDocuments(
      documents,
      organizationId,
    );
    final excel = Excel.createExcel();
    final scope = excel['Filter V2'];
    scope.appendRow([TextCellValue('Field'), TextCellValue('Value')]);
    for (final entry in <String, String>{
      'Currency': filter.currency ?? 'All',
      'Query': filter.query.trim(),
      'Kind': filter.kind?.prefix ?? 'All',
      'From': filter.from?.toIso8601String().substring(0, 10) ?? 'All dates',
      'To': filter.to?.toIso8601String().substring(0, 10) ?? 'All dates',
      'Parcel mode': filter.parcel.startsWith('parcel:')
          ? 'Parcel'
          : filter.parcel,
      'Parcel ID': filter.parcel.startsWith('parcel:')
          ? filter.parcel.substring(7)
          : '',
    }.entries) {
      scope.appendRow([TextCellValue(entry.key), TextCellValue(entry.value)]);
    }
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
