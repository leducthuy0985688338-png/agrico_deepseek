import 'personnel.dart'
    show LaborMoney, ProductionLaborCost, PersonnelPlanChoice;
import '../../inventory/domain/entities/exact_decimal.dart';

enum PayrollAdjustmentKind { earnings, deduction }

class PayrollCostAdjustment {
  const PayrollCostAdjustment(this.planId, this.amount);
  final String planId, amount;
  Map<String, Object?> toJson() => {
    'planId': planId,
    'amount': ExactDecimal.parse(amount).toString(),
  };
}

class PayrollAdjustmentDraft {
  const PayrollAdjustmentDraft({
    required this.id,
    required this.farmId,
    required this.payrollId,
    required this.currency,
    required this.day,
    required this.delta,
    required this.reason,
    required this.expectedRevision,
    this.kind = PayrollAdjustmentKind.earnings,
    this.allocations = const [],
  });
  final String id, farmId, payrollId, currency, day, delta, reason;
  final int expectedRevision;
  final PayrollAdjustmentKind kind;
  final List<PayrollCostAdjustment> allocations;
  String get costDelta => LaborMoney.sum(allocations.map((a) => a.amount));
  void validate() {
    if ([id, farmId, payrollId, reason].any((v) => v.trim().isEmpty) ||
        reason.length > 2000 ||
        expectedRevision < 0 ||
        !{'VND', 'LAK'}.contains(currency)) {
      throw const FormatException('Invalid payroll adjustment.');
    }
    LaborMoney.date(day);
    final amount = ExactDecimal.parse(delta, maxScale: 6);
    if (amount.coefficient == BigInt.zero ||
        amount.coefficient.abs() > BigInt.from(9007199254740991)) {
      throw const FormatException('Nonzero exact adjustment required.');
    }
    if (kind == PayrollAdjustmentKind.deduction && allocations.isNotEmpty) {
      throw const FormatException('Deductions do not change production cost.');
    }
    if (allocations.map((a) => a.planId).toSet().length != allocations.length) {
      throw const FormatException('Duplicate plan allocation.');
    }
    for (final a in allocations) {
      final part = ExactDecimal.parse(a.amount, maxScale: 6);
      if (a.planId.trim().isEmpty ||
          part.coefficient == BigInt.zero ||
          part.isNegative != amount.isNegative) {
        throw const FormatException(
          'Allocation sign must match earnings correction.',
        );
      }
    }
    final allocated = ExactDecimal.parse(costDelta);
    final absolute = ExactDecimal.parse(
      allocated.isNegative ? LaborMoney.minus('0', costDelta) : costDelta,
    );
    final maximum = ExactDecimal.parse(
      amount.isNegative ? LaborMoney.minus('0', delta) : delta,
    );
    if (absolute.compareTo(maximum) > 0) {
      throw const FormatException('Allocation exceeds correction.');
    }
  }
}

class PayrollAdjustmentRecord {
  const PayrollAdjustmentRecord({
    required this.draft,
    required this.code,
    required this.status,
    required this.creator,
    required this.createdAt,
    required this.beforeNet,
    this.approver,
    this.approvedAt,
    this.approvedRevision,
  });
  final PayrollAdjustmentDraft draft;
  final String code, status, creator, createdAt, beforeNet;
  final String? approver, approvedAt;
  final int? approvedRevision;
}

class PayrollRefund {
  const PayrollRefund({
    required this.id,
    required this.payrollId,
    required this.amount,
    required this.currency,
    required this.day,
    required this.reason,
    required this.actor,
    required this.financeId,
    this.reversesId,
  });
  final String id, payrollId, amount, currency, day, reason, actor, financeId;
  final String? reversesId;
  String get signedAmount =>
      reversesId == null ? amount : LaborMoney.minus('0', amount);
}

abstract interface class PayrollAdjustmentRepository {
  Future<List<PersonnelPlanChoice>> payrollAdjustmentPlans(
    String farmId,
    String payrollId,
  );
  Future<List<PayrollAdjustmentRecord>> payrollAdjustments(String farmId);
  Future<void> createPayrollAdjustment(
    PayrollAdjustmentDraft draft,
    String actor,
  );
  Future<void> approvePayrollAdjustment(String farmId, String id, String actor);
  Future<void> cancelPayrollAdjustment(String farmId, String id, String actor);
  Future<List<PayrollRefund>> payrollRefunds(String farmId);
  Future<void> refundPayroll(
    String farmId,
    String id,
    String payrollId,
    String amount,
    String currency,
    String day,
    String reason,
    String actor, {
    String? reversesId,
  });
  Future<List<ProductionLaborCost>> payrollAdjustmentCosts(String farmId);
}
