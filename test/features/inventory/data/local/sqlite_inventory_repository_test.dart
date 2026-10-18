import 'package:agrico_deepseek/features/inventory/data/local/sqlite_inventory_repository.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
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
    await database.execute('CREATE TABLE fields (id TEXT PRIMARY KEY)');
    await database.execute('CREATE TABLE production_seasons (id TEXT PRIMARY KEY, field_id TEXT NOT NULL)');
    await database.insert('fields', {'id': 'field-1'});
    await database.insert('production_seasons', {
      'id': 'season-1',
      'field_id': 'field-1',
    });

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

  test('production issue atomically creates immutable cost intent', () async {
    await repository.record(movement('receipt', InventoryMovementKind.receipt, 10));
    await expectLater(
      repository.recordProductionIssue(
        movement('invalid-destination', InventoryMovementKind.issue, 2),
        fieldId: 'field-1',
        seasonId: 'unknown-season',
      ),
      throwsA(isA<StateError>()),
    );
    expect((await repository.listByFarm('farm-1')).single.stock, 10);
    expect(await repository.pendingProductionCosts('farm-1'), isEmpty);
    await repository.recordProductionIssue(
      movement('production-issue', InventoryMovementKind.issue, 4),
      fieldId: 'field-1',
      seasonId: 'season-1',
    );
    final intents = await repository.pendingProductionCosts('farm-1');
    expect(intents, hasLength(1));
    expect(intents.single['movement_id'], 'production-issue');
    expect(intents.single['quantity'], 4);
    expect(intents.single['unit_price'], 20000);
    expect(intents.single['field_id'], 'field-1');
    expect((await repository.listByFarm('farm-1')).single.stock, 6);

    await expectLater(
      repository.recordProductionIssue(
        movement('failed-issue', InventoryMovementKind.issue, 7),
        fieldId: 'field-1',
        seasonId: 'season-1',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await repository.pendingProductionCosts('farm-1'), hasLength(1));
    expect((await repository.listByFarm('farm-1')).single.stock, 6);

    await repository.acknowledgeProductionCost('farm-1', 'production-issue');
    expect(await repository.pendingProductionCosts('farm-1'), isEmpty);
    expect(await database.query(SqliteInventoryRepository.costOutboxTable),
        hasLength(1));
  });

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

  test('shared-catalog material registration reuses its projected inventory identity', () async {
    await SqliteCompanyCatalog.createSchema(database);
    await database.insert(SqliteCompanyCatalog.entriesTable, {
      'id': 'unit-kg', 'farm_id': 'farm-1', 'kind': 'unit',
      'code': 'DVT-000001', 'name': 'kg', 'name_key': 'KG',
      'unit_id': null, 'active': 1, 'revision': 1,
    });
    await database.insert(SqliteCompanyCatalog.entriesTable, {
      'id': 'material-1', 'farm_id': 'farm-1', 'kind': 'material',
      'code': 'VT-000001', 'name': 'Vật tư A', 'name_key': 'VẬT TƯ A',
      'unit_id': 'unit-kg', 'active': 1, 'revision': 1,
    });
    await database.insert(SqliteInventoryRepository.itemsTable, {
      'id': 'material-1', 'farm_id': 'farm-1',
      'code': 'VT-000001', 'name': 'Vật tư A', 'unit': 'kg',
      'unit_price': 0, 'supplier': '', 'stock': 0,
    });
    const material = InventoryItem(
      id: 'material-1', farmId: 'farm-1', code: 'VT-000001',
      name: 'Vật tư A', unit: 'kg', unitPrice: 120, supplier: 'NCC',
    );
    await repository.register(material);
    await repository.record(InventoryMovement(
      id: 'material-receipt', farmId: 'farm-1', itemId: 'material-1',
      kind: InventoryMovementKind.receipt, quantity: 3,
      occurredAt: DateTime.utc(2026, 10, 18),
    ));
    await repository.register(material);
    final rows = await database.query(SqliteInventoryRepository.itemsTable,
        where: 'id=?', whereArgs: ['material-1']);
    expect(rows, hasLength(1));
    expect(rows.single['stock'], 3);
    expect(rows.single['unit_price'], 120.0);
    expect(await repository.movementsByFarm('farm-1'), hasLength(1));
    await expectLater(repository.register(const InventoryItem(
      id: 'unknown', farmId: 'farm-1', code: 'VT-999999',
      name: 'Unknown', unit: 'kg', unitPrice: 0, supplier: '',
    )), throwsA(isA<Exception>()));
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
