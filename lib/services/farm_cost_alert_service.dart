import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import 'production_cost_database.dart';

class FarmCostAlertService {
  final ProductionCostDatabase _database;

  FarmCostAlertService({ProductionCostDatabase? database})
      : _database = database ?? ProductionCostDatabase();

  Future<List<FarmCostAlertRow>> load({
    required List<FieldModel> fields,
    required List<ProductionSeasonModel> seasons,
  }) async {
    if (seasons.isEmpty) return const [];

    final fieldById = <String, FieldModel>{
      for (final field in fields) field.id: field,
    };

    final rows = <_RawSeasonCost>[];
    for (final season in seasons) {
      final records = await _database.getBySeason(season.id);
      final byCategory = <ProductionCostCategory, double>{};
      var total = 0.0;
      for (final record in records) {
        total += record.amount;
        byCategory[record.category] =
            (byCategory[record.category] ?? 0) + record.amount;
      }
      final field = fieldById[season.fieldId];
      final areaHa = season.plannedArea > 0
          ? season.plannedArea / 10000
          : (field?.area ?? 0) / 10000;
      rows.add(
        _RawSeasonCost(
          season: season,
          areaHa: areaHa,
          total: total,
          byCategory: byCategory,
        ),
      );
    }

    final populated = rows.where((row) => row.areaHa > 0 && row.total > 0);
    final totalArea = populated.fold<double>(0, (sum, row) => sum + row.areaHa);
    final totalCost = populated.fold<double>(0, (sum, row) => sum + row.total);
    final benchmarkPerHa = totalArea > 0 ? totalCost / totalArea : 0.0;

    return rows
        .map(
          (row) => FarmCostAlertRow(
            season: row.season,
            areaHa: row.areaHa,
            actualTotal: row.total,
            benchmarkTotal: benchmarkPerHa * row.areaHa,
            actualByCategory: Map.unmodifiable(row.byCategory),
          ),
        )
        .toList(growable: false);
  }
}

class FarmCostAlertRow {
  final ProductionSeasonModel season;
  final double areaHa;
  final double actualTotal;
  final double benchmarkTotal;
  final Map<ProductionCostCategory, double> actualByCategory;

  const FarmCostAlertRow({
    required this.season,
    required this.areaHa,
    required this.actualTotal,
    required this.benchmarkTotal,
    required this.actualByCategory,
  });

  double get variance => actualTotal - benchmarkTotal;
  double get actualPerHa => areaHa > 0 ? actualTotal / areaHa : 0;
  double get benchmarkPerHa => areaHa > 0 ? benchmarkTotal / areaHa : 0;
  bool get isOverBudget => variance > 0 && actualTotal > 0;
  bool get isCritical => benchmarkTotal > 0 && actualTotal >= benchmarkTotal * 1.2;
}

class _RawSeasonCost {
  final ProductionSeasonModel season;
  final double areaHa;
  final double total;
  final Map<ProductionCostCategory, double> byCategory;

  const _RawSeasonCost({
    required this.season,
    required this.areaHa,
    required this.total,
    required this.byCategory,
  });
}
