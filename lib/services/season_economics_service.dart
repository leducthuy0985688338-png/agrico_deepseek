import '../providers/harvest_provider.dart';
import '../providers/production_log_provider.dart';

class SeasonEconomics {
  final double totalCost;
  final double totalRevenue;
  final double profit;
  final double costPerHa;
  final double revenuePerHa;
  final double profitPerHa;
  final double totalQuantity;
  final double yieldPerHa;

  const SeasonEconomics({
    required this.totalCost,
    required this.totalRevenue,
    required this.profit,
    required this.costPerHa,
    required this.revenuePerHa,
    required this.profitPerHa,
    required this.totalQuantity,
    required this.yieldPerHa,
  });

  static SeasonEconomics calculate({
    required double plannedAreaSquareMeters,
    required double totalCost,
    required double totalRevenue,
    required double totalQuantity,
  }) {
    final ha = plannedAreaSquareMeters / 10000;
    final safeHa = ha > 0 ? ha : 0;
    return SeasonEconomics(
      totalCost: totalCost,
      totalRevenue: totalRevenue,
      profit: totalRevenue - totalCost,
      costPerHa: safeHa > 0 ? totalCost / safeHa : 0,
      revenuePerHa: safeHa > 0 ? totalRevenue / safeHa : 0,
      profitPerHa: safeHa > 0 ? (totalRevenue - totalCost) / safeHa : 0,
      totalQuantity: totalQuantity,
      yieldPerHa: safeHa > 0 ? totalQuantity / safeHa : 0,
    );
  }

  static Future<SeasonEconomics> load({
    required double plannedAreaSquareMeters,
    required String seasonId,
  }) async {
    final logs = ProductionLogProvider()..loadForSeason(seasonId);
    final harvest = HarvestProvider()..loadForSeason(seasonId);
    await Future.wait([
      logs.loadForSeason(seasonId),
      harvest.loadForSeason(seasonId),
    ]);
    return calculate(
      plannedAreaSquareMeters: plannedAreaSquareMeters,
      totalCost: logs.totalCost(seasonId),
      totalRevenue: harvest.totalRevenue(seasonId),
      totalQuantity: harvest.totalQuantity(seasonId),
    );
  }
}
