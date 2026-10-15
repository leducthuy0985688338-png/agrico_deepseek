import 'production_cost_parcel_filter.dart';
import 'production_cost_period.dart';
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

  Future<Excel> workbook({
    String? currency,
    ProductionCostPeriod period = const ProductionCostPeriod(),
    ProductionCostParcelFilter parcelFilter =
        const ProductionCostParcelFilter.all(),
  }) async {
    _authorize();
    final snapshot = await summary.load(
      period: period,
      parcelFilter: parcelFilter,
      currency: currency,
    );
    _authorize();
    final excel = Excel.createExcel();
    final currencySheet = excel['Currency Filter'];
    currencySheet.appendRow([TextCellValue('Currency')]);
    currencySheet.appendRow([TextCellValue(currency ?? 'All')]);
    final scope = excel['Period'];
    scope.appendRow([TextCellValue('From date'), TextCellValue('To date')]);
    scope.appendRow([
      TextCellValue(
        period.from?.toIso8601String().substring(0, 10) ?? 'All dates',
      ),
      TextCellValue(
        period.to?.toIso8601String().substring(0, 10) ?? 'All dates',
      ),
    ]);
    final filterSheet = excel['Parcel Filter'];
    filterSheet.appendRow([
      TextCellValue('Mode'),
      TextCellValue('Parcel ID'),
      TextCellValue('Parcel'),
    ]);
    filterSheet.appendRow([
      TextCellValue(parcelFilter.mode.name),
      TextCellValue(parcelFilter.parcelId ?? ''),
      TextCellValue(
        parcelFilter.mode == ProductionCostParcelMode.all
            ? 'All parcels'
            : parcelFilter.mode == ProductionCostParcelMode.general
            ? 'General expenses'
            : snapshot.parcelLabels[parcelFilter.parcelId] ??
                  'Linked land parcel',
      ),
    ]);
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
    String? currency,
    ProductionCostPeriod period = const ProductionCostPeriod(),
    ProductionCostParcelFilter parcelFilter =
        const ProductionCostParcelFilter.all(),
  }) async {
    final report = await workbook(
      period: period,
      parcelFilter: parcelFilter,
      currency: currency,
    );
    _authorize();
    await save(report);
  }
}
