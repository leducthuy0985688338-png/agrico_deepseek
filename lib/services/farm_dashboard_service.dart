import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_log_provider.dart';

class FarmDashboardMetrics {
  final double totalArea;
  final int fieldCount;
  final int seasonCount;
  final double totalCost;
  final double totalRevenue;
  final double totalProfit;
  final double totalHarvest;

  const FarmDashboardMetrics({
    required this.totalArea,
    required this.fieldCount,
    required this.seasonCount,
    required this.totalCost,
    required this.totalRevenue,
    required this.totalProfit,
    required this.totalHarvest,
  });

  double get areaHa => totalArea / 10000;
  double get profitPerHa => areaHa > 0 ? totalProfit / areaHa : 0;
  double get yieldPerHa => areaHa > 0 ? totalHarvest / areaHa : 0;

  static Future<FarmDashboardMetrics> calculate({
    required List<FieldModel> fields,
    required List<ProductionSeasonModel> seasons,
  }) async {
    double cost = 0;
    double revenue = 0;
    double harvest = 0;
    for (final season in seasons) {
      final logs = ProductionLogProvider();
      final crops = HarvestProvider();
      await Future.wait([
        logs.loadForSeason(season.id),
        crops.loadForSeason(season.id),
      ]);
      cost += logs.totalCost(season.id);
      revenue += crops.totalRevenue(season.id);
      harvest += crops.totalQuantity(season.id);
      logs.dispose();
      crops.dispose();
    }
    return FarmDashboardMetrics(
      totalArea: fields.fold(0, (sum, field) => sum + field.area),
      fieldCount: fields.length,
      seasonCount: seasons.length,
      totalCost: cost,
      totalRevenue: revenue,
      totalProfit: revenue - cost,
      totalHarvest: harvest,
    );
  }
}
