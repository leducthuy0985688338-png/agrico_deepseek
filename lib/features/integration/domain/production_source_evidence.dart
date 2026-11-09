import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../inventory/domain/entities/exact_decimal.dart';

/// Diagnostic evidence only. These states never authorize a posting or approval.
class ProductionSourceEvidence {
  ProductionSourceEvidence(this.state, this.issues, {this.observedIdentity});
  final String state;
  final List<String> issues;
  final String? observedIdentity;

  static String fingerprint(Map<String, Object?> fields) {
    final keys = fields.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(jsonEncode({for (final key in keys) key: fields[key]})),
        )
        .toString();
  }

  static bool _text(Object? v) => v is String && v.trim().isNotEmpty;
  static bool _date(Object? v) => v is String && DateTime.tryParse(v) != null;

  static ProductionSourceEvidence material(
    Map<String, Object?> cost,
    Map<String, Object?>? movement,
    Map<String, Object?>? plan,
  ) {
    if (movement == null) {
      return ProductionSourceEvidence('missingSource', ['movementMissing']);
    }
    final issues = <String>[];
    for (final key in [
      'farm_id',
      'item_id',
      'plan_id',
      'quantity_units',
      'unit_price_text',
      'amount_text',
      'currency',
      'priced_by',
      'occurred_at',
      'zero_price_confirmed',
    ]) {
      if (cost[key] == null ||
          movement[key] == null ||
          cost[key] != movement[key]) {
        issues.add('movementFieldMismatch:$key');
      }
    }
    for (final key in [
      'farm_id',
      'item_id',
      'plan_id',
      'unit_price_text',
      'amount_text',
      'currency',
      'priced_by',
      'occurred_at',
    ]) {
      if (!_text(movement[key]) || !_text(cost[key])) {
        issues.add('movementRequiredFieldMissing:$key');
      }
    }
    if (!_date(movement['occurred_at'])) issues.add('movementDateInvalid');
    if (!_text(movement['id']) ||
        cost['movement_id'] != movement['id'] ||
        !_text(movement['code']) ||
        movement['kind'] != 'issue') {
      issues.add('movementDocumentIdentityMismatch');
    }
    if (plan == null ||
        cost['farm_id'] != plan['farm_id'] ||
        cost['parcel_id'] != plan['parcel_id'] ||
        cost['season_id'] == null ||
        cost['season_id'] != plan['season_id'] ||
        cost['currency'] != plan['currency']) {
      issues.add('movementDestinationMismatch');
    }
    try {
      final units = cost['quantity_units'];
      if (units is! int || units <= 0) throw const FormatException();
      // Convert persisted integer units directly; never round a binary quantity.
      final quantity =
          ExactDecimal.parse(units.toString()) * ExactDecimal.parse('0.000001');
      final price = ExactDecimal.parse(cost['unit_price_text'] as String);
      final amount = ExactDecimal.parse(cost['amount_text'] as String);
      if (price.isNegative ||
          amount.isNegative ||
          (quantity * price).compareTo(amount) != 0 ||
          (price.coefficient == BigInt.zero &&
              cost['zero_price_confirmed'] != 1)) {
        issues.add('movementArithmeticMismatch');
      }
    } catch (_) {
      issues.add('movementArithmeticUnverified');
    }
    final invalidated =
        {
          'void',
          'voided',
          'reversed',
          'cancelled',
        }.contains(movement['status']) ||
        movement['reverses_id'] != null ||
        movement['reversal_id'] != null;
    if (invalidated) {
      // Native production issues have no approved reversal allocation contract.
      // Do not turn an unfamiliar receipt/reversal into a negative cost.
      issues.add('materialReversalRequiresReconciliation');
    }
    final hasApproval =
        _text(movement['approved_by']) && _date(movement['approved_at']);
    final revision = movement['revision'];
    if (revision is! int || revision < 0) {
      issues.add('materialRevisionNotPersisted');
    }
    if (!hasApproval) issues.add('materialIndependentApprovalNotRecorded');
    return ProductionSourceEvidence(
      invalidated
          ? 'voidOrReversalObserved'
          : issues.any((i) => !i.startsWith('material'))
          ? 'sourceMismatch'
          : hasApproval
          ? 'recordedApprovalEvidence'
          : 'immutableIssueWithoutApproval',
      issues,
      observedIdentity: fingerprint({
        'movement_id': movement['id'],
        for (final key in [
          'farm_id',
          'code',
          'item_id',
          'plan_id',
          'quantity_units',
          'unit_price_text',
          'amount_text',
          'currency',
          'occurred_at',
          'priced_by',
        ])
          key: movement[key],
      }),
    );
  }

  static ProductionSourceEvidence payroll(
    Map<String, Object?> payroll,
    Iterable<Map<String, Object?>> audit,
  ) {
    final issues = <String>[];
    final events = audit
        .where(
          (e) =>
              e['farm_id'] == payroll['farm_id'] &&
              e['entity_id'] == payroll['id'],
        )
        .toList();
    for (final action in ['payroll.create', 'payroll.approve']) {
      final found = events.where((e) => e['action'] == action).toList();
      if (found.length != 1 ||
          !_text(found.singleOrNull?['id']?.toString()) ||
          !_text(found.singleOrNull?['actor_id']) ||
          !_date(found.singleOrNull?['occurred_at'])) {
        issues.add('payrollAuditIdentityUnverified:$action');
      }
    }
    // Audit IDs prove an event occurred, not which financial payload was approved.
    // A digest detects observation changes; it is NOT a persisted source version.
    if (payroll['revision'] is! int || (payroll['revision'] as int) < 0) {
      issues.add('payrollDurableVersionMissing');
    }
    return ProductionSourceEvidence(
      issues.isEmpty
          ? 'recordedVersionEvidence'
          : 'observedSnapshotNotApprovedVersion',
      issues,
      observedIdentity: fingerprint({
        for (final key in [
          'id',
          'farm_id',
          'worker_id',
          'period',
          'currency',
          'code',
          'allowance',
          'bonus',
          'adjustment_plan_id',
          'extra_cost_day',
        ])
          key: payroll[key],
      }),
    );
  }
}

enum ProductionExpenseClass {
  directProduction,
  commonProduction,
  administrativeOrPeriod,
  paymentOnly,
  includedInSource,
  unqualified,
}

abstract final class ProductionExpensePolicy {
  /// Classification alone never authorizes cost; a native approved allocation is required.
  static ProductionExpenseClass classify(String sourceType, Object? treatment) {
    if (sourceType == 'cash' || sourceType == 'settlement') {
      return ProductionExpenseClass.paymentOnly;
    }
    return switch (treatment) {
      'periodExpense' => ProductionExpenseClass.administrativeOrPeriod,
      'includedInProduction' => ProductionExpenseClass.includedInSource,
      'directProduction' => ProductionExpenseClass.directProduction,
      'commonProduction' => ProductionExpenseClass.commonProduction,
      _ => ProductionExpenseClass.unqualified,
    };
  }
}
