import '../models/fuel_model.dart';
import '../models/production_cost_model.dart';
import 'production_cost_database.dart';
import 'production_season_database.dart';

/// Bridges fuel issues to the production-cost ledger.
///
/// A fuel transaction is only a production cost when it is an XUAT linked to
/// a field. The source/sourceId pair makes the operation idempotent.
class FuelProductionCostSyncService {
  final ProductionCostDatabase _costDatabase;
  final ProductionSeasonDatabase _seasonDatabase;

  FuelProductionCostSyncService({
    ProductionCostDatabase? costDatabase,
    ProductionSeasonDatabase? seasonDatabase,
  })  : _costDatabase = costDatabase ?? ProductionCostDatabase(),
        _seasonDatabase = seasonDatabase ?? ProductionSeasonDatabase();

  Future<ProductionCostModel?> sync(FuelTransaction transaction) async {
    if (transaction.type != TransactionType.XUAT) return null;
    final fieldId = transaction.fieldId;
    if (fieldId == null || fieldId.isEmpty) return null;

    final existing = await _costDatabase.getBySource('fuel', transaction.id);
    var seasonId = transaction.seasonId;
    if (seasonId == null || seasonId.isEmpty) {
      final season = await _seasonDatabase.getLatestByField(fieldId);
      seasonId = season?.id;
    }
    if (seasonId == null || seasonId.isEmpty) return null;

    final unitPrice = transaction.price ?? 0;
    final record = ProductionCostModel(
      id: existing?.id ?? 'FUEL-COST-${transaction.id}',
      fieldId: fieldId,
      seasonId: seasonId,
      category: ProductionCostCategory.fuel,
      date: transaction.date,
      itemName: transaction.fuelName,
      quantity: transaction.quantity,
      unit: 'Lít',
      unitPrice: unitPrice,
      amount: transaction.quantity * unitPrice,
      machineId: transaction.machineId,
      notes: transaction.note ?? 'Xuất nhiên liệu cho sản xuất',
      source: 'fuel',
      sourceId: transaction.id,
    );

    await _costDatabase.upsert(record);
    return record;
  }
}
