import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/operation_scope.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/warehouse_repository.dart';
import 'package:agrico_deepseek/features/inventory/presentation/inventory_catalog_screen.dart';

class Warehouses implements InventoryRepository, WarehouseRepository {
  final requested = <String>[];
  InventoryItem item(String id) => InventoryItem(
    id: 'item',
    farmId: 'f',
    code: 'VT-001',
    name: 'Phân bón',
    unit: 'kg',
    unitPrice: 0,
    supplier: '',
    stock: id == 'a' ? 10 : 20,
  );
  @override
  InventoryRepository inWarehouse(OperationScope scope, String warehouseId) =>
      WarehouseStock(this, scope, warehouseId);
  @override
  Future<List<InventoryWarehouse>> warehouses(
    String farmId,
    OperationScope scope,
  ) async =>
      [
            const InventoryWarehouse('a', 'KHO-001', 'Kho A'),
            const InventoryWarehouse('b', 'KHO-002', 'Kho B'),
          ]
          .where(
            (w) => scope.allows(
              ResourceContext(farmId: farmId, warehouseId: w.id),
            ),
          )
          .toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class WarehouseStock implements InventoryRepository {
  WarehouseStock(this.owner, this.scope, this.id);
  final Warehouses owner;
  final OperationScope scope;
  final String id;
  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async {
    scope.require(ResourceContext(farmId: farmId, warehouseId: id));
    owner.requested.add(id);
    return [owner.item(id)];
  }

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async {
    scope.require(ResourceContext(farmId: farmId, warehouseId: id));
    owner.requested.add('history:$id');
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget app(AuthorizationSubject subject, Warehouses repository) =>
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: InventoryCatalogScreen(
          subject: subject,
          service: InventoryService(repository, currentSubject: () => subject),
        ),
      );
  testWidgets(
    'Admin switches warehouse balances and history keeps the chosen warehouse',
    (tester) async {
      final repo = Warehouses();
      const admin = AuthorizationSubject(
        userId: 'u',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: {DataScope.allFarm},
      );
      await tester.pumpWidget(app(admin, repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 kg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('warehouse-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KHO-002 · Kho B').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('20 kg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory-history-open')));
      await tester.pumpAndSettle();
      expect(repo.requested, contains('history:b'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'warehouse keeper sees only the assigned warehouse and no price or export actions',
    (tester) async {
      final repo = Warehouses();
      const keeper = AuthorizationSubject(
        userId: 'u',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: {
          PermissionCodes.inventoryView,
          PermissionCodes.inventoryReceive,
        },
        dataScopes: {DataScope.assignedWarehouses},
        assignedWarehouseIds: {'a'},
      );
      await tester.pumpWidget(app(keeper, repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 kg'), findsOneWidget);
      expect(find.byKey(const Key('warehouse-create')), findsNothing);
      expect(
        find.byKey(const Key('inventory-direct-receipt-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('inventory-direct-issue-item')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('warehouse-selector')));
      await tester.pumpAndSettle();
      expect(find.text('KHO-002 · Kho B'), findsNothing);
      await tester.tap(find.text('KHO-001 · Kho A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inventory-history-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory-history-export')), findsNothing);
      expect(
        repo.requested.every((id) => id == 'a' || id == 'history:a'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
