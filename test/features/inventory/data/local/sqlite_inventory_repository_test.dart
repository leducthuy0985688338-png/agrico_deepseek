import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late SqliteInventoryRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteInventoryRepository.createSchema(database);
    repository = SqliteInventoryRepository(database);
    await repository.register(
      const InventoryItem(
        id: 'item-1',
        farmId: 'farm-1',
        code: 'PB001',
        name: 'Phân bón',
        unit: 'kg',
        unitPrice: 20000,
        supplier: 'Nhà cung cấp A',
      ),
    );
  });
  tearDown(() => database.close());

  InventoryMovement movement(
    String id,
    InventoryMovementKind kind,
    int quantity, {
    String farmId = 'farm-1',
  }) => InventoryMovement(
    id: id,
    farmId: farmId,
    itemId: 'item-1',
    kind: kind,
    quantity: quantity,
    occurredAt: DateTime.utc(2026, 9, 29),
  );

  test('receipt and issue persist stock with an audit trail', () async {
    await repository.record(movement('in-1', InventoryMovementKind.receipt, 5));
    await repository.record(movement('out-1', InventoryMovementKind.issue, 2));
    final reopened = SqliteInventoryRepository(database);
    expect((await reopened.listByFarm('farm-1')).single.stock, 3);
    expect(
      (await reopened.movementsByFarm('farm-1')).map((event) => event.kind),
      [InventoryMovementKind.receipt, InventoryMovementKind.issue],
    );
    expect(await reopened.listByFarm('farm-2'), isEmpty);
  });

  test('cross-farm, insufficient stock and duplicate IDs roll back', () async {
    await expectLater(
      repository.record(
        movement('other', InventoryMovementKind.receipt, 1, farmId: 'farm-2'),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.record(movement('out', InventoryMovementKind.issue, 1)),
      throwsStateError,
    );
    await repository.record(movement('in-1', InventoryMovementKind.receipt, 2));
    await expectLater(
      repository.record(movement('in-1', InventoryMovementKind.receipt, 5)),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repository.listByFarm('farm-1')).single.stock, 2);
    expect(await repository.movementsByFarm('farm-1'), hasLength(1));
  });
}
