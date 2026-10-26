import 'finance_document_filter.dart';
import 'production_cost_parcel_filter.dart';
import 'production_cost_period.dart';
import '../../../core/identity/domain/business_reference_code.dart';
import '../domain/finance_document.dart';
import 'finance_document_service.dart';

class ProductionCostGroup {
  ProductionCostGroup({
    required this.parcelId,
    required this.currency,
    required List<FinanceDocument> documents,
  }) : documents = List.unmodifiable(documents);
  final String? parcelId;
  final String currency;
  final List<FinanceDocument> documents;
  int get amountMinor =>
      documents.fold(0, (sum, document) => sum + document.amountMinor);
}

class ProductionCostSnapshot {
  ProductionCostSnapshot({
    required List<ProductionCostGroup> groups,
    required Map<String, String> parcelLabels,
    this.period = const ProductionCostPeriod(),
    this.parcelFilter = const ProductionCostParcelFilter.all(),
    Set<String> availableParcelIds = const {},
    Set<String> availableCurrencies = const {},
    this.currency,
    this.query = '',
  }) : groups = List.unmodifiable(groups),
       parcelLabels = Map.unmodifiable(parcelLabels),
       availableParcelIds = Set.unmodifiable(availableParcelIds),
       availableCurrencies = Set.unmodifiable(availableCurrencies);
  final List<ProductionCostGroup> groups;
  final Map<String, String> parcelLabels;
  final ProductionCostPeriod period;
  final ProductionCostParcelFilter parcelFilter;
  final Set<String> availableParcelIds;
  final Set<String> availableCurrencies;
  final String? currency;
  final String query;
  int get documentCount =>
      groups.fold(0, (count, group) => count + group.documents.length);

  Map<String, int> get totals {
    final result = <String, int>{};
    for (final group in groups) {
      result.update(
        group.currency,
        (amount) => amount + group.amountMinor,
        ifAbsent: () => group.amountMinor,
      );
    }
    return Map.unmodifiable(result);
  }
}

/// A view of saved payment documents; no second expense ledger is created.
class ProductionCostSummary {
  const ProductionCostSummary(this.finance);
  final FinanceDocumentService finance;
  bool get canView => finance.canExport;

  Future<ProductionCostSnapshot> load({
    String? currency,
    String query = '',
    ProductionCostPeriod period = const ProductionCostPeriod(),
    ProductionCostParcelFilter parcelFilter =
        const ProductionCostParcelFilter.all(),
  }) async {
    final filter = FinanceDocumentFilter(
      currency: currency,
      query: query,
      kind: BusinessDocumentKind.payment,
    );
    filter.validate();
    period.validate();
    parcelFilter.validate();
    if (!canView) {
      throw StateError('Production cost access denied.');
    }
    final allDocuments = await finance.listByOrganization(
      finance.organizationId,
    );
    final documents = allDocuments
        .where(
          (d) =>
              !d.isSettlement &&
              !d.isFinancing &&
              d.amountScale == 0 &&
              !d.category.startsWith('INTEGRATED_'),
        )
        .toList();
    if (!canView) {
      throw StateError('Production cost access denied.');
    }
    final identities = <String>{};
    for (final document in documents) {
      if (!identities.add(document.id)) {
        throw StateError('Duplicate finance document identity.');
      }
      if (document.kind == BusinessDocumentKind.payment &&
          (document.id.trim().isEmpty ||
              document.code.trim().isEmpty ||
              document.amountMinor <= 0 ||
              document.currency.trim().isEmpty ||
              document.category.trim().isEmpty ||
              (document.parcelId != null &&
                  document.parcelId!.trim().isEmpty))) {
        throw StateError('Invalid saved payment document.');
      }
    }
    final parcels = await finance.availableParcels();
    if (!canView) {
      throw StateError('Production cost access denied.');
    }
    final buckets = <(String?, String), List<FinanceDocument>>{};
    for (final document in documents) {
      if (!filter.matches(document) ||
          !period.contains(document.occurredAt) ||
          !parcelFilter.contains(document.parcelId)) {
        continue;
      }
      buckets
          .putIfAbsent((document.parcelId, document.currency), () => [])
          .add(document);
    }
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        final parcelOrder = (a.$1 ?? '').compareTo(b.$1 ?? '');
        return parcelOrder == 0 ? a.$2.compareTo(b.$2) : parcelOrder;
      });
    return ProductionCostSnapshot(
      currency: currency,
      query: query,
      availableCurrencies: {
        for (final document in documents)
          if (document.kind == BusinessDocumentKind.payment) document.currency,
      },
      period: period,
      parcelFilter: parcelFilter,
      availableParcelIds: {
        for (final parcel in parcels) parcel.id,
        for (final document in documents)
          if (document.kind == BusinessDocumentKind.payment) ?document.parcelId,
      },
      groups: [
        for (final key in keys)
          ProductionCostGroup(
            parcelId: key.$1,
            currency: key.$2,
            documents: buckets[key]!,
          ),
      ],
      parcelLabels: {
        for (final parcel in parcels)
          parcel.id: '${parcel.parcelCode} · ${parcel.name}',
      },
    );
  }
}
