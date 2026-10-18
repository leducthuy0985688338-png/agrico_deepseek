import '../../../services/material_production_cost_sync_service.dart';
import '../data/local/sqlite_inventory_repository.dart';

/// Replays committed production issues into the separate cost database.
/// A failed delivery remains pending. Repeated deliveries use the stable
/// movement ID and the cost database's unique source constraint.
class InventoryCostReconciler {
  const InventoryCostReconciler({
    required this.inventory,
    required this.costs,
  });

  final SqliteInventoryRepository inventory;
  final MaterialProductionCostSyncService costs;

  /// Returns the number of acknowledged intents. Throws on delivery failure;
  /// remaining intents are available for the next retry.
  Future<int> reconcile(String farmId) async {
    if (farmId.trim().isEmpty) {
      throw const FormatException('Farm is required.');
    }
    final pending = await inventory.pendingProductionCosts(farmId);
    var acknowledged = 0;
    for (final row in pending) {
      final movementId = row['movement_id']! as String;
      final result = await costs.syncExport(
        transactionId: movementId,
        itemId: row['item_id']! as String,
        itemName: row['item_name']! as String,
        unit: row['unit']! as String,
        quantity: (row['quantity']! as num).toDouble(),
        unitPrice: (row['unit_price']! as num).toDouble(),
        fieldId: row['field_id']! as String,
        seasonId: row['season_id']! as String,
        date: DateTime.parse(row['occurred_at']! as String),
      );
      if (result == null) {
        throw StateError('Production cost could not be persisted for $movementId.');
      }
      await inventory.acknowledgeProductionCost(farmId, movementId);
      acknowledged++;
    }
    return acknowledged;
  }
}
