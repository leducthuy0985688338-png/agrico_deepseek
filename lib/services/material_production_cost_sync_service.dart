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
    if (fieldId.trim().isEmpty || quantity <= 0) return null;
    if (!quantity.isFinite || !unitPrice.isFinite || unitPrice < 0) {
      throw const FormatException('Invalid material cost quantity or unit price.');
    }
    if (transactionId.trim().isEmpty || itemId.trim().isEmpty ||
        itemName.trim().isEmpty || unit.trim().isEmpty) {
      throw const FormatException('Material cost source and item are required.');
    }

    // A delivered movement is immutable for cost purposes. A retry must not
    // overwrite the original price, destination, date or quantity.
    final existing = await _costDatabase.getBySource('material', transactionId);
    if (existing != null) return existing;

    final resolvedSeasonId = (seasonId == null || seasonId.isEmpty)
        ? (await _seasonDatabase.getLatestByField(fieldId))?.id
        : seasonId;
    if (resolvedSeasonId == null || resolvedSeasonId.isEmpty) return null;

    final record = ProductionCostModel(
      id: 'MATERIAL-COST-$transactionId',
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
    // Another delivery can win the unique source constraint while this one
    // waits for SQLite. Always return the persisted winner.
    return await _costDatabase.getBySource('material', transactionId) ?? record;
  }
}
