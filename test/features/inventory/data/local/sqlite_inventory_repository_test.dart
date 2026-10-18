import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_monthly_document_sequence.dart';
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

  test('registering an existing projected item updates metadata without resetting stock', () async {
    await repository.record(movement('in-before-register', InventoryMovementKind.receipt, 7));
    await repository.register(
      const InventoryItem(
        id: 'item-1',
        farmId: 'farm-1',
        code: 'PB001',
        name: 'Phân bón',
        unit: 'kg',
        unitPrice: 25000,
        supplier: 'Nhà cung cấp B',
      ),
    );
    final item = (await repository.listByFarm('farm-1')).single;
    expect(item.stock, 7);
    expect(item.unitPrice, 25000);
    expect(item.supplier, 'Nhà cung cấp B');
    expect(await repository.movementsByFarm('farm-1'), hasLength(1));
    await expectLater(
      repository.register(
        const InventoryItem(
          id: 'item-1',
          farmId: 'farm-1',
          code: 'OTHER',
          name: 'Wrong identity',
          unit: 'kg',
          unitPrice: 1,
          supplier: '',
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repository.listByFarm('farm-1')).single.stock, 7);
  });

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
  test(
    'codes use Laos month and independent receipt issue sequences',
    () async {
      InventoryMovement event(
        String id,
        DateTime at, [
        InventoryMovementKind kind = InventoryMovementKind.receipt,
      ]) => InventoryMovement(
        id: id,
        farmId: 'farm-1',
        itemId: 'item-1',
        kind: kind,
        quantity: 1,
        occurredAt: at,
      );
      await repository.record(event('sep', DateTime.utc(2026, 9, 30, 16, 59)));
      await repository.record(event('oct', DateTime.utc(2026, 9, 30, 17)));
      await repository.record(event('oct-2', DateTime.utc(2026, 10, 1)));
      await repository.record(
        event(
          'issue',
          DateTime.utc(2026, 10, 1, 1),
          InventoryMovementKind.issue,
        ),
      );
      expect((await repository.movementsByFarm('farm-1')).map((e) => e.code), [
        'NHAP-202609-001',
        'NHAP-202610-001',
        'NHAP-202610-002',
        'XUAT-202610-001',
      ]);
      await repository.register(
        const InventoryItem(
          id: 'item-2',
          farmId: 'farm-2',
          code: 'PB001',
          name: 'Other farm',
          unit: 'kg',
          unitPrice: 0,
          supplier: '',
        ),
      );
      await repository.record(
        InventoryMovement(
          id: 'farm-2-receipt',
          farmId: 'farm-2',
          itemId: 'item-2',
          kind: InventoryMovementKind.receipt,
          quantity: 1,
          occurredAt: DateTime.utc(2026, 10, 1),
        ),
      );
      expect(
        (await repository.movementsByFarm('farm-2')).single.code,
        'NHAP-202610-001',
      );
    },
  );

  test(
    'failed insertion does not consume a code and overflow rolls back stock',
    () async {
      await repository.record(
        movement('first', InventoryMovementKind.receipt, 1),
      );
      await expectLater(
        repository.record(movement('first', InventoryMovementKind.receipt, 5)),
        throwsA(isA<DatabaseException>()),
      );
      await repository.record(
        movement('second', InventoryMovementKind.receipt, 1),
      );
      expect((await repository.movementsByFarm('farm-1')).map((e) => e.code), [
        'NHAP-202609-001',
        'NHAP-202609-002',
      ]);
      await database.update(
        SqliteMonthlyDocumentSequence.table,
        {'last_sequence': 999},
        where: 'organization_id=? AND kind=? AND year_month=?',
        whereArgs: ['farm-1', 'NHAP', '202609'],
      );
      await expectLater(
        repository.record(
          movement('overflow', InventoryMovementKind.receipt, 1),
        ),
        throwsA(isA<FormatException>()),
      );
      expect((await repository.listByFarm('farm-1')).single.stock, 2);
      expect(await repository.movementsByFarm('farm-1'), hasLength(2));
    },
  );

  test(
    'clean schema initialization is idempotent and numbering persists',
    () async {
      await SqliteInventoryRepository.createSchema(database);
      await repository.record(
        movement('first', InventoryMovementKind.receipt, 2),
      );
      await SqliteInventoryRepository.createSchema(database);
      await SqliteInventoryRepository.createSchema(database);
      await repository.record(
        movement('second', InventoryMovementKind.receipt, 1),
      );
      expect((await repository.movementsByFarm('farm-1')).map((e) => e.code), [
        'NHAP-202609-001',
        'NHAP-202609-002',
      ]);
      expect((await repository.listByFarm('farm-1')).single.stock, 3);
    },
  );
}
