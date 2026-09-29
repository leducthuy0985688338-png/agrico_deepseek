import '../../../core/permissions/authorization.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/repositories/inventory_repository.dart';

class InventoryService {
  const InventoryService(this.repository);

  final InventoryRepository repository;

  void _authorize(AuthorizationSubject subject, String permission) {
    if (!subject.dataScopes.contains(DataScope.allFarm) ||
        !const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: subject.farmId),
        )) {
      throw StateError('Inventory requires farm-wide access.');
    }
  }

  Future<List<InventoryItem>> list(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.listByFarm(subject.farmId);
  }

  Future<List<InventoryMovement>> movements(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.movementsByFarm(subject.farmId);
  }

  Future<void> register(AuthorizationSubject subject, InventoryItem item) {
    _authorize(subject, PermissionCodes.inventoryManage);
    if (item.farmId != subject.farmId) {
      throw StateError('Item is outside the current farm.');
    }
    item.validate();
    return repository.register(item);
  }

  Future<void> record(
    AuthorizationSubject subject,
    InventoryMovement movement,
  ) {
    _authorize(subject, PermissionCodes.inventoryManage);
    if (movement.farmId != subject.farmId) {
      throw StateError('Movement is outside the current farm.');
    }
    movement.validate();
    return repository.record(movement);
  }
}
