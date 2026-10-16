import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/presentation/inventory_catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates and reloads a farm inventory item', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    final repository = _Inventory();
    const subject = AuthorizationSubject(
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
    Widget screen() => MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: InventoryCatalogScreen(
        subject: subject,
        service: InventoryService(repository),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('inventory-code')), 'PB001');
    await tester.enterText(find.byKey(const Key('inventory-name')), 'Phân bón');
    await tester.enterText(find.byKey(const Key('inventory-unit')), 'kg');
    await tester.enterText(find.byKey(const Key('inventory-price')), '100');
    await tester.tap(find.byKey(const Key('inventory-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.stock, 0);
    Future<void> move(String kind, String amount) async {
      await tester.tap(
        find.byKey(Key('inventory-actions-${repository.saved.single.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('inventory-$kind-${repository.saved.single.id}')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inventory-movement-quantity')),
        amount,
      );
      await tester.tap(find.byKey(const Key('inventory-movement-save')));
      await tester.pumpAndSettle();
    }

    await move('receipt', '0');
    expect(find.byKey(const Key('inventory-movement-error')), findsOneWidget);
    expect(repository.movements, isEmpty);
    await tester.enterText(
      find.byKey(const Key('inventory-movement-quantity')),
      '5',
    );
    await tester.tap(find.byKey(const Key('inventory-movement-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.stock, 5);
    await move('issue', '2');
    expect(repository.saved.single.stock, 3);
    expect(repository.movements.length, 2);
    await move('issue', '4');
    expect(find.byKey(const Key('inventory-movement-error')), findsOneWidget);
    expect(repository.saved.single.stock, 3);
    expect(repository.movements.length, 2);
    final dialog = find.byType(AlertDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('PB001 · Phân bón'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('PB001 · Phân bón'), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(
      find.descendant(
        of: find.byWidget(tile.subtitle!),
        matching: find.textContaining('3 kg'),
      ),
      findsOneWidget,
    );
    await tester.binding.setSurfaceSize(null);
  });
}

class _Inventory implements InventoryRepository {
  final saved = <InventoryItem>[];
  final movements = <InventoryMovement>[];

  @override
  Future<void> register(InventoryItem item) async {
    saved.add(item);
  }

  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async =>
      saved.where((item) => item.farmId == farmId).toList();

  @override
  Future<void> record(InventoryMovement movement) async {
    final index = saved.indexWhere(
      (item) => item.id == movement.itemId && item.farmId == movement.farmId,
    );
    if (index < 0) {
      throw StateError('Missing item');
    }
    final item = saved[index];
    final stock =
        item.stock +
        (movement.kind == InventoryMovementKind.receipt
            ? movement.quantity
            : -movement.quantity);
    if (stock < 0) {
      throw StateError('Insufficient stock');
    }
    saved[index] = InventoryItem(
      id: item.id,
      farmId: item.farmId,
      code: item.code,
      name: item.name,
      unit: item.unit,
      unitPrice: item.unitPrice,
      supplier: item.supplier,
      stock: stock,
    );
    movements.add(movement);
  }

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async =>
      movements.where((movement) => movement.farmId == farmId).toList();
}
