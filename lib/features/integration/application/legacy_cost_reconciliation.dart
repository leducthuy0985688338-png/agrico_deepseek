import 'dart:convert';
import '../domain/production_cost_entry.dart';
import '../../inventory/domain/entities/exact_decimal.dart';

/// Explicit identity mapping supplied for review, never guessed from date/amount.
class LegacyCostSourceLink {
  const LegacyCostSourceLink({
    required this.source,
    required this.sourceId,
    required this.v2Key,
    required this.evidenceReference,
  });
  final String source, sourceId, v2Key, evidenceReference;
  String get legacyKey => jsonEncode([source, sourceId]);
}

class LegacyCostComparison {
  const LegacyCostComparison(
    this.legacyId,
    this.v2Key,
    this.issues,
    this.legacyAmount,
    this.v2Amount,
  );
  final String? legacyId, v2Key, v2Amount;
  final Object? legacyAmount;
  final List<String> issues;
  bool get exactMatch => issues.isEmpty;
  Map<String, Object?> toJson() => {
    'legacyId': legacyId,
    'v2Key': v2Key,
    'legacyAmountRaw': legacyAmount,
    'v2AmountExact': v2Amount,
    'classification': exactMatch ? 'exactMatch' : issues.join(';'),
  };
}

/// Pure read-only review engine. Never opens agrico_costs.db, infers a farm,
/// converts REAL to authoritative exact money, or adds legacy to V2 totals.
/// Caller supplies an authorized offline extract and explicit evidenced links.
abstract final class LegacyCostReconciliation {
  static List<LegacyCostComparison> compare({
    required List<Map<String, Object?>> legacyRows,
    required List<ProductionCostEntry> v2Entries,
    required List<LegacyCostSourceLink> links,
  }) {
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    String key(Map<String, Object?> row) =>
        jsonEncode([row['source'], row['source_id']]);
    final counts = <String, int>{};
    for (final row in legacyRows) {
      counts.update(key(row), (n) => n + 1, ifAbsent: () => 1);
    }
    final mappings = <String, List<LegacyCostSourceLink>>{};
    final targets = <String, int>{};
    for (final link in links) {
      mappings.putIfAbsent(link.legacyKey, () => []).add(link);
      targets.update(link.v2Key, (n) => n + 1, ifAbsent: () => 1);
    }
    final indexed = <String, List<ProductionCostEntry>>{};
    for (final entry in v2Entries) {
      indexed.putIfAbsent(entry.idempotencyKey, () => []).add(entry);
    }
    return [
      for (final row in legacyRows)
        (() {
          final issues = <String>[];
          final k = key(row);
          if (text(row['source']) == null || text(row['source_id']) == null) {
            issues.add('missingLegacySourceIdentity');
          } else if (counts[k]! > 1) {
            issues.add('duplicateLegacySource');
          }
          final candidates = mappings[k] ?? const <LegacyCostSourceLink>[];
          final link = candidates.length == 1 ? candidates.single : null;
          if (candidates.length > 1) issues.add('ambiguousSourceMapping');
          if (link == null || link.evidenceReference.trim().isEmpty) {
            issues.add('unmatchedSource');
          }
          if (link != null && targets[link.v2Key]! > 1) {
            issues.add('duplicateMappedSource');
          }
          final matches = indexed[link?.v2Key] ?? const <ProductionCostEntry>[];
          final v2 = matches.length == 1 ? matches.single : null;
          if (matches.length > 1) issues.add('duplicateV2Source');
          if (link != null && v2 == null) issues.add('unmatchedV2Source');
          if (!{'VND', 'LAK'}.contains(row['currency'])) {
            issues.add('missingCurrency');
          }
          if (row['revision'] is! int ||
              (row['revision'] as int) < 0 ||
              text(row['approved_by']) == null ||
              text(row['approved_at']) == null ||
              DateTime.tryParse(text(row['approved_at']) ?? '') == null ||
              row['status'] != 'approved') {
            issues.add('missingApprovalOrRevision');
          }
          ExactDecimal? legacyAmount;
          try {
            if (row['amount'] is! String) throw const FormatException();
            legacyAmount = ExactDecimal.parse(row['amount'] as String);
          } catch (_) {
            issues.add('legacyAmountNotExactText');
          }
          if (v2 != null) {
            for (final pair in [
              ('category', row['category'], v2.category.name),
              ('date', row['date'], v2.effectiveDate),
              ('parcel', row['field_id'], v2.parcelId),
              ('plan', row['plan_id'], v2.planId),
              ('currency', row['currency'], v2.currency),
            ]) {
              if (pair.$2 == null || pair.$3 == null || pair.$2 != pair.$3) {
                issues.add('dimensionMismatch:${pair.$1}');
              }
            }
            if (v2.eligibility != CostEligibility.eligible) {
              issues.add('v2NotEligible');
            }
            if (v2.sourceRevision == null ||
                v2.approvedBy == null ||
                v2.approvedAt == null) {
              issues.add('v2ApprovalOrRevisionMissing');
            }
            if (row['revision'] != null &&
                v2.sourceRevision != null &&
                row['revision'] != v2.sourceRevision) {
              issues.add('sourceVersionMismatch');
            }
            if (v2.amountExact == null) {
              issues.add('v2ExactAmountMissing');
            } else {
              try {
                final exactV2 = ExactDecimal.parse(v2.amountExact!);
                if (legacyAmount != null &&
                    legacyAmount.compareTo(exactV2) != 0) {
                  issues.add('amountMismatch');
                }
              } catch (_) {
                issues.add('v2ExactAmountInvalid');
              }
            }
          }
          return LegacyCostComparison(
            text(row['id']),
            link?.v2Key,
            List.unmodifiable(issues),
            row['amount'],
            v2?.amountExact,
          );
        })(),
    ];
  }
}
