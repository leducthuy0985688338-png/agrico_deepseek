import '../../../../core/permissions/operation_scope.dart';
import 'inventory_repository.dart';

class InventoryWarehouse {
  const InventoryWarehouse(this.id, this.code, this.name, {this.active = true});
  final String id, code, name;
  final bool active;
  static String defaultId(String farm) => 'warehouse:default:$farm';
}

abstract interface class WarehouseRepository {
  InventoryRepository inWarehouse(OperationScope scope, String warehouseId);
  Future<List<InventoryWarehouse>> warehouses(
    String farmId,
    OperationScope scope,
  );
  Future<void> createWarehouse(
    String farmId,
    String id,
    String name,
    String actorId,
  );
  Future<void> transfer(
    String farmId,
    String id,
    String itemId,
    String sourceId,
    String destinationId,
    num quantity,
    DateTime at,
    String actorId,
    OperationScope scope,
  );
}
