import 'package:excel/excel.dart';
import '../domain/production_cost_entry.dart';
import 'production_cost_projection.dart';
import 'dart:convert';

abstract final class ProductionCostExport {
  static const tabs = [
    'CHI PHI SAN XUAT ERP',
    'GIA THANH THEO KE HOACH',
    'GIA THANH THEO LO DAT',
    'DOANH THU LOI NHUAN',
    'DOI CHIEU NGUON',
  ];
  static void append(Excel book, ProductionCostProjection projection) {
    final snapshot = projection.snapshot;
    void row(String tab, List<Object?> values) => book[tab].appendRow([
      for (final v in values) TextCellValue(v?.toString() ?? ''),
    ]);
    row(tabs[0], [
      'Source type',
      'Source ID',
      'Source revision',
      'Line ID',
      'Plan ID',
      'Plan code',
      'Parcel ID',
      'Parcel code',
      'Category',
      'Exact amount (text)',
      'Currency',
      'Scale',
      'Effective date UTC+7',
      'Accounting period',
      'Approval status',
      'Created by',
      'Created at',
      'Approved by',
      'Approved at',
      'Correction reference',
      'Audit reference',
      'Idempotency key',
      'Period locked',
      'Approved payload digest',
      'Approved payload version',
      'Allocation driver',
      'Weight units',
      'Allocation base units',
      'Weight evidence',
    ]);
    for (final entry in projection.entries.where(
      (e) => e.eligibility == CostEligibility.eligible && e.isCost,
    )) {
      final type = entry.sourceType == 'productionExpense'
          ? 'expenseAllocation'
          : entry.sourceType;
      final g = projection.governance(type, entry.sourceId);
      final policies = snapshot
          .rows('production_expense_policies_v2')
          .where(
            (r) =>
                r['source_id'] == entry.sourceId &&
                (type == 'expenseAllocation' ||
                    entry.sourceType == 'expenseReversal'),
          )
          .toList();
      final policy = policies.singleOrNull;
      final weights = policy == null
          ? const <dynamic>[]
          : ((snapshotDecode(policy['weights_json'])));
      final weight = weights
          .whereType<Map>()
          .where((r) => r['planId'] == entry.planId)
          .singleOrNull;
      row(tabs[0], [
        entry.sourceType,
        entry.sourceId,
        entry.sourceRevision,
        entry.lineId,
        entry.planId,
        snapshot.planCode(entry.planId),
        entry.parcelId,
        snapshot.parcelCode(entry.parcelId),
        entry.category.name,
        entry.amountExact,
        entry.currency,
        entry.scale,
        entry.effectiveDate,
        entry.accountingPeriod,
        entry.approvalStatus,
        entry.createdBy,
        entry.createdAt,
        entry.approvedBy,
        entry.approvedAt,
        entry.correctionReference,
        entry.auditReference,
        entry.idempotencyKey,
        snapshot.closingRevision != null,
        g?['status'] == 'approved' ? g!['payload_digest'] : null,
        g?['status'] == 'approved' ? g!['revision'] : null,
        policy?['driver'],
        weight?['units'],
        policy?['base_units'],
        weight?['evidence'],
      ]);
    }
    for (final byPlan in [true, false]) {
      final tab = byPlan ? tabs[1] : tabs[2];
      row(tab, [
        'Period',
        'Parcel ID',
        'Parcel code',
        'Plan ID',
        'Plan code',
        'Currency',
        'Labor (text)',
        'Material (text)',
        'Machine (text)',
        'Other (text)',
        'Total cost (text)',
        'Status',
        'Period locked',
      ]);
      for (final g in projection.groups(byPlan: byPlan)) {
        row(tab, [
          snapshot.period,
          g.parcelId,
          snapshot.parcelCode(g.parcelId),
          g.planId,
          g.planId == null ? null : snapshot.planCode(g.planId),
          g.currency,
          for (final c in [
            ProductionCostCategory.labor,
            ProductionCostCategory.material,
            ProductionCostCategory.machine,
            ProductionCostCategory.other,
          ])
            g.amount(c),
          g.totalCost,
          g.status,
          snapshot.closingRevision != null,
        ]);
      }
    }
    row(tabs[3], [
      'Period',
      'Parcel ID',
      'Parcel code',
      'Currency',
      'Incurred cost (text)',
      'Posted sales less reversals (text)',
      'Sales minus incurred cost (text)',
      'Status',
      'Period locked',
      'Scope',
    ]);
    for (final g in projection.groups()) {
      row(tabs[3], [
        snapshot.period,
        g.parcelId,
        snapshot.parcelCode(g.parcelId),
        g.currency,
        g.totalCost,
        g.revenue,
        g.profit,
        g.status,
        snapshot.closingRevision != null,
        'Posted sales minus incurred allocated production cost; not inventory-matched accounting profit',
      ]);
    }
    row(tabs[4], [
      'Source type',
      'Source ID',
      'Line ID',
      'Plan ID',
      'Parcel ID',
      'Currency',
      'Exact amount (text)',
      'Eligibility',
      'Source status',
      'Issues',
      'Idempotency key',
      'Effective date',
      'Period',
      'Period locked',
      'Correction reference',
      'Source evidence state',
      'Observed fingerprint (not approved version)',
    ]);
    for (final entry in projection.entries) {
      row(tabs[4], [
        entry.sourceType,
        entry.sourceId,
        entry.lineId,
        entry.planId,
        entry.parcelId,
        entry.currency,
        entry.amountExact,
        entry.eligibility.name,
        entry.approvalStatus,
        entry.issues.join('; '),
        entry.idempotencyKey,
        entry.effectiveDate,
        entry.accountingPeriod,
        snapshot.closingRevision != null,
        entry.correctionReference,
        projection.sourceEvidence[entry.idempotencyKey]?.state,
        projection.sourceEvidence[entry.idempotencyKey]?.observedIdentity,
      ]);
    }
    for (final issue in projection.coverageIssues) {
      row(tabs[4], [
        'coverage',
        null,
        null,
        null,
        null,
        null,
        null,
        'incomplete',
        null,
        issue,
      ]);
    }
    for (final tab in tabs) {
      for (var i = 0; i < book[tab].maxColumns; i++) {
        book[tab].setColumnWidth(i, 28);
      }
    }
  }

  static List<dynamic> snapshotDecode(Object? value) {
    try {
      return jsonDecode(value as String) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }
}
