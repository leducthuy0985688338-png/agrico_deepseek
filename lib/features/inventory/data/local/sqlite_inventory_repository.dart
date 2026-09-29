import 'package:sqflite/sqflite.dart';

import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';

class SqliteInventoryRepository implements InventoryRepository {
  const SqliteInventoryRepository(this.database);

  final Database database;
  static const itemsTable = 'inventory_items_v2';
  static const movementsTable = 'inventory_movements_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $itemsTable (
      id TEXT PRIMARY KEY,
      farm_id TEXT NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      unit TEXT NOT NULL,
      unit_price REAL NOT NULL CHECK(unit_price >= 0),
      supplier TEXT NOT NULL,
      stock INTEGER NOT NULL DEFAULT 0 CHECK(stock >= 0),
      UNIQUE(farm_id, code)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $movementsTable (
      id TEXT PRIMARY KEY,
      farm_id TEXT NOT NULL,
      item_id TEXT NOT NULL REFERENCES $itemsTable(id) ON DELETE RESTRICT,
      kind TEXT NOT NULL CHECK(kind IN ('receipt', 'issue')),
      quantity INTEGER NOT NULL CHECK(quantity > 0),
      occurred_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_items_v2_farm '
      'ON $itemsTable(farm_id, code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movements_v2_farm '
      'ON $movementsTable(farm_id, occurred_at, id)',
    );
  }

  @override
  Future<void> register(InventoryItem item) async {
    item.validate();
    if (item.stock != 0) {
      throw const FormatException('Opening stock requires a receipt.');
    }
    await database.insert(itemsTable, {
      'id': item.id,
      'farm_id': item.farmId,
      'code': item.code,
      'name': item.name,
      'unit': item.unit,
      'unit_price': item.unitPrice,
      'supplier': item.supplier,
      'stock': item.stock,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async {
    final rows = await database.query(
      itemsTable,
      where: 'farm_id = ?',
      whereArgs: [farmId],
      orderBy: 'code, id',
    );
    return List.unmodifiable(
      rows.map(
        (row) => InventoryItem(
          id: row['id']! as String,
          farmId: row['farm_id']! as String,
          code: row['code']! as String,
          name: row['name']! as String,
          unit: row['unit']! as String,
          unitPrice: (row['unit_price']! as num).toDouble(),
          supplier: row['supplier']! as String,
          stock: row['stock']! as int,
        ),
      ),
    );
  }

  @override
  Future<void> record(InventoryMovement movement) async {
    movement.validate();
    await database.transaction((tx) async {
      final delta = movement.kind == InventoryMovementKind.receipt
          ? movement.quantity
          : -movement.quantity;
      final changed = await tx.rawUpdate(
        'UPDATE $itemsTable SET stock = stock + ? '
        'WHERE id = ? AND farm_id = ? AND stock + ? >= 0',
        [delta, movement.itemId, movement.farmId, delta],
      );
      if (changed != 1) {
        throw StateError(
          'Item is missing or stock is insufficient in this farm.',
        );
      }
      await tx.insert(movementsTable, {
        'id': movement.id,
        'farm_id': movement.farmId,
        'item_id': movement.itemId,
        'kind': movement.kind.name,
        'quantity': movement.quantity,
        'occurred_at': movement.occurredAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async {
    final rows = await database.query(
      movementsTable,
      where: 'farm_id = ?',
      whereArgs: [farmId],
      orderBy: 'occurred_at, id',
    );
    return List.unmodifiable(
      rows.map(
        (row) => InventoryMovement(
          id: row['id']! as String,
          farmId: row['farm_id']! as String,
          itemId: row['item_id']! as String,
          kind: InventoryMovementKind.values.byName(row['kind']! as String),
          quantity: row['quantity']! as int,
          occurredAt: DateTime.parse(row['occurred_at']! as String),
        ),
      ),
    );
  }
}
