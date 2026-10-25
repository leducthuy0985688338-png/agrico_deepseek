import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/production_destination_repository.dart';

import '../../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../../core/identity/domain/business_reference_code.dart';

import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../../../core/catalog/sqlite_company_catalog.dart';
import '../../../../core/catalog/company_catalog.dart';

class SqliteInventoryRepository
    implements InventoryRepository, ProductionDestinationRepository {
  const SqliteInventoryRepository(this.database);

  final Database database;
  static const seasonsTable = 'production_seasons_v2';
  static const costsTable = 'production_material_costs_v2';
  static const itemsTable = 'inventory_items_v2';
  static const movementsTable = 'inventory_movements_v2';

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
    await db.execute('''CREATE TABLE IF NOT EXISTS $seasonsTable (
      id TEXT PRIMARY KEY,
      farm_id TEXT NOT NULL,
      parcel_id TEXT NOT NULL REFERENCES land_parcels(id) ON DELETE RESTRICT,
      name TEXT NOT NULL,
      starts_on TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
      UNIQUE(farm_id, parcel_id, name)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $costsTable (
      movement_id TEXT PRIMARY KEY REFERENCES $movementsTable(id) ON DELETE RESTRICT,
      farm_id TEXT NOT NULL,
      parcel_id TEXT NOT NULL REFERENCES land_parcels(id) ON DELETE RESTRICT,
      season_id TEXT NOT NULL REFERENCES $seasonsTable(id) ON DELETE RESTRICT,
      item_id TEXT NOT NULL REFERENCES $itemsTable(id) ON DELETE RESTRICT,
      item_name TEXT NOT NULL,
      unit TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK(quantity > 0),
      unit_price REAL NOT NULL CHECK(unit_price >= 0),
      amount REAL NOT NULL CHECK(amount >= 0),
      occurred_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_seasons_v2_farm '
      'ON $seasonsTable(farm_id, parcel_id, active)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_material_costs_v2_farm '
      'ON $costsTable(farm_id, parcel_id, season_id, occurred_at)',
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

  /// An issue intended for production. Stock and its immutable production cost
  /// are committed in the same database transaction. All writes use the same agrico.db connection; there is no second cost writer.
  @override
  Future<void> recordProductionIssue(
    InventoryMovement movement, {
    required String parcelId,
    required String seasonId,
  }) async {
    if (movement.kind != InventoryMovementKind.issue ||
        parcelId.trim().isEmpty ||
        seasonId.trim().isEmpty) {
      throw const FormatException(
        'Production issue requires a V2 parcel and season.',
      );
    }
    await _record(movement, parcelId: parcelId, seasonId: seasonId);
  }

  @override
  Future<void> record(InventoryMovement movement) => _record(movement);

  Future<void> _record(
    InventoryMovement movement, {
    String? parcelId,
    String? seasonId,
  }) async {
    movement.validate();
    if (movement.code != null) {
      throw const FormatException('Movement codes are assigned by SQLite.');
    }
    await database.transaction((tx) async {
      if (parcelId != null) {
        final destination = await tx.rawQuery(
          'SELECT s.id FROM $seasonsTable s '
          'JOIN land_parcels p ON p.id=s.parcel_id AND p.farm_id=s.farm_id '
          "WHERE p.id=? AND s.id=? AND s.farm_id=? AND p.active=1 "
          "AND p.kind='fieldPlot' AND s.active=1 AND s.starts_on<=? LIMIT 1",
          [
            parcelId,
            seasonId,
            movement.farmId,
            movement.occurredAt
                .toUtc()
                .add(const Duration(hours: 7))
                .toIso8601String()
                .substring(0, 10),
          ],
        );
        if (destination.isEmpty) {
          throw StateError('Invalid V2 parcel/season for this farm and date.');
        }
      }
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
      final costItem = parcelId == null
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
        final price = (costItem['unit_price']! as num).toDouble();
        final amount = price * movement.quantity;
        if (!price.isFinite || price < 0 || !amount.isFinite) {
          throw const FormatException('Invalid material cost snapshot.');
        }
        await tx.insert(costsTable, {
          'movement_id': movement.id,
          'farm_id': movement.farmId,
          'item_id': movement.itemId,
          'parcel_id': parcelId,
          'season_id': seasonId,
          'item_name': costItem['name'],
          'unit': costItem['unit'],
          'quantity': movement.quantity,
          'unit_price': costItem['unit_price'],
          'occurred_at': movement.occurredAt.toIso8601String(),
          'amount': amount,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });
  }

  @override
  Future<List<ProductionDestination>> productionDestinations(
    String farmId,
  ) async {
    final rows = await database.rawQuery(
      'SELECT p.id AS parcel_id, p.parcel_code, s.id AS season_id, s.name '
      'FROM $seasonsTable s JOIN land_parcels p '
      'ON p.id=s.parcel_id AND p.farm_id=s.farm_id '
      "WHERE s.farm_id=? AND p.active=1 AND p.kind='fieldPlot' AND s.active=1 "
      'ORDER BY p.parcel_code, s.starts_on DESC, s.id',
      [farmId],
    );
    return List.unmodifiable(
      rows.map(
        (r) => ProductionDestination(
          parcelId: r['parcel_id']! as String,
          parcelCode: r['parcel_code']! as String,
          seasonId: r['season_id']! as String,
          seasonName: r['name']! as String,
        ),
      ),
    );
  }

  @override
  Future<List<ProductionIdentityChoice>> productionParcels(
    String farmId,
  ) async {
    final rows = await database.query(
      'land_parcels',
      columns: ['id', 'parcel_code'],
      where: "farm_id=? AND active=1 AND kind='fieldPlot'",
      whereArgs: [farmId],
      orderBy: 'parcel_code, id',
    );
    return List.unmodifiable(
      rows.map(
        (r) => ProductionIdentityChoice(
          r['id']! as String,
          r['parcel_code']! as String,
        ),
      ),
    );
  }

  @override
  Future<List<ProductionSeason>> productionSeasons(String farmId) async {
    final rows = await database.query(
      seasonsTable,
      where: 'farm_id=?',
      whereArgs: [farmId],
      orderBy: 'starts_on DESC, id',
    );
    return List.unmodifiable(
      rows.map(
        (r) => ProductionSeason(
          id: r['id']! as String,
          farmId: r['farm_id']! as String,
          parcelId: r['parcel_id']! as String,
          name: r['name']! as String,
          startsOn: r['starts_on']! as String,
          active: r['active'] == 1,
        ),
      ),
    );
  }

  @override
  Future<void> createProductionSeason(ProductionSeason season) async {
    season.validate();
    await database.transaction((tx) async {
      final parcel = await tx.query(
        'land_parcels',
        columns: ['id'],
        where: "id=? AND farm_id=? AND active=1 AND kind='fieldPlot'",
        whereArgs: [season.parcelId, season.farmId],
      );
      if (parcel.length != 1) {
        throw StateError('Active V2 production plot required.');
      }
      await tx.insert(seasonsTable, {
        'id': season.id,
        'farm_id': season.farmId,
        'parcel_id': season.parcelId,
        'name': season.name,
        'starts_on': season.startsOn,
        'active': season.active ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  @override
  Future<void> setProductionSeasonActive(
    String farmId,
    String seasonId,
    bool active,
  ) async {
    final changed = await database.update(
      seasonsTable,
      {'active': active ? 1 : 0},
      where: 'id=? AND farm_id=?',
      whereArgs: [seasonId, farmId],
    );
    if (changed != 1) throw StateError('Season not found in this farm.');
  }

  @override
  Future<List<ProductionMaterialCost>> productionCosts(String farmId) async {
    final rows = await database.rawQuery(
      'SELECT c.*, p.parcel_code, s.name AS season_name FROM $costsTable c '
      'JOIN land_parcels p ON p.id=c.parcel_id AND p.farm_id=c.farm_id '
      'JOIN $seasonsTable s ON s.id=c.season_id AND s.farm_id=c.farm_id '
      'AND s.parcel_id=c.parcel_id '
      'WHERE c.farm_id=? ORDER BY c.occurred_at DESC, c.movement_id',
      [farmId],
    );
    return List.unmodifiable(
      rows.map(
        (r) => ProductionMaterialCost(
          movementId: r['movement_id']! as String,
          parcelId: r['parcel_id']! as String,
          parcelCode: r['parcel_code']! as String,
          seasonId: r['season_id']! as String,
          seasonName: r['season_name']! as String,
          itemName: r['item_name']! as String,
          unit: r['unit']! as String,
          quantity: r['quantity']! as int,
          unitPrice: (r['unit_price']! as num).toDouble(),
          amount: (r['amount']! as num).toDouble(),
          occurredAt: DateTime.parse(r['occurred_at']! as String),
        ),
      ),
    );
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
