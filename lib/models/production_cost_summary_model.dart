import 'production_cost_model.dart';

class ProductionCostSummaryModel {
  final String seasonId;
  final String fieldId;
  final double totalCost;
  final Map<ProductionCostCategory, double> byCategory;

  const ProductionCostSummaryModel({
    required this.seasonId,
    required this.fieldId,
    required this.totalCost,
    required this.byCategory,
  });

  double get material => byCategory[ProductionCostCategory.material] ?? 0;
  double get labor => byCategory[ProductionCostCategory.labor] ?? 0;
  double get machine => byCategory[ProductionCostCategory.machine] ?? 0;
  double get fuel => byCategory[ProductionCostCategory.fuel] ?? 0;

  double costPerHa(double areaHa) => areaHa <= 0 ? 0 : totalCost / areaHa;
}
