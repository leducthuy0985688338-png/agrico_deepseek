import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manager = AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm-1',
    permissionCodes: {
      PermissionCodes.inventoryView,
      PermissionCodes.inventoryManage,
      PermissionCodes.catalogManage,
    },
    dataScopes: {DataScope.allFarm},
  );
  const viewer = AuthorizationSubject(
    userId: 'viewer',
    membershipId: 'member',
    farmId: 'farm-1',
    permissionCodes: {PermissionCodes.inventoryView},
    dataScopes: {DataScope.allFarm},
  );
  const item = InventoryItem(
    id: 'item-1',
    farmId: 'farm-1',
    code: 'PB001',
    name: 'Phân bón',
    unit: 'kg',
    unitPrice: 100,
    supplier: 'A',
  );

  test(
    'stock movement permission does not grant master catalog registration',
    () {
      final repository = _Inventory();
      const stockManager = AuthorizationSubject(
        userId: 'stock',
        membershipId: 'stock',
        farmId: 'farm-1',
        permissionCodes: {
          PermissionCodes.inventoryView,
          PermissionCodes.inventoryManage,
        },
        dataScopes: {DataScope.allFarm},
      );
      expect(
        () => InventoryService(repository).register(stockManager, item),
        throwsStateError,
      );
      expect(repository.items, isEmpty);
    },
  );

  test('reads by farm and rejects unauthorized or cross-farm writes', () async {
    final repository = _Inventory();
    final service = InventoryService(repository);
    await service.register(manager, item);
    expect(await service.list(viewer), [item]);
    expect(() => service.register(viewer, item), throwsStateError);
    expect(
      () => service.register(
        manager,
        const InventoryItem(
          id: 'other',
          farmId: 'farm-2',
          code: 'PB002',
          name: 'Other',
          unit: 'kg',
          unitPrice: 100,
          supplier: 'B',
        ),
      ),
      throwsStateError,
    );
    const limited = AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.inventoryView},
      dataScopes: {DataScope.assignedFields},
    );
    expect(() => service.list(limited), throwsStateError);
    expect(repository.items, hasLength(1));
  });
}

class _Inventory implements InventoryRepository {
  final items = <InventoryItem>[];

  @override
  Future<void> register(InventoryItem item) async {
    items.add(item);
  }

  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async =>
      items.where((item) => item.farmId == farmId).toList();

  @override
  Future<void> record(InventoryMovement movement) async {}

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async => [];
}
