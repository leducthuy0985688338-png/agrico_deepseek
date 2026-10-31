import 'dart:convert';
import '../../inventory/domain/entities/exact_decimal.dart';

enum ProductionCostCategory { labor, material, machine, other, revenue }

enum CostEligibility { eligible, pending, incomplete, excluded, voided }

/// A read-only source projection, never a second journal or a posting API.
class ProductionCostEntry {
  ProductionCostEntry({
    required this.sourceType,
    required this.sourceId,
    required this.lineId,
    required this.category,
    required this.eligibility,
    required this.approvalStatus,
    this.sourceRevision,
    this.planId,
    this.parcelId,
    this.amountExact,
    this.currency,
    this.scale,
    this.effectiveDate,
    this.accountingPeriod,
    this.createdBy,
    this.createdAt,
    this.approvedBy,
    this.approvedAt,
    this.correctionReference,
    this.auditReference,
    List<String> issues = const [],
  }) : issues = List.unmodifiable(issues);
  final String sourceType, sourceId, lineId, approvalStatus;
  final String? planId,
      parcelId,
      amountExact,
      currency,
      effectiveDate,
      accountingPeriod,
      createdBy,
      createdAt,
      approvedBy,
      approvedAt,
      correctionReference,
      auditReference;
  final int? sourceRevision, scale;
  final ProductionCostCategory category;
  final CostEligibility eligibility;
  final List<String> issues;
  String get idempotencyKey => jsonEncode([sourceType, sourceId, lineId]);
  bool get isCost => category != ProductionCostCategory.revenue;
  bool get blocksTotals =>
      eligibility == CostEligibility.incomplete ||
      eligibility == CostEligibility.pending;
}

class ProductionCostGroup {
  ProductionCostGroup({
    required this.parcelId,
    required this.planId,
    required this.currency,
    required this.entries,
    required this.coverageIssues,
  });
  final String parcelId, currency;
  final String? planId;
  final List<ProductionCostEntry> entries;
  final List<String> coverageIssues;
  bool get complete =>
      coverageIssues.isEmpty && !entries.any((e) => e.blocksTotals);
  String? amount(ProductionCostCategory category) {
    if (coverageIssues.isNotEmpty ||
        entries.any((e) => e.category == category && e.blocksTotals)) {
      return null;
    }
    return entries
        .where(
          (e) =>
              e.category == category &&
              e.eligibility == CostEligibility.eligible,
        )
        .fold(
          ExactDecimal.parse('0'),
          (sum, e) => sum + ExactDecimal.parse(e.amountExact!),
        )
        .toString();
  }

  String? get totalCost {
    final amounts = [
      for (final c in ProductionCostCategory.values.where(
        (c) => c != ProductionCostCategory.revenue,
      ))
        amount(c),
    ];
    if (amounts.any((a) => a == null)) return null;
    return amounts
        .fold(ExactDecimal.parse('0'), (s, a) => s + ExactDecimal.parse(a!))
        .toString();
  }

  String? get revenue => amount(ProductionCostCategory.revenue);
  String? get profit => totalCost == null || revenue == null
      ? null
      : (ExactDecimal.parse(revenue!) - ExactDecimal.parse(totalCost!))
            .toString();
  String get status => !complete
      ? 'INCOMPLETE'
      : entries.any((e) => e.eligibility == CostEligibility.eligible)
      ? 'APPROVED'
      : 'NO_ACTIVITY';
}
