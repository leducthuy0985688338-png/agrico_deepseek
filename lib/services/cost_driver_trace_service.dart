import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../providers/production_cost_provider.dart';
import 'season_cost_driver_analysis_service.dart';

class CostDriverTraceRow {
  final String seasonId;
  final String fieldId;
  final String driverLabel;
  final ProductionCostCategory category;
  final double amount;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String? source;
  final String? sourceId;
  final String recordId;

  const CostDriverTraceRow({
    required this.seasonId,
    required this.fieldId,
    required this.driverLabel,
    required this.category,
    required this.amount,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.source,
    required this.sourceId,
    required this.recordId,
  });
}

class CostDriverTraceService {
  const CostDriverTraceService();

  Future<List<CostDriverTraceRow>> trace({
    required ProductionSeasonModel season,
    required SeasonCostDriverChange driver,
  }) async {
    final provider = ProductionCostProvider();
    try {
      await provider.loadForSeason(season.id);
      final records = provider.recordsForSeason(season.id)
          .where((record) => record.category == driver.category)
          .where((record) => _label(record) == driver.label)
          .toList(growable: false);

      return records
          .map(
            (record) => CostDriverTraceRow(
              seasonId: record.seasonId,
              fieldId: record.fieldId,
              driverLabel: driver.label,
              category: record.category,
              amount: record.amount,
              quantity: record.quantity,
              unit: record.unit,
              unitPrice: record.unitPrice,
              source: record.source,
              sourceId: record.sourceId,
              recordId: record.id,
            ),
          )
          .toList(growable: false);
    } finally {
      provider.dispose();
    }
  }

  Future<Map<String, double>> aggregateByField({
    required ProductionSeasonModel season,
    required SeasonCostDriverChange driver,
  }) async {
    final rows = await trace(season: season, driver: driver);
    final result = <String, double>{};
    for (final row in rows) {
      result[row.fieldId] = (result[row.fieldId] ?? 0) + row.amount;
    }
    return result;
  }

  String _label(ProductionCostModel record) {
    final item = record.itemName.trim();
    return item.isEmpty ? record.category.label : item;
  }
}
