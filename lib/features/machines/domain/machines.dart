import '../../personnel/domain/personnel.dart' show LaborMoney, MoneyRounding;
import '../../inventory/domain/entities/exact_decimal.dart';
export '../../personnel/domain/personnel.dart' show MoneyRounding;
export '../../inventory/domain/entities/exact_decimal.dart';

abstract final class MachineRules {
  static void requiredText(String text) {
    if (text.trim().isEmpty || text.length > 2000) {
      throw const FormatException('Required value.');
    }
  }

  static void date(String day) => LaborMoney.date(day);
  static void amount(String amount) => LaborMoney.nonNegative(amount);
  static String day(DateTime time) => LaborMoney.day(time);
}

class MachineCard {
  const MachineCard(
    this.id,
    this.code,
    this.name,
    this.active,
    this.profile,
    this.revision,
  );
  final String id, code, name;
  final bool active;
  final Map<String, String> profile;
  final int revision;
}

class MachineRate {
  const MachineRate({
    required this.id,
    required this.machineId,
    required this.effectiveOn,
    required this.amount,
    required this.currency,
    required this.shiftMinutes,
    required this.scale,
    required this.rounding,
    this.revision = 0,
  });
  final String id, machineId, effectiveOn, amount, currency;
  final int shiftMinutes, scale, revision;
  final MoneyRounding rounding;
  void validate() {
    MachineRules.requiredText(id);
    MachineRules.requiredText(machineId);
    MachineRules.date(effectiveOn);
    ExactDecimal.validatePrice(amount, currency);
    if (shiftMinutes <= 0 ||
        shiftMinutes > 1440 ||
        scale < 0 ||
        scale > 6 ||
        revision < 0) {
      throw const FormatException('Invalid shift policy.');
    }
  }

  String cost(int minutes) =>
      LaborMoney.fraction(amount, minutes, shiftMinutes, scale, rounding);
  Map<String, dynamic> toJson() => {
    'id': id,
    'machineId': machineId,
    'effectiveOn': effectiveOn,
    'amount': amount,
    'currency': currency,
    'shiftMinutes': shiftMinutes,
    'scale': scale,
    'rounding': rounding.name,
    'revision': revision,
  };
  factory MachineRate.fromJson(Map<String, dynamic> j) => MachineRate(
    id: j['id'] as String,
    machineId: j['machineId'] as String,
    effectiveOn: j['effectiveOn'] as String,
    amount: j['amount'] as String,
    currency: j['currency'] as String,
    shiftMinutes: j['shiftMinutes'] as int,
    scale: j['scale'] as int,
    rounding: MoneyRounding.values.byName(j['rounding'] as String),
    revision: j['revision'] as int,
  );
}

class MachineAllocation {
  const MachineAllocation(this.planId, this.minutes, {this.taskId});
  final String planId;
  final int minutes;
  final String? taskId;
  Map<String, dynamic> toJson() => {
    'planId': planId,
    'minutes': minutes,
    'taskId': taskId,
  };
  factory MachineAllocation.fromJson(Map<String, dynamic> j) =>
      MachineAllocation(
        j['planId'] as String,
        j['minutes'] as int,
        taskId: j['taskId'] as String?,
      );
}

