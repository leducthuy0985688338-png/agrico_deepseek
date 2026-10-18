import 'package:sqflite/sqflite.dart';

import '../../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../../core/identity/domain/business_reference_code.dart';

import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../../../core/catalog/sqlite_company_catalog.dart';
import '../../../../core/catalog/company_catalog.dart';

class SqliteInventoryRepository implements InventoryRepository {
  const SqliteInventoryRepository(this.database);

  final Database database;
  static const itemsTable = 'inventory_items_v2';
  static const movementsTable = 'inventory_movements_v2';
  static const costOutboxTable = 'inventory_cost_outbox_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteMonthlyDocumentSequence.createSchema(db);
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
      occurred_at TEXT NOT NULL,
      code TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $costOutboxTable (
      movement_id TEXT PRIMARY KEY REFERENCES $movementsTable(id) ON DELETE RESTRICT,
      farm_id TEXT NOT NULL,
      item_id TEXT NOT NULL,
      field_id TEXT NOT NULL,
      season_id TEXT NOT NULL,
      item_name TEXT NOT NULL,
      unit TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK(quantity > 0),
      unit_price REAL NOT NULL CHECK(unit_price >= 0),
      occurred_at TEXT NOT NULL,
      delivered INTEGER NOT NULL DEFAULT 0 CHECK(delivered IN (0, 1))
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_cost_outbox_pending '
      'ON $costOutboxTable(farm_id, delivered, occurred_at)',
    );
    final columns = await db.rawQuery('PRAGMA table_info($movementsTable)');
    if (!columns.any((column) => column['name'] == 'code')) {
      await db.execute('ALTER TABLE $movementsTable ADD COLUMN code TEXT');
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_movements_v2_code '
      'ON $movementsTable(farm_id, code) WHERE code IS NOT NULL',
    );
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
    await database.transaction((tx) async {
      if (await SqliteCompanyCatalog.hasTable(
        tx,
        SqliteCompanyCatalog.entriesTable,
      )) {
        final unit = await tx.query(
          SqliteCompanyCatalog.entriesTable,
          where: 'farm_id=? AND kind=? AND name=? AND active=1',
          whereArgs: [item.farmId, CatalogKind.unit.name, item.unit],
        );
        if (unit.isEmpty) throw const CatalogFailure('catalog.unitRequired');
        final existing = await tx.query(
          SqliteCompanyCatalog.entriesTable,
          where:
              'id=? AND farm_id=? AND kind=? AND code=? AND name=? AND unit_id=? AND active=1',
          whereArgs: [
            item.id,
            item.farmId,
            CatalogKind.material.name,
            item.code,
            item.name,
            unit.single['id'],
          ],
        );
        if (existing.isEmpty) {
          throw const CatalogFailure('catalog.invalidSelection');
        }
      }
      // The shared catalog projects a zero-stock inventory row when a material
      // is created. Registration configures that same row, never inserts a
      // second identity or resets stock and movement history.
      final projected = await tx.query(
        itemsTable,
        where: 'id=? AND farm_id=? AND code=? AND name=? AND unit=?',
        whereArgs: [item.id, item.farmId, item.code, item.name, item.unit],
        limit: 1,
      );
      if (projected.isNotEmpty) {
        await tx.update(
          itemsTable,
          {'unit_price': item.unitPrice, 'supplier': item.supplier},
          where: 'id=? AND farm_id=?',
          whereArgs: [item.id, item.farmId],
        );
      } else {
        await tx.insert(itemsTable, {
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
    });
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

  /// An issue intended for production. Stock and its immutable cost intent
  /// are committed in the same database transaction. Delivery to the separate
  /// cost database is intentionally performed by a later reconciler.
  Future<void> recordProductionIssue(
    InventoryMovement movement, {
    required String fieldId,
    required String seasonId,
  }) async {
    if (movement.kind != InventoryMovementKind.issue ||
        fieldId.trim().isEmpty || seasonId.trim().isEmpty) {
      throw const FormatException('Production issue requires a field and season.');
    }
    await _record(movement, fieldId: fieldId, seasonId: seasonId);
  }

  @override
  Future<void> record(InventoryMovement movement) => _record(movement);

  Future<void> _record(
    InventoryMovement movement, {
    String? fieldId,
    String? seasonId,
  }) async {
    movement.validate();
    if (movement.code != null) {
      throw const FormatException('Movement codes are assigned by SQLite.');
    }
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
      final costItem = fieldId == null
          ? null
          : (await tx.query(
              itemsTable,
              columns: ['name', 'unit', 'unit_price'],
              where: 'id=? AND farm_id=?',
              whereArgs: [movement.itemId, movement.farmId],
              limit: 1,
            )).single;
      // Laos business month (UTC+7), independent of the device timezone.
      final date = movement.occurredAt.toUtc().add(const Duration(hours: 7));
      final kind = movement.kind == InventoryMovementKind.receipt
          ? BusinessDocumentKind.stockIn
          : BusinessDocumentKind.stockOut;
      await SqliteMonthlyDocumentSequence().saveWithCode(
        transaction: tx,
        // Farm is the existing inventory authorization boundary. In v2,
        // organization identity must be mapped explicitly before broadening scope.
        organizationId: movement.farmId,
        kind: kind,
        documentDate: date,
        save: (code) => tx.insert(movementsTable, {
          'id': movement.id,
          'code': code,
          'farm_id': movement.farmId,
          'item_id': movement.itemId,
          'kind': movement.kind.name,
          'quantity': movement.quantity,
          'occurred_at': movement.occurredAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort),
      );
      if (costItem != null) {
        await tx.insert(costOutboxTable, {
          'movement_id': movement.id,
          'farm_id': movement.farmId,
          'item_id': movement.itemId,
          'field_id': fieldId,
          'season_id': seasonId,
          'item_name': costItem['name'],
          'unit': costItem['unit'],
          'quantity': movement.quantity,
          'unit_price': costItem['unit_price'],
          'occurred_at': movement.occurredAt.toIso8601String(),
          'delivered': 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });
  }

  /// Read-only pending intents; the consumer must acknowledge only after
  /// the cost record is durably persisted.
  Future<List<Map<String, Object?>>> pendingProductionCosts(String farmId) async {
    final rows = await database.query(
      costOutboxTable,
      where: 'farm_id=? AND delivered=0',
      whereArgs: [farmId],
      orderBy: 'occurred_at, movement_id',
    );
    return List.unmodifiable(rows);
  }

  Future<void> acknowledgeProductionCost(String farmId, String movementId) async {
    final changed = await database.update(
      costOutboxTable,
      {'delivered': 1},
      where: 'farm_id=? AND movement_id=?',
      whereArgs: [farmId, movementId],
    );
    if (changed != 1) throw StateError('Unknown production cost intent.');
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
          code: row['code'] as String?,
        ),
      ),
    );
  }
}
