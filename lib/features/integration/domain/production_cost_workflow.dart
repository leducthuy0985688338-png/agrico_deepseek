enum CostAllocationDriver {
  direct,
  area,
  machineMinutes,
  laborMinutes,
  approvedWeights,
}

class CostAllocationWeight {
  const CostAllocationWeight(this.planId, this.units, this.evidence);
  final String planId, evidence;
  final int units;
  Map<String, Object?> toJson() => {
    'planId': planId,
    'units': units,
    'evidence': evidence,
  };
}

class ExpenseAllocationProposal {
  ExpenseAllocationProposal({
    required this.expenseId,
    required this.driver,
    required this.baseUnits,
    required this.moneyScale,
    required List<CostAllocationWeight> weights,
  }) : weights = List.unmodifiable(weights);
  final String expenseId;
  final CostAllocationDriver driver;
  final int baseUnits, moneyScale;
  final List<CostAllocationWeight> weights;
  void validate() {
    if (expenseId.trim().isEmpty ||
        baseUnits <= 0 ||
        baseUnits > 9007199254740991 ||
        moneyScale < 0 ||
        moneyScale > 6 ||
        weights.isEmpty ||
        weights.length > 1000 ||
        weights.map((w) => w.planId).toSet().length != weights.length ||
        weights.any(
          (w) =>
              w.planId.trim().isEmpty ||
              w.evidence.trim().isEmpty ||
              w.units <= 0 ||
              w.units > baseUnits,
        ) ||
        weights.fold<int>(0, (s, w) => s + w.units) > baseUnits) {
      throw const FormatException(
        'Explicit positive allocation base and evidenced unique plans required.',
      );
    }
    if (driver == CostAllocationDriver.direct &&
        (baseUnits != 1 || weights.length != 1 || weights.single.units != 1)) {
      throw const FormatException(
        'Direct expense requires exactly one full destination.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'expenseId': expenseId,
    'driver': driver.name,
    'baseUnits': baseUnits,
    'moneyScale': moneyScale,
    'weights': weights.map((w) => w.toJson()).toList(),
  };
}

abstract interface class ProductionCostWorkflowStore {
  Future<void> approveMaterial(
    String farm,
    String id,
    int revision,
    String actor,
    void Function() checkAccess,
  );
  Future<void> proposeExpense(
    String farm,
    ExpenseAllocationProposal proposal,
    String actor,
    void Function() checkAccess,
  );
  Future<void> approveExpense(
    String farm,
    String id,
    int revision,
    String actor,
    void Function() checkAccess,
  );
}
