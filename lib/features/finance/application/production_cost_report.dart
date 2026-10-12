import 'package:excel/excel.dart';
import 'production_cost_summary.dart';

class ProductionCostReport {
  const ProductionCostReport(this.summary);
  final ProductionCostSummary summary;

  void _authorize() {
    if (!summary.canView) {
      throw StateError('Production cost report access denied.');
    }
  }

  Future<Excel> workbook() async {
    _authorize();
    final snapshot = await summary.load();
    _authorize();
    final excel = Excel.createExcel();
    final totals = excel['Totals'];
    totals.appendRow([TextCellValue('Currency'), TextCellValue('Payments')]);
    for (final total in snapshot.totals.entries) {
      totals.appendRow([TextCellValue(total.key), IntCellValue(total.value)]);
    }
    final groups = excel['By Parcel'];
    groups.appendRow([
      TextCellValue('Parcel ID'),
      TextCellValue('Parcel'),
      TextCellValue('Currency'),
      TextCellValue('Payments'),
      TextCellValue('Documents'),
    ]);
    final documents = excel['Documents'];
    documents.appendRow([
      TextCellValue('Code'),
      TextCellValue('Date'),
      TextCellValue('Parcel ID'),
      TextCellValue('Parcel'),
      TextCellValue('Currency'),
      TextCellValue('Amount'),
      TextCellValue('Category'),
      TextCellValue('Description'),
    ]);
    for (final group in snapshot.groups) {
      final label = group.parcelId == null
          ? 'General expenses'
          : snapshot.parcelLabels[group.parcelId] ?? 'Linked land parcel';
      groups.appendRow([
        TextCellValue(group.parcelId ?? ''),
        TextCellValue(label),
        TextCellValue(group.currency),
        IntCellValue(group.amountMinor),
        IntCellValue(group.documents.length),
      ]);
      for (final document in group.documents) {
        documents.appendRow([
          TextCellValue(document.code),
          TextCellValue(document.occurredAt.toIso8601String()),
          TextCellValue(document.parcelId ?? ''),
          TextCellValue(label),
          TextCellValue(document.currency),
          IntCellValue(document.amountMinor),
          TextCellValue(document.category),
          TextCellValue(document.description ?? ''),
        ]);
      }
    }
    return excel;
  }

  Future<void> exportReport({
    required Future<void> Function(Excel) save,
  }) async {
    final report = await workbook();
    _authorize();
    await save(report);
  }
}
