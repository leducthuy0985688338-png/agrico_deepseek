export 'payroll_adjustment.dart';
import '../../inventory/domain/entities/exact_decimal.dart';
import '../../inventory/domain/entities/production_plan.dart';
export '../../inventory/domain/entities/exact_decimal.dart';

enum PayBasis { hourly, daily, piece }

enum MoneyRounding { halfUp, down }

abstract final class LaborMoney {
  static String sum(Iterable<String> values) => values
      .fold(ExactDecimal.parse('0'), (s, v) => s + ExactDecimal.parse(v))
      .toString();
  static String minus(String a, String b) =>
      (ExactDecimal.parse(a) - ExactDecimal.parse(b)).toString();

  /// Explicit payroll policy: base-ten money rounded only by the selected rule.
  static String fraction(
    String amount,
    int numerator,
    int denominator,
    int scale,
    MoneyRounding rounding,
  ) {
    if (numerator < 0 || denominator <= 0 || scale < 0 || scale > 6) {
      throw const FormatException('Invalid money ratio.');
    }
    final value = ExactDecimal.parse(amount);
    if (value.isNegative) throw const FormatException('Negative rate.');
    final dividend =
        value.coefficient * BigInt.from(numerator) * BigInt.from(10).pow(scale);
    final divisor = BigInt.from(denominator) * BigInt.from(10).pow(value.scale);
    var result = dividend ~/ divisor;
    if (rounding == MoneyRounding.halfUp &&
        (dividend % divisor) * BigInt.two >= divisor) {
      result += BigInt.one;
    }
    var digits = result.toString().padLeft(scale + 1, '0');
    if (scale > 0) {
      digits =
          '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
    }
    return ExactDecimal.parse(digits).toString();
  }

  /// Balance rounded source money across plans and the unallocated remainder.
  /// Largest remainders, stable input order, never duplicate a smallest unit.
  static List<String> allocate(
    String amount,
    List<int> weights,
    int total,
    int scale,
  ) {
    final source = ExactDecimal.parse(amount);
    if (source.isNegative ||
        weights.any((w) => w < 0) ||
        weights.fold<int>(0, (s, w) => s + w) > total ||
        source.scale > scale) {
      throw const FormatException('Invalid allocation weights.');
    }
    if (total == 0) {
      if (source.coefficient != BigInt.zero || weights.any((w) => w != 0)) {
        throw const FormatException('No allocation base.');
      }
      return weights.map((_) => '0').toList();
    }
    final units =
        source.coefficient * BigInt.from(10).pow(scale - source.scale);
    final all = [...weights, total - weights.fold<int>(0, (s, w) => s + w)];
    final parts = all
        .map((w) => units * BigInt.from(w) ~/ BigInt.from(total))
        .toList();
    final order = List<int>.generate(all.length, (i) => i)
      ..sort((a, b) {
        final c = (units * BigInt.from(all[b]) % BigInt.from(total)).compareTo(
          units * BigInt.from(all[a]) % BigInt.from(total),
        );
        return c == 0 ? a.compareTo(b) : c;
      });
    final remainder = (units - parts.fold(BigInt.zero, (s, n) => s + n))
        .toInt();
    for (var i = 0; i < remainder; i++) {
      parts[order[i]] += BigInt.one;
    }
    String render(BigInt n) {
      var digits = n.toString().padLeft(scale + 1, '0');
      if (scale > 0) {
        digits =
            '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
      }
      return ExactDecimal.parse(digits).toString();
    }

    return parts.take(weights.length).map(render).toList(growable: false);
  }

  static void nonNegative(String value, {int scale = 6}) {
    if (ExactDecimal.parse(value, maxScale: scale).isNegative) {
      throw const FormatException('Negative amount.');
    }
  }

  static String day(DateTime instant) => instant
      .toUtc()
      .add(const Duration(hours: 7))
      .toIso8601String()
      .substring(0, 10);
  static void date(String date) {
    if (!ProductionPlan.validDate(date)) {
      throw const FormatException('Invalid calendar date.');
    }
  }
}

