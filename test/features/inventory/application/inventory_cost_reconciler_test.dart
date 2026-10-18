import 'package:agrico_deepseek/features/inventory/application/inventory_cost_reconciler.dart';
import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/material_production_cost_sync_service.dart';
import 'package:agrico_deepseek/services/production_cost_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryCosts extends ProductionCostDatabase {
  final Map<String, ProductionCostModel> records = {};
  int writes = 0;

  @override
  Future<ProductionCostModel?> getBySource(String source, String sourceId) async =>
      records['$source:$sourceId'];

  @override
  Future<void> upsert(ProductionCostModel record) async {
    writes++;
    records.putIfAbsent('${record.source}:${record.sourceId}', () => record);
  }
}

void main() {
  sqfliteFfiInit();
  test('reconcile writes once and acknowledges committed production issue', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await SqliteInventoryRepository.createSchema(db);
      final inventory = SqliteInventoryRepository(db);
      await inventory.register(const InventoryItem(
        id: 'material', farmId: 'farm', code: 'VT001',
        name: 'Fertilizer', unit: 'kg', unitPrice: 25, supplier: '',
      ));
      InventoryMovement movement(String id, InventoryMovementKind kind, int quantity) =>
          InventoryMovement(
            id: id, farmId: 'farm', itemId: 'material',
            kind: kind, quantity: quantity,
            occurredAt: DateTime.utc(2026, 10, 18),
          );
      await inventory.record(movement('receipt', InventoryMovementKind.receipt, 10));
      await inventory.recordProductionIssue(
        movement('issue', InventoryMovementKind.issue, 4),
        fieldId: 'field', seasonId: 'season',
      );
      final costs = _MemoryCosts();
      final reconciler = InventoryCostReconciler(
        inventory: inventory,
        costs: MaterialProductionCostSyncService(costDatabase: costs),
      );
      expect(await reconciler.reconcile('farm'), 1);
      expect(costs.records['material:issue']?.amount, 100);
      expect(await inventory.pendingProductionCosts('farm'), isEmpty);
      expect(await reconciler.reconcile('farm'), 0);
      expect(costs.writes, 1);

      // Simulate a crash after posting the cost but before acknowledgement.
      await db.update(SqliteInventoryRepository.costOutboxTable,
          {'delivered': 0}, where: 'movement_id=?', whereArgs: ['issue']);
      expect(await reconciler.reconcile('farm'), 1);
      expect(costs.writes, 1);
      expect(await inventory.pendingProductionCosts('farm'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
