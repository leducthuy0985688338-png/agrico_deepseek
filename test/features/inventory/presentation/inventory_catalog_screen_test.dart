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
    expect(find.text('PB001 · Phân bón'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('PB001 · Phân bón'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}

class _Inventory implements InventoryRepository {
  final saved = <InventoryItem>[];

  @override
  Future<void> register(InventoryItem item) async {
    saved.add(item);
  }

  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async =>
      saved.where((item) => item.farmId == farmId).toList();

  @override
  Future<void> record(InventoryMovement movement) async {}

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async => [];
}