class EmployeeProfile {
  EmployeeProfile({
    required this.workerId,
    required this.farmId,
    required Map<String, String> details,
    this.revision = 0,
    this.departmentId,
  }) : details = Map.unmodifiable(details);
  final String workerId, farmId;
  final String? departmentId;
  static const sensitiveFields = {
    'identityNo',
    'birthOn',
    'bankName',
    'bankAccount',
  };
  final int revision;
  final Map<String, String> details;
  static const fields = {
    'position',
    'department',
    'phone',
    'address',
    'birthOn',
    'gender',
    'identityNo',
    'contractStart',
    'contractEnd',
    'bankName',
    'bankAccount',
  };
  void validate() {
    if (workerId.trim().isEmpty ||
        farmId.trim().isEmpty ||
        revision < 0 ||
        !fields.containsAll(details.keys) ||
        details.values.any((v) => v.length > 500)) {
      throw const FormatException('Invalid employee profile.');
    }
    for (final key in ['birthOn', 'contractStart', 'contractEnd']) {
      final v = details[key];
      if (v != null && v.isNotEmpty) LaborMoney.date(v);
    }
    final start = details['contractStart'] ?? '',
        end = details['contractEnd'] ?? '';
    if (start.isNotEmpty && end.isNotEmpty && end.compareTo(start) < 0) {
      throw const FormatException('Invalid contract dates.');
    }
  }
}

class EmployeeCard {
  const EmployeeCard({
    required this.workerId,
    required this.code,
    required this.name,
    required this.active,
    this.profile,
  });
  final String workerId, code, name;
  final bool active;
  final EmployeeProfile? profile;
}

class PayRate {
  const PayRate({
    required this.id,
    required this.farmId,
    required this.workerId,
    required this.effectiveOn,
    required this.basis,
    required this.rate,
    required this.currency,
    required this.rounding,
    required this.moneyScale,
    this.standardMinutes = 480,
    this.overtimeHourlyRate,
    this.pieceUnit = '',
    this.workTypeId = '',
    this.revision = 0,
  });
  final int revision;
  final String id, farmId, workerId, effectiveOn, rate, currency, pieceUnit;
  final String workTypeId;
  final PayBasis basis;
  final MoneyRounding rounding;
  final int moneyScale, standardMinutes;
  final String? overtimeHourlyRate;
  void validate() {
    LaborMoney.date(effectiveOn);
    ExactDecimal.validatePrice(rate, currency);
    if ([id, farmId, workerId].any((v) => v.trim().isEmpty) ||
        moneyScale < 0 ||
        moneyScale > 6 ||
        standardMinutes < 1 ||
        standardMinutes > 1440 ||
        (basis == PayBasis.piece && pieceUnit.trim().isEmpty) ||
        pieceUnit.length > 40 ||
        (basis != PayBasis.piece && pieceUnit.isNotEmpty) ||
        revision < 0) {
      throw const FormatException('Invalid pay rate.');
    }
    if (overtimeHourlyRate != null) {
      ExactDecimal.validatePrice(overtimeHourlyRate!, currency);
    }
  }
}

class LaborAllocationDraft {
  const LaborAllocationDraft({
    required this.planId,
    required this.regularMinutes,
    required this.overtimeMinutes,
    this.taskId,
  });
  final String planId;
  final String? taskId;
  final int regularMinutes, overtimeMinutes;
}

