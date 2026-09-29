import '../entities/inventory_item.dart';

abstract interface class InventoryRepository {
  Future<void> register(InventoryItem item);
  Future<List<InventoryItem>> listByFarm(String farmId);
  Future<void> record(InventoryMovement movement);
  Future<List<InventoryMovement>> movementsByFarm(String farmId);
}
