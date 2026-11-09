import 'exact_decimal.dart';

enum ProductionPlanStatus { draft, active, paused, completed, cancelled }

class ProductionPlan {
  const ProductionPlan({
    required this.id,
    required this.farmId,
    required this.parcelId,
    required this.seasonId,
    required this.name,
    required this.crop,
    required this.startsOn,
    required this.endsOn,
    required this.currency,
    required this.materialBudget,
    required this.laborBudget,
    required this.machineBudget,
    required this.laborHours,
    required this.machineShifts,
    this.code,
    this.parcelCode,
    this.seasonName,
    this.status = ProductionPlanStatus.draft,
    this.revision = 0,
  });
  final String id, farmId, parcelId, seasonId, name, crop, startsOn, endsOn;
  final String currency, materialBudget, laborBudget, machineBudget;
  final String laborHours, machineShifts;
  final String? code, parcelCode, seasonName;
  final ProductionPlanStatus status;
  final int revision;
  static bool validDate(String value) {
    final parsed = DateTime.tryParse(value);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        parsed != null &&
        parsed.toIso8601String().substring(0, 10) == value;
  }

  void validate() {
    if ([
          id,
          farmId,
          parcelId,
          seasonId,
          name,
          crop,
        ].any((s) => s.trim().isEmpty) ||
        name.length > 120 ||
        crop.length > 120 ||
        !validDate(startsOn) ||
        !validDate(endsOn) ||
        startsOn.compareTo(endsOn) > 0 ||
        revision < 0) {
      throw const FormatException('Invalid production plan.');
    }
    for (final amount in [
      materialBudget,
      laborBudget,
      machineBudget,
      laborHours,
      machineShifts,
    ]) {
      ExactDecimal.validatePrice(amount, currency);
    }
  }

  ExactDecimal get totalBudget =>
      ExactDecimal.parse(materialBudget) +
      ExactDecimal.parse(laborBudget) +
      ExactDecimal.parse(machineBudget);
}

class ProductionPlanTask {
  const ProductionPlanTask({
    required this.id,
    required this.farmId,
    required this.planId,
    required this.title,
    required this.stage,
    required this.quantity,
    required this.unit,
    this.completed = false,
    this.dueOn,
    this.revision = 0,
  });
  final String id, farmId, planId, title, stage, quantity, unit;
  final bool completed;
  final String? dueOn;
  final int revision;
  void validate() {
    if ([id, farmId, planId, title, unit].any((s) => s.trim().isEmpty) ||
        (dueOn != null && !ProductionPlan.validDate(dueOn!)) ||
        title.length > 160 ||
        stage.length > 120 ||
        unit.length > 40 ||
        ExactDecimal.parse(quantity, maxScale: 6).coefficient <= BigInt.zero ||
        revision < 0) {
      throw const FormatException('Invalid plan task.');
    }
  }
}