class LaborEntryDraft {
  LaborEntryDraft({
    required this.id,
    required this.farmId,
    required this.workerId,
    required this.startsAt,
    required this.endsAt,
    required this.breakMinutes,
    required this.overtimeMinutes,
    this.pieceQuantity,
    required List<LaborAllocationDraft> allocations,
    this.notes = '',
    this.machineId,
    this.requestedBasis,
    this.requestedPieceUnit = '',
    this.workTypeId = '',
    this.outputQuantity,
    this.outputUnit,
  }) : allocations = List.unmodifiable(allocations);
  final String id, farmId, workerId, notes;
  final String? machineId;
  final PayBasis? requestedBasis;
  final String requestedPieceUnit, workTypeId;
  final String? outputQuantity, outputUnit;
  final DateTime startsAt, endsAt;
  final int breakMinutes, overtimeMinutes;
  final String? pieceQuantity;
  final List<LaborAllocationDraft> allocations;
  String get businessDay => LaborMoney.day(startsAt);
  int get netMinutes => endsAt.difference(startsAt).inMinutes - breakMinutes;
  int get regularMinutes => netMinutes - overtimeMinutes;
  bool get piece => pieceQuantity != null;
  void validate() {
    final duration = endsAt.difference(startsAt);
    if ([id, farmId, workerId].any((v) => v.trim().isEmpty) ||
        duration.inMinutes < 1 ||
        duration.inMinutes > 1440 ||
        startsAt.second != 0 ||
        startsAt.millisecond != 0 ||
        startsAt.microsecond != 0 ||
        endsAt.second != 0 ||
        endsAt.millisecond != 0 ||
        endsAt.microsecond != 0 ||
        breakMinutes < 0 ||
        netMinutes < 1 ||
        overtimeMinutes < 0 ||
        overtimeMinutes > netMinutes ||
        notes.length > 1000) {
      throw const FormatException('Invalid attendance interval.');
    }
    if ((outputQuantity == null) != (outputUnit == null)) {
      throw const FormatException('Output quantity/unit required together.');
    }
    if (outputQuantity != null &&
        (ExactDecimal.parse(outputQuantity!, maxScale: 6).coefficient <=
                BigInt.zero ||
            outputUnit!.trim().isEmpty ||
            outputUnit!.length > 40)) {
      throw const FormatException('Invalid measured work.');
    }
    if (requestedPieceUnit.length > 40 ||
        (!piece && requestedPieceUnit.isNotEmpty) ||
        machineId?.trim().isEmpty == true) {
      throw const FormatException('Invalid piece unit or machine.');
    }
    if (requestedBasis != null && (requestedBasis == PayBasis.piece) != piece) {
      throw const FormatException('Pay basis does not match work.');
    }
    if (piece &&
        (regularMinutes <= 0 ||
            ExactDecimal.parse(pieceQuantity!, maxScale: 6).coefficient <=
                BigInt.zero)) {
      throw const FormatException('Invalid piece quantity.');
    }
    var normal = 0, ot = 0;
    final plans = <String>{};
    for (final a in allocations) {
      if (a.planId.trim().isEmpty ||
          !plans.add(a.planId) ||
          a.regularMinutes < 0 ||
          a.overtimeMinutes < 0 ||
          a.regularMinutes + a.overtimeMinutes <= 0 ||
          a.taskId?.trim().isEmpty == true) {
        throw const FormatException('Invalid allocation.');
      }
      normal += a.regularMinutes;
      ot += a.overtimeMinutes;
    }
    if (normal > regularMinutes || ot > overtimeMinutes) {
      throw const FormatException('Allocation exceeds source time.');
    }
  }
}

class LaborEntryRecord {
  const LaborEntryRecord({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.businessDay,
    required this.startsAt,
    required this.endsAt,
    required this.breakMinutes,
    required this.regularMinutes,
    required this.overtimeMinutes,
    required this.status,
    required this.revision,
    this.pieceQuantity,
    this.pieceUnit,
    this.currency,
    this.regularAmount,
    this.overtimeAmount,
    this.pieceAmount,
    this.rateId,
    this.standardMinutes,
    this.machineId,
    this.outputQuantity,
    this.outputUnit,
    this.planLabels = const [],
    this.workTypeLabel,
  });
  final List<String> planLabels;
  final String? workTypeLabel;
  final String? outputQuantity, outputUnit;
  String? get productivityQuantity => outputQuantity ?? pieceQuantity;
  String? get productivityUnit => outputUnit ?? pieceUnit;
  final String id, workerId, workerName, businessDay, status;
  final int revision, breakMinutes, regularMinutes, overtimeMinutes;
  final DateTime startsAt, endsAt;
  final String? pieceQuantity,
      pieceUnit,
      currency,
      regularAmount,
      overtimeAmount,
      pieceAmount,
      rateId;
  final int? standardMinutes;
  final String? machineId;
  String? get total => regularAmount == null
      ? null
      : LaborMoney.sum([regularAmount!, overtimeAmount!, pieceAmount!]);
}

class PayrollDraft {
  const PayrollDraft({
    required this.id,
    required this.farmId,
    required this.workerId,
    required this.period,
    required this.currency,
    this.allowance = '0',
    this.bonus = '0',
    this.advance = '0',
    this.deduction = '0',
    this.note = '',
    this.adjustmentPlanId,
  });
  final String id,
      farmId,
      workerId,
      period,
      currency,
      allowance,
      bonus,
      advance,
      deduction,
      note;
  final String? adjustmentPlanId;
  void validate() {
    if ([id, farmId, workerId].any((v) => v.trim().isEmpty) ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) ||
        !{'VND', 'LAK'}.contains(currency)) {
      throw const FormatException('Invalid payroll period.');
    }
    for (final v in [allowance, bonus, advance, deduction]) {
      LaborMoney.nonNegative(v);
    }
    if ([
          allowance,
          bonus,
          advance,
          deduction,
        ].any((v) => ExactDecimal.parse(v).coefficient != BigInt.zero) &&
        note.trim().isEmpty) {
      throw const FormatException('Adjustment reason required.');
    }
  }
}

