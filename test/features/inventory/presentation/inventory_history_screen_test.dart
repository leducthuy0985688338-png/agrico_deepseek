import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/presentation/inventory_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history shows newest first, codes, Lao time and refreshes', (
    tester,
  ) async {
    final repository = _History();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: InventoryHistoryScreen(
          subject: const AuthorizationSubject(
            userId: 'user',
            membershipId: 'member',
            farmId: 'farm-1',
            permissionCodes: {PermissionCodes.inventoryView},
            dataScopes: {DataScope.allFarm},
          ),
          service: InventoryService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NK-202610-001'), findsOneWidget);
    expect(find.textContaining('ຝຸ່ນ'), findsNWidgets(2));
    expect(find.textContaining('01/10/2026 00:00 (UTC+7)'), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.first.key, const Key('inventory-history-new'));
    expect(tiles.last.key, const Key('inventory-history-old'));
    repository.events.clear();
    await tester.tap(find.byKey(const Key('inventory-history-refresh')));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(repository.farms, everyElement('farm-1'));
  });
}

class _History implements InventoryRepository {
  final farms = <String>[];
  final events = [
    InventoryMovement(
      id: 'old',
      farmId: 'farm-1',
      itemId: 'item',
      kind: InventoryMovementKind.receipt,
      quantity: 5,
      occurredAt: DateTime.utc(2026, 9, 29),
    ),
    InventoryMovement(
      id: 'new',
      farmId: 'farm-1',
      itemId: 'item',
      code: 'NK-202610-001',
      kind: InventoryMovementKind.receipt,
      quantity: 2,
      occurredAt: DateTime.utc(2026, 9, 30, 17),
    ),
  ];
  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async {
    farms.add(farmId);
    return const [
      InventoryItem(
        id: 'item',
        farmId: 'farm-1',
        code: 'PB001',
        name: 'ຝຸ່ນ',
        unit: 'kg',
        unitPrice: 100,
        supplier: '',
        stock: 7,
      ),
    ];
  }

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async {
    farms.add(farmId);
    return [...events];
  }

  @override
  Future<void> record(InventoryMovement movement) async =>
      throw UnimplementedError();
  @override
  Future<void> register(InventoryItem item) async => throw UnimplementedError();
}
