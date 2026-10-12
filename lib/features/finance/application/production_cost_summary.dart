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
  }) : groups = List.unmodifiable(groups),
       parcelLabels = Map.unmodifiable(parcelLabels);
  final List<ProductionCostGroup> groups;
  final Map<String, String> parcelLabels;
  final ProductionCostPeriod period;
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
    ProductionCostPeriod period = const ProductionCostPeriod(),
  }) async {
    period.validate();
    if (!canView) {
      throw StateError('Production cost access denied.');
    }
    final documents = await finance.listByOrganization(finance.organizationId);
    final parcels = await finance.availableParcels();
    if (!canView) {
      throw StateError('Production cost access denied.');
    }
    final buckets = <(String?, String), List<FinanceDocument>>{};
    for (final document in documents) {
      if (document.kind != BusinessDocumentKind.payment ||
          !period.contains(document.occurredAt)) {
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
      period: period,
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