class PayrollRecordV2 {
  const PayrollRecordV2({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.period,
    required this.currency,
    required this.status,
    required this.regular,
    required this.overtime,
    required this.piece,
    required this.allowance,
    required this.bonus,
    required this.advance,
    required this.deduction,
    required this.net,
    required this.paid,
    required this.note,
    this.adjustmentPlanId,
    this.code = '',
    this.adjustmentTotal = '0',
    this.adjustmentRevision = 0,
    this.refunded = '0',
  });
  final String adjustmentTotal, refunded;
  final int adjustmentRevision;
  String get effectiveNet => LaborMoney.sum([net, adjustmentTotal]);
  String get overpaid => ExactDecimal.parse(remaining).isNegative
      ? LaborMoney.minus('0', remaining)
      : '0';
  String get payable =>
      ExactDecimal.parse(remaining).isNegative ? '0' : remaining;
  final String code;
  final String id,
      workerId,
      workerName,
      period,
      currency,
      status,
      regular,
      overtime,
      piece,
      allowance,
      bonus,
      advance,
      deduction,
      net,
      paid,
      note;
  final String? adjustmentPlanId;
  String get remaining =>
      status == 'cancelled' ? '0' : LaborMoney.minus(effectiveNet, paid);
}

class ProductionLaborCost {
  const ProductionLaborCost({
    required this.entryId,
    required this.planId,
    required this.currency,
    required this.amount,
    required this.businessDay,
    required this.regularMinutes,
    required this.overtimeMinutes,
  });
  final String entryId, planId, currency, amount, businessDay;
  final int regularMinutes, overtimeMinutes;
}

abstract interface class ProductionLaborCostRepository {
  Future<List<ProductionLaborCost>> productionLaborCosts(String farmId);
}

class PersonnelPlanChoice {
  const PersonnelPlanChoice(
    this.id,
    this.label,
    this.currency,
    this.startsOn,
    this.endsOn,
  );
  final String id, label, currency, startsOn, endsOn;
}

class PersonnelTaskChoice {
  const PersonnelTaskChoice(this.id, this.planId, this.label, this.workerId);
  final String id, planId, label;
  final String? workerId;
}

class SalaryPayment {
  const SalaryPayment({
    required this.id,
    required this.payrollId,
    required this.amount,
    required this.currency,
    required this.day,
    required this.note,
    this.reversed = false,
  });
  final String id, payrollId, amount, currency, day, note;
  final bool reversed;
}

abstract interface class PersonnelRepository {
  Future<List<PersonnelPlanChoice>> planChoices(String farmId);
  Future<List<PersonnelTaskChoice>> taskChoices(String farmId);
  Future<List<SalaryPayment>> payments(String farmId);
  Future<List<EmployeeCard>> employees(
    String farmId, {
    required bool sensitive,
  });
  Future<void> saveProfile(EmployeeProfile profile, String actorId);
  Future<List<PayRate>> rates(String farmId);
  Future<void> createRate(PayRate rate, String actorId);
  Future<List<LaborEntryRecord>> entries(String farmId, {required bool money});
  Future<void> createEntry(LaborEntryDraft draft, String actorId);
  Future<void> approveEntry(
    String farmId,
    String id,
    int revision,
    String actorId,
  );
  Future<void> voidEntry(
    String farmId,
    String id,
    int revision,
    String reason,
    String actorId,
  );
  Future<List<PayrollRecordV2>> payrolls(String farmId);
  Future<void> createPayroll(PayrollDraft draft, String actorId);
  Future<void> approvePayroll(String farmId, String id, String actorId);
  Future<void> cancelPayroll(
    String farmId,
    String id,
    String reason,
    String actorId,
  );
  Future<void> recordPayment(
    String farmId,
    String id,
    String payrollId,
    String amount,
    String currency,
    String day,
    String note,
    String actorId,
  );
}

class PersonnelDepartment {
  const PersonnelDepartment(this.id, this.name, {this.code = ''});
  final String id, name, code;
}

abstract interface class PersonnelOrganizationRepository {
  Future<List<PersonnelDepartment>> departments(String farmId);
  Future<void> createDepartment(
    String farmId,
    PersonnelDepartment department,
    String actorId,
  );
}
