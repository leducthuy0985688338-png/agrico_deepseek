import '../models/production_cost_model.dart';
import 'production_cost_database.dart';
import 'production_season_database.dart';

/// Converts a warehouse material issue into a production-cost record.
/// The source/sourceId pair keeps the operation idempotent.
class MaterialProductionCostSyncService {
  final ProductionCostDatabase _costDatabase;
  final ProductionSeasonDatabase _seasonDatabase;

  MaterialProductionCostSyncService({
    ProductionCostDatabase? costDatabase,
    ProductionSeasonDatabase? seasonDatabase,
  })  : _costDatabase = costDatabase ?? ProductionCostDatabase(),
        _seasonDatabase = seasonDatabase ?? ProductionSeasonDatabase();

  Future<ProductionCostModel?> syncExport({
    required String transactionId,
    required String itemId,
    required String itemName,
    required String unit,
    required double quantity,
    required double unitPrice,
    required String fieldId,
    String? seasonId,
    DateTime? date,
    String? notes,
  }) async {
    if (fieldId.isEmpty || quantity <= 0) return null;

    final resolvedSeasonId = (seasonId == null || seasonId.isEmpty)
        ? (await _seasonDatabase.getLatestByField(fieldId))?.id
        : seasonId;
    if (resolvedSeasonId == null || resolvedSeasonId.isEmpty) return null;

    final existing = await _costDatabase.getBySource('material', transactionId);
    final record = ProductionCostModel(
      id: existing?.id ?? 'MATERIAL-COST-$transactionId',
      fieldId: fieldId,
      seasonId: resolvedSeasonId,
      category: ProductionCostCategory.material,
      date: date ?? DateTime.now(),
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      unitPrice: unitPrice,
      amount: quantity * unitPrice,
      notes: notes ?? 'Xuất vật tư cho sản xuất',
      source: 'material',
      sourceId: transactionId,
    );

    await _costDatabase.upsert(record);
    return record;
  }
}
