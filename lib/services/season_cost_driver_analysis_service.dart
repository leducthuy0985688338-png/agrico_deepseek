import '../models/production_cost_model.dart';
import '../providers/production_cost_provider.dart';

class SeasonCostCategoryChange {
  final ProductionCostCategory category;
  final double currentAmount;
  final double previousAmount;

  const SeasonCostCategoryChange({
    required this.category,
    required this.currentAmount,
    required this.previousAmount,
  });

  double get absoluteChange => currentAmount - previousAmount;

  double get changeRate {
    if (previousAmount.abs() < 0.000001) {
      return currentAmount.abs() < 0.000001 ? 0 : 1;
    }
    return absoluteChange / previousAmount.abs();
  }
}

class SeasonCostDriverChange {
  final String label;
  final ProductionCostCategory category;
  final double currentAmount;
  final double previousAmount;

  const SeasonCostDriverChange({
    required this.label,
    required this.category,
    required this.currentAmount,
    required this.previousAmount,
  });

  double get absoluteChange => currentAmount - previousAmount;

  double get changeRate {
    if (previousAmount.abs() < 0.000001) {
      return currentAmount.abs() < 0.000001 ? 0 : 1;
    }
    return absoluteChange / previousAmount.abs();
  }
}

class SeasonCostDriverAnalysis {
  final String currentSeasonId;
  final String previousSeasonId;
  final double currentTotal;
  final double previousTotal;
  final List<SeasonCostCategoryChange> categories;
  final List<SeasonCostDriverChange> drivers;

  const SeasonCostDriverAnalysis({
    required this.currentSeasonId,
    required this.previousSeasonId,
    required this.currentTotal,
    required this.previousTotal,
    required this.categories,
    required this.drivers,
  });

  double get totalChange => currentTotal - previousTotal;

  double get totalChangeRate {
    if (previousTotal.abs() < 0.000001) {
      return currentTotal.abs() < 0.000001 ? 0 : 1;
    }
    return totalChange / previousTotal.abs();
  }

  List<SeasonCostCategoryChange> get increasingCategories => categories
      .where((item) => item.absoluteChange > 0.000001)
      .toList(growable: false);

  List<SeasonCostDriverChange> get increasingDrivers => drivers
      .where((item) => item.absoluteChange > 0.000001)
      .toList(growable: false);
}

class SeasonCostDriverAnalysisService {
  const SeasonCostDriverAnalysisService();

  Future<SeasonCostDriverAnalysis> analyze({
    required String currentSeasonId,
    required String previousSeasonId,
  }) async {
    final currentProvider = ProductionCostProvider();
    final previousProvider = ProductionCostProvider();

    try {
      await Future.wait([
        currentProvider.loadForSeason(currentSeasonId),
        previousProvider.loadForSeason(previousSeasonId),
      ]);

      final currentRecords = currentProvider.recordsForSeason(currentSeasonId);
      final previousRecords = previousProvider.recordsForSeason(previousSeasonId);

      final currentCategories = _categoryTotals(currentRecords);
      final previousCategories = _categoryTotals(previousRecords);
      final categories = ProductionCostCategory.values
          .map(
            (category) => SeasonCostCategoryChange(
              category: category,
              currentAmount: currentCategories[category] ?? 0,
              previousAmount: previousCategories[category] ?? 0,
            ),
          )
          .toList(growable: false);

      final currentDrivers = _driverTotals(currentRecords);
      final previousDrivers = _driverTotals(previousRecords);
      final driverKeys = <String>{...currentDrivers.keys, ...previousDrivers.keys};
      final drivers = driverKeys
          .map((key) {
            final current = currentDrivers[key];
            final previous = previousDrivers[key];
            return SeasonCostDriverChange(
              label: current?.label ?? previous?.label ?? key,
              category: current?.category ?? previous!.category,
              currentAmount: current?.amount ?? 0,
              previousAmount: previous?.amount ?? 0,
            );
          })
          .toList()
        ..sort((a, b) => b.absoluteChange.compareTo(a.absoluteChange));

      return SeasonCostDriverAnalysis(
        currentSeasonId: currentSeasonId,
        previousSeasonId: previousSeasonId,
        currentTotal: currentProvider.totalCost(currentSeasonId),
        previousTotal: previousProvider.totalCost(previousSeasonId),
        categories: categories,
        drivers: drivers,
      );
    } finally {
      currentProvider.dispose();
      previousProvider.dispose();
    }
  }

  Map<ProductionCostCategory, double> _categoryTotals(
    List<ProductionCostModel> records,
  ) {
    final result = <ProductionCostCategory, double>{};
    for (final record in records) {
      result[record.category] = (result[record.category] ?? 0) + record.amount;
    }
    return result;
  }

  Map<String, _DriverTotal> _driverTotals(List<ProductionCostModel> records) {
    final result = <String, _DriverTotal>{};
    for (final record in records) {
      final item = record.itemName.trim();
      final key = '${record.category.key}:$item';
      final existing = result[key];
      result[key] = _DriverTotal(
        label: item.isEmpty ? record.category.label : item,
        category: record.category,
        amount: (existing?.amount ?? 0) + record.amount,
      );
    }
    return result;
  }
}

class _DriverTotal {
  final String label;
  final ProductionCostCategory category;
  final double amount;

  const _DriverTotal({
    required this.label,
    required this.category,
    required this.amount,
  });
}