class MachineRun {
  const MachineRun({
    required this.id,
    required this.machineId,
    required this.operatorId,
    required this.startsAt,
    required this.endsAt,
    required this.idleMinutes,
    required this.meterStart,
    required this.meterEnd,
    this.allocations = const [],
    this.outputQuantity,
    this.outputUnit,
    this.note = '',
  });
  final String id, machineId, operatorId, meterStart, meterEnd, note;
  final DateTime startsAt, endsAt;
  final int idleMinutes;
  final List<MachineAllocation> allocations;
  final String? outputQuantity, outputUnit;
  int get minutes => endsAt.difference(startsAt).inMinutes - idleMinutes;
  String get businessDay => MachineRules.day(startsAt);
  void validate() {
    for (final s in [id, machineId, operatorId]) {
      MachineRules.requiredText(s);
    }
    if (startsAt.second != 0 ||
        endsAt.second != 0 ||
        startsAt.millisecond != 0 ||
        endsAt.millisecond != 0 ||
        startsAt.microsecond != 0 ||
        endsAt.microsecond != 0 ||
        minutes <= 0 ||
        idleMinutes < 0 ||
        endsAt.difference(startsAt).inMinutes > 1440) {
      throw const FormatException('Invalid operating interval.');
    }
    MachineRules.amount(meterStart);
    MachineRules.amount(meterEnd);
    if (ExactDecimal.parse(meterEnd).compareTo(ExactDecimal.parse(meterStart)) <
        0) {
      throw const FormatException('Meter goes backwards.');
    }
    if (allocations.any((a) => a.minutes <= 0 || a.planId.isEmpty) ||
        allocations.map((a) => a.planId).toSet().length != allocations.length ||
        allocations.fold<int>(0, (s, a) => s + a.minutes) > minutes) {
      throw const FormatException('Invalid allocations.');
    }
    if (outputQuantity != null) {
      MachineRules.amount(outputQuantity!);
      MachineRules.requiredText(outputUnit ?? '');
    } else if (outputUnit != null && outputUnit!.isNotEmpty) {
      throw const FormatException('Output required.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'machineId': machineId,
    'operatorId': operatorId,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'idleMinutes': idleMinutes,
    'meterStart': meterStart,
    'meterEnd': meterEnd,
    'outputQuantity': outputQuantity,
    'outputUnit': outputUnit,
    'note': note,
    'allocations': allocations.map((a) => a.toJson()).toList(),
  };
  factory MachineRun.fromJson(Map<String, dynamic> j) => MachineRun(
    id: j['id'] as String,
    machineId: j['machineId'] as String,
    operatorId: j['operatorId'] as String,
    startsAt: DateTime.parse(j['startsAt'] as String),
    endsAt: DateTime.parse(j['endsAt'] as String),
    idleMinutes: j['idleMinutes'] as int,
    meterStart: j['meterStart'] as String,
    meterEnd: j['meterEnd'] as String,
    outputQuantity: j['outputQuantity'] as String?,
    outputUnit: j['outputUnit'] as String?,
    note: j['note'] as String,
    allocations: (j['allocations'] as List)
        .map(
          (a) =>
              MachineAllocation.fromJson(Map<String, dynamic>.from(a as Map)),
        )
        .toList(),
  );
}

class MachineExpense {
  const MachineExpense({
    required this.id,
    required this.machineId,
    required this.kind,
    required this.day,
    required this.amount,
    required this.currency,
    required this.reference,
    required this.note,
    this.litres,
    this.meter,
    this.nextOn,
    this.nextMeter,
  });
  final String id, machineId, kind, day, amount, currency, reference, note;
  final String? litres, meter, nextOn, nextMeter;
  void validate() {
    for (final s in [id, machineId, reference, note]) {
      MachineRules.requiredText(s);
    }
    if (!{'fuel', 'maintenance'}.contains(kind)) {
      throw const FormatException('Unknown expense.');
    }
    MachineRules.date(day);
    ExactDecimal.validatePrice(amount, currency);
    if (kind == 'fuel' &&
        (litres == null ||
            ExactDecimal.parse(
                  litres!,
                  maxScale: 6,
                ).compareTo(ExactDecimal.parse('0')) <=
                0)) {
      throw const FormatException('Positive litres required.');
    }
    if (litres != null) MachineRules.amount(litres!);
    if (meter != null) MachineRules.amount(meter!);
    if (nextOn != null) {
      MachineRules.date(nextOn!);
      if (nextOn!.compareTo(day) <= 0) {
        throw const FormatException('Next service must be later.');
      }
    }
    if (nextMeter != null) {
      MachineRules.amount(nextMeter!);
      if (meter == null ||
          ExactDecimal.parse(
                nextMeter!,
              ).compareTo(ExactDecimal.parse(meter!)) <=
              0) {
        throw const FormatException('Invalid next meter.');
      }
    }
    if (kind == 'fuel' && (nextOn != null || nextMeter != null)) {
      throw const FormatException('Fuel cannot schedule service.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'machineId': machineId,
    'kind': kind,
    'day': day,
    'amount': amount,
    'currency': currency,
    'reference': reference,
    'note': note,
    'litres': litres,
    'meter': meter,
    'nextOn': nextOn,
    'nextMeter': nextMeter,
  };
  factory MachineExpense.fromJson(Map<String, dynamic> j) => MachineExpense(
    id: j['id'] as String,
    machineId: j['machineId'] as String,
    kind: j['kind'] as String,
    day: j['day'] as String,
    amount: j['amount'] as String,
    currency: j['currency'] as String,
    reference: j['reference'] as String,
    note: j['note'] as String,
    litres: j['litres'] as String?,
    meter: j['meter'] as String?,
    nextOn: j['nextOn'] as String?,
    nextMeter: j['nextMeter'] as String?,
  );
}

class MachineRecord<T> {
  const MachineRecord(
    this.value,
    this.status,
    this.revision, {
    this.amount,
    this.currency,
    this.rateId,
  });
  final T value;
  final String status;
  final int revision;
  final String? amount, currency, rateId;
}

class ProductionMachineCost {
  const ProductionMachineCost({
    required this.sourceId,
    required this.machineId,
    required this.planId,
    required this.day,
    required this.minutes,
    required this.amount,
    required this.currency,
  });
  final String sourceId, machineId, planId, day, amount, currency;
  final int minutes;
}

abstract interface class ProductionMachineCostRepository {
  Future<List<ProductionMachineCost>> productionMachineCosts(String farm);
}

abstract interface class MachineRepository
    implements ProductionMachineCostRepository {
  Future<List<MachineCard>> machines(String farm);
  Future<void> profile(
    String farm,
    String machine,
    int revision,
    Map<String, String> values,
    String actor,
  );
  Future<List<MachineRate>> rates(String farm);
  Future<void> addRate(String farm, MachineRate rate, String actor);
  Future<List<MachineRecord<MachineRun>>> runs(
    String farm, {
    bool money = true,
  });
  Future<void> addRun(String farm, MachineRun run, String actor);
  Future<void> approveRun(String farm, String id, int revision, String actor);
  Future<void> voidRun(
    String farm,
    String id,
    int revision,
    String reason,
    String actor,
  );
  Future<List<MachineRecord<MachineExpense>>> expenses(String farm);
  Future<void> addExpense(String farm, MachineExpense expense, String actor);
  Future<void> approveExpense(
    String farm,
    String id,
    int revision,
    String actor,
  );
  Future<void> voidExpense(
    String farm,
    String id,
    int revision,
    String reason,
    String actor,
  );
  Future<List<Map<String, Object?>>> plans(String farm);
  Future<List<Map<String, Object?>>> workers(String farm);
}
