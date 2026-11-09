import 'sqlite_warehouse_stock.dart';
import '../../../../core/production/source_governance.dart';
import '../../../../core/permissions/operation_scope.dart';
import '../../../../core/permissions/authorization.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../../../machines/domain/machines.dart'
    show ProductionMachineCost, ProductionMachineCostRepository;
import '../../../machines/data/sqlite_machine_repository.dart';
import '../../../personnel/data/sqlite_personnel_repository.dart';
import '../../../personnel/domain/personnel.dart'
    show ProductionLaborCost, ProductionLaborCostRepository;
import '../../domain/entities/exact_decimal.dart';
import '../../domain/repositories/production_planning_repository.dart';
import 'sqlite_production_planning_repository.dart';

import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/production_destination_repository.dart';

import '../../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../../core/identity/domain/business_reference_code.dart';

import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../../../core/catalog/sqlite_company_catalog.dart';
import '../../../../core/catalog/company_catalog.dart';

class SqliteInventoryRepository
    implements
        InventoryRepository,
        WarehouseRepository,
        ProductionDestinationRepository,
        ProductionPlanningRepository,
        ProductionLaborCostRepository,
        ProductionMachineCostRepository {
  const SqliteInventoryRepository(
    this.database, {
    this.warehouseId,
    this.scope,
  });
  final String? warehouseId;
  final OperationScope? scope;
  @override
  InventoryRepository inWarehouse(OperationScope scope, String warehouseId) =>
      SqliteInventoryRepository(
        database,
        warehouseId: warehouseId,
        scope: scope,
      );
  @override
  Future<List<InventoryWarehouse>> warehouses(
    String farmId,
    OperationScope scope,
  ) async {
    // No writes on a read path. Empty farms get their default at startup or first receipt.
    final rows = await database.query(
      'inventory_warehouses_v1',
      where: 'farm_id=? AND ${scope.sql(warehouse: 'id')}',
      whereArgs: [farmId],
      orderBy: 'code,id',
    );
    final result = rows
        .map(
          (r) => InventoryWarehouse(
            r['id']! as String,
            r['code']! as String,
            r['name']! as String,
            active: r['active'] == 1,
          ),
        )
        .toList();
    final defaultId = InventoryWarehouse.defaultId(farmId);
    if (!result.any((w) => w.id == defaultId) &&
        scope.allows(ResourceContext(farmId: farmId, warehouseId: defaultId)))
      result.insert(
        0,
        InventoryWarehouse(defaultId, 'KHO-000', 'Kho mặc định'),
      );
    return result;
  }

  @override
  Future<void> createWarehouse(
    String farmId,
    String id,
    String name,
    String actorId,
  ) => database.transaction((tx) async {
    if (id.trim().isEmpty ||
        id.startsWith('warehouse:default:') ||
        name.trim().isEmpty ||
        name.length > 200 ||
        actorId.trim().isEmpty)
      throw const FormatException('Invalid warehouse.');
    await SqliteWarehouseStock.ensureDefault(tx, farmId);
    final previous = await tx.query(
      'inventory_warehouse_sequences_v1',
      where: 'farm_id=?',
      whereArgs: [farmId],
    );
    final n = previous.isEmpty
        ? 1
        : (previous.single['last_value']! as int) + 1;
    await tx.insert('inventory_warehouse_sequences_v1', {
      'farm_id': farmId,
      'last_value': n,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.insert('inventory_warehouses_v1', {
      'id': id,
      'farm_id': farmId,
      'code': 'KHO-${n.toString().padLeft(3, '0')}',
      'name': name.trim(),
      'active': 1,
    });
  });
  @override
  Future<void> transfer(
    String farmId,
    String id,
    String itemId,
    String sourceId,
    String destinationId,
    num quantity,
    DateTime at,
    String actorId,
    OperationScope scope,
  ) => database.transaction((tx) async {
    final stamp = scope.live.stamp(scope.opened);
    scope.require(ResourceContext(farmId: farmId, warehouseId: sourceId));
    scope.require(ResourceContext(farmId: farmId, warehouseId: destinationId));
    if (sourceId == destinationId || id.trim().isEmpty)
      throw const FormatException('Different warehouses required.');
    final units = ExactDecimal.quantityUnits(quantity);
    if (units <= 0) throw const FormatException('Positive quantity required.');
    final previous = await tx.query(
      'inventory_transfers_v1',
      where: 'id=?',
      whereArgs: [id],
    );
    if (previous.isNotEmpty) {
      final r = previous.single;
      if (r['farm_id'] == farmId &&
          r['item_id'] == itemId &&
          r['source_id'] == sourceId &&
          r['destination_id'] == destinationId &&
          r['quantity_units'] == units &&
          r['occurred_at'] == at.toUtc().toIso8601String() &&
          r['actor_id'] == actorId)
        return;
      throw StateError('Transfer identity conflict.');
    }
    await tx.insert('inventory_transfers_v1', {
      'id': id,
      'farm_id': farmId,
      'item_id': itemId,
      'source_id': sourceId,
      'destination_id': destinationId,
      'quantity_units': units,
      'occurred_at': at.toUtc().toIso8601String(),
      'actor_id': actorId,
    });
    for (final receipt in [false, true]) {
      await recordInTransaction(
        tx,
        InventoryMovement(
          id: 'transfer:$id:${receipt ? 'in' : 'out'}',
          farmId: farmId,
          itemId: itemId,
          warehouseId: receipt ? destinationId : sourceId,
          kind: receipt
              ? InventoryMovementKind.receipt
              : InventoryMovementKind.issue,
          quantity: quantity,
          occurredAt: at,
        ),
        transferId: id,
      );
    }
    scope.live.requireStamp(scope.opened, stamp);
  });

  final Database database;
  static const seasonsTable = 'production_seasons_v2';
  static const costsTable = 'production_material_costs_v2';
  static const itemsTable = 'inventory_items_v2';
  static const movementsTable = 'inventory_movements_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SourceGovernance.createSchema(db);
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
    await SqliteProductionPlanningRepository.createSchema(db);
    Future<void> column(String table, String name, String definition) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (!info.any((r) => r['name'] == name)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $name $definition');
      }
    }

    final itemColumns = await db.rawQuery('PRAGMA table_info($itemsTable)');
    if (!itemColumns.any((c) => c['name'] == 'stock_units')) {
      await db.execute(
        'ALTER TABLE $itemsTable ADD COLUMN stock_units INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('UPDATE $itemsTable SET stock_units=stock*1000000');
    }
    await column(movementsTable, 'quantity_units', 'INTEGER');
    await column(costsTable, 'quantity_units', 'INTEGER');
    for (final table in [movementsTable, costsTable]) {
      await column(table, 'unit_price_text', 'TEXT');
      await column(table, 'amount_text', 'TEXT');
      await column(table, 'currency', "TEXT CHECK(currency IN ('VND','LAK'))");
      await column(table, 'priced_by', 'TEXT');
      await column(table, 'zero_price_confirmed', 'INTEGER NOT NULL DEFAULT 0');
      await column(table, 'plan_id', 'TEXT REFERENCES production_plans_v1(id)');
    }
    await db.execute(
      'UPDATE $itemsTable SET stock_units=stock*1000000 WHERE stock_units IS NULL',
    );
    await db.execute(
      'UPDATE $movementsTable SET quantity_units=quantity*1000000 WHERE quantity_units IS NULL',
    );
    await db.execute(
      'UPDATE $costsTable SET quantity_units=quantity*1000000 WHERE quantity_units IS NULL',
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
    await SqliteWarehouseStock.createSchema(db);
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
          'stock_units': 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    });
  }

  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async {
    final productIds =
        await SqliteCompanyCatalog.hasTable(
          database,
          SqliteCompanyCatalog.entriesTable,
        )
        ? (await database.query(
            SqliteCompanyCatalog.entriesTable,
            columns: ['id'],
            where: "farm_id=? AND kind='product'",
            whereArgs: [farmId],
          )).map((r) => r['id']).toSet()
        : <Object?>{};
    if (warehouseId != null)
      scope?.require(ResourceContext(farmId: farmId, warehouseId: warehouseId));
    final rows = warehouseId == null
        ? await database.query(
            itemsTable,
            where: 'farm_id=?',
            whereArgs: [farmId],
            orderBy: 'code,id',
          )
        : await database.rawQuery(
            'SELECT i.*,COALESCE(s.stock_units,0) AS warehouse_stock_units FROM inventory_items_v2 i LEFT JOIN inventory_warehouse_stock_v1 s ON s.item_id=i.id AND s.farm_id=i.farm_id AND s.warehouse_id=? WHERE i.farm_id=? ORDER BY i.code,i.id',
            [warehouseId, farmId],
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
          stock: ExactDecimal.quantityFromUnits(
            (row['warehouse_stock_units'] ?? row['stock_units'])! as int,
          ),
          finishedGoods: productIds.contains(row['id']),
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
    String? planId,
  }) async {
    if (movement.kind != InventoryMovementKind.issue ||
        parcelId.trim().isEmpty ||
        seasonId.trim().isEmpty ||
        planId == null ||
        planId.trim().isEmpty) {
      throw const FormatException(
        'Production issue requires a V2 parcel and season.',
      );
    }
    await _record(
      movement,
      parcelId: parcelId,
      seasonId: seasonId,
      planId: planId,
    );
  }

  @override
  Future<void> record(InventoryMovement movement) => _record(movement);

  Future<void> _record(
    InventoryMovement movement, {
    String? parcelId,
    String? seasonId,
    String? planId,
  }) => database.transaction(
    (tx) => recordInTransaction(
      tx,
      movement,
      parcelId: parcelId,
      seasonId: seasonId,
      planId: planId,
    ),
  );

  Future<void> recordInTransaction(
    Transaction tx,
    InventoryMovement movement, {
    String? parcelId,
    String? seasonId,
    String? planId,
    bool finishedGoods = false,
    String? transferId,
  }) async {
    movement.validate();
    final scopeStamp = scope?.live.stamp(scope!.opened);
    if (movement.transferId != null)
      throw const FormatException('Transfers are generated internally.');
    if (transferId != null) {
      final t = await tx.query(
        'inventory_transfers_v1',
        where: 'id=? AND farm_id=? AND item_id=? AND quantity_units=?',
        whereArgs: [
          transferId,
          movement.farmId,
          movement.itemId,
          movement.quantityUnits,
        ],
      );
      final expectedWarehouse = movement.kind == InventoryMovementKind.receipt
          ? 'destination_id'
          : 'source_id';
      if (t.length != 1 ||
          t.single[expectedWarehouse] != movement.warehouseId ||
          movement.unitPriceText != null ||
          movement.currency != null ||
          planId != null)
        throw StateError('Invalid internal transfer.');
    }
    final selected =
        movement.warehouseId ?? InventoryWarehouse.defaultId(movement.farmId);
    if (warehouseId != null && warehouseId != selected)
      throw StateError('Warehouse mismatch.');
    scope?.require(
      ResourceContext(farmId: movement.farmId, warehouseId: selected),
    );
    if (selected == InventoryWarehouse.defaultId(movement.farmId))
      await SqliteWarehouseStock.ensureDefault(tx, movement.farmId);
    final selectedRows = await tx.query(
      'inventory_warehouses_v1',
      where: 'id=? AND farm_id=? AND active=1',
      whereArgs: [selected, movement.farmId],
    );
    if (selectedRows.length != 1) throw StateError('Warehouse unavailable.');
    if (transferId == null &&
        movement.kind == InventoryMovementKind.issue &&
        (movement.unitPriceText == null ||
            movement.currency == null ||
            movement.pricedBy == null ||
            movement.pricedBy!.trim().isEmpty)) {
      throw const FormatException(
        'An Admin-confirmed issue price is required.',
      );
    }
    if (movement.unitPriceText != null &&
        ExactDecimal.parse(movement.unitPriceText!).coefficient ==
            BigInt.zero &&
        !movement.zeroPriceConfirmed) {
      throw const FormatException('Zero price must be confirmed.');
    }
    if (movement.code != null) {
      throw const FormatException('Movement codes are assigned by SQLite.');
    }
    if (!finishedGoods &&
        await SqliteCompanyCatalog.hasTable(
          tx,
          SqliteCompanyCatalog.entriesTable,
        )) {
      final product = await tx.query(
        SqliteCompanyCatalog.entriesTable,
        columns: ['id'],
        where: "id=? AND kind='product'",
        whereArgs: [movement.itemId],
      );
      if (product.isNotEmpty) {
        throw StateError('Finished goods require harvest/sale lot workflow.');
      }
    }
    final prior = await tx.query(
      movementsTable,
      where: 'id=?',
      whereArgs: [movement.id],
    );
    if (prior.isNotEmpty) {
      final r = prior.single;
      if (r['farm_id'] == movement.farmId &&
          r['warehouse_id'] == selected &&
          r['transfer_id'] == transferId &&
          r['item_id'] == movement.itemId &&
          r['kind'] == movement.kind.name &&
          r['quantity_units'] == movement.quantityUnits &&
          r['occurred_at'] == movement.occurredAt.toUtc().toIso8601String() &&
          r['currency'] == movement.currency &&
          r['unit_price_text'] == movement.unitPriceText &&
          r['priced_by'] == movement.pricedBy &&
          r['zero_price_confirmed'] == (movement.zeroPriceConfirmed ? 1 : 0) &&
          r['plan_id'] == planId) {
        return;
      }
      throw StateError('Movement identity already has different contents.');
    }
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
    if (parcelId != null) {
      final day = movement.occurredAt
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
      final plan = await tx.query(
        'production_plans_v1',
        where:
            "id=? AND farm_id=? AND parcel_id=? AND season_id=? AND status='active' AND currency=? AND starts_on<=? AND ends_on>=?",
        whereArgs: [
          planId,
          movement.farmId,
          parcelId,
          seasonId,
          movement.currency,
          day,
          day,
        ],
      );
      if (plan.length != 1) {
        throw StateError(
          'Active plan, matching currency and plan dates required.',
        );
      }
    }
    if (movement.kind == InventoryMovementKind.issue) {
      final balance = await tx.query(
        'inventory_warehouse_stock_v1',
        where: 'warehouse_id=? AND item_id=? AND farm_id=?',
        whereArgs: [selected, movement.itemId, movement.farmId],
      );
      if (balance.isEmpty ||
          (balance.single['stock_units']! as int) < movement.quantityUnits)
        throw StateError('Insufficient stock in selected warehouse.');
    }
    final delta = movement.kind == InventoryMovementKind.receipt
        ? movement.quantityUnits
        : -movement.quantityUnits;
    final changed = await tx.rawUpdate(
      'UPDATE $itemsTable SET stock = (stock_units + ?) / 1000000.0, stock_units = stock_units + ? '
      'WHERE id = ? AND farm_id = ? AND stock_units + ? >= 0 AND stock_units + ? <= 9007199254740991',
      [delta, delta, movement.itemId, movement.farmId, delta, delta],
    );
    if (changed != 1) {
      throw StateError(
        'Item is missing or stock is insufficient in this farm.',
      );
    }
    await tx.insert('inventory_warehouse_stock_v1', {
      'farm_id': movement.farmId,
      'warehouse_id': selected,
      'item_id': movement.itemId,
      'stock_units': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final balanceChanged = await tx.rawUpdate(
      'UPDATE inventory_warehouse_stock_v1 SET stock_units=stock_units+? WHERE farm_id=? AND warehouse_id=? AND item_id=? AND stock_units+?>=0 AND stock_units+?<=9007199254740991',
      [delta, movement.farmId, selected, movement.itemId, delta, delta],
    );
    if (balanceChanged != 1)
      throw StateError('Warehouse stock overflow or shortage.');
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
        'warehouse_id': selected,
        'transfer_id': transferId,
        'kind': movement.kind.name,
        'quantity': movement.quantity,
        'quantity_units': movement.quantityUnits,
        'unit_price_text': movement.unitPriceText,
        'amount_text': movement.amountText,
        'currency': movement.currency,
        'priced_by': movement.pricedBy,
        'zero_price_confirmed': movement.zeroPriceConfirmed ? 1 : 0,
        'plan_id': planId,
        'occurred_at': movement.occurredAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort),
    );
    if (costItem != null) {
      final price = double.parse(movement.unitPriceText!);
      final amount = double.parse(movement.amountText!);
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
        'quantity_units': movement.quantityUnits,
        'unit_price_text': movement.unitPriceText,
        'amount_text': movement.amountText,
        'currency': movement.currency,
        'priced_by': movement.pricedBy,
        'zero_price_confirmed': movement.zeroPriceConfirmed ? 1 : 0,
        'plan_id': planId,
        'unit_price': price,
        'occurred_at': movement.occurredAt.toUtc().toIso8601String(),
        'amount': amount,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
    if (costItem != null) {
      await SourceGovernance.register(
        tx,
        farm: movement.farmId,
        type: 'material',
        id: movement.id,
        day: date.toIso8601String().substring(0, 10),
        actor: scope?.subject.userId ?? movement.pricedBy!,
        payload: await SourceGovernance.nativePayload(
          tx,
          'material',
          movement.id,
        ),
      );
    }
    if (scopeStamp != null) scope!.live.requireStamp(scope!.opened, scopeStamp);
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
      'SELECT c.*, p.parcel_code, s.name AS season_name, plan.code AS plan_code FROM $costsTable c '
      'JOIN land_parcels p ON p.id=c.parcel_id AND p.farm_id=c.farm_id '
      'JOIN $seasonsTable s ON s.id=c.season_id AND s.farm_id=c.farm_id '
      'AND s.parcel_id=c.parcel_id '
      'LEFT JOIN production_plans_v1 plan ON plan.id=c.plan_id AND plan.farm_id=c.farm_id '
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
          quantity: ExactDecimal.quantityFromUnits(r['quantity_units']! as int),
          currency: r['currency'] as String?,
          unitPriceText: r['unit_price_text'] as String?,
          amountText: r['amount_text'] as String?,
          planId: r['plan_id'] as String?,
          planCode: r['plan_code'] as String?,
          unitPrice: (r['unit_price']! as num).toDouble(),
          amount: (r['amount']! as num).toDouble(),
          occurredAt: DateTime.parse(r['occurred_at']! as String),
        ),
      ),
    );
  }

  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async {
    if (warehouseId != null)
      scope?.require(ResourceContext(farmId: farmId, warehouseId: warehouseId));
    final rows = await database.query(
      movementsTable,
      where: warehouseId == null ? 'farm_id=?' : 'farm_id=? AND warehouse_id=?',
      whereArgs: [farmId, if (warehouseId != null) warehouseId],
      orderBy: 'occurred_at, id',
    );
    return List.unmodifiable(
      rows.map(
        (row) => InventoryMovement(
          id: row['id']! as String,
          farmId: row['farm_id']! as String,
          itemId: row['item_id']! as String,
          warehouseId: row['warehouse_id'] as String?,
          transferId: row['transfer_id'] as String?,
          kind: InventoryMovementKind.values.byName(row['kind']! as String),
          quantity: ExactDecimal.quantityFromUnits(
            row['quantity_units']! as int,
          ),
          unitPriceText: row['unit_price_text'] as String?,
          currency: row['currency'] as String?,
          pricedBy: row['priced_by'] as String?,
          zeroPriceConfirmed: row['zero_price_confirmed'] == 1,
          occurredAt: DateTime.parse(row['occurred_at']! as String),
          code: row['code'] as String?,
        ),
      ),
    );
  }

  SqliteProductionPlanningRepository get _planning =>
      SqliteProductionPlanningRepository(database);
  @override
  Future<List<ProductionPlan>> productionPlans(String farmId) =>
      _planning.productionPlans(farmId);
  @override
  Future<void> createProductionPlan(ProductionPlan plan, String actorId) =>
      _planning.createProductionPlan(plan, actorId);
  @override
  Future<void> changeProductionPlanStatus(
    String farmId,
    String planId,
    int revision,
    ProductionPlanStatus status,
    String actorId,
  ) => _planning.changeProductionPlanStatus(
    farmId,
    planId,
    revision,
    status,
    actorId,
  );
  @override
  Future<List<ProductionPlanTask>> productionPlanTasks(String farmId) =>
      _planning.productionPlanTasks(farmId);
  @override
  Future<void> createProductionPlanTask(
    ProductionPlanTask task,
    String actorId,
  ) => _planning.createProductionPlanTask(task, actorId);
  @override
  Future<void> completeProductionPlanTask(
    String farmId,
    String taskId,
    int revision,
    bool completed,
    String actorId,
  ) => _planning.completeProductionPlanTask(
    farmId,
    taskId,
    revision,
    completed,
    actorId,
  );
  @override
  Future<List<ProductionMachineCost>> productionMachineCosts(
    String farmId,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='machine_runs_v1'",
    );
    if (tables.isEmpty) return [];
    return SqliteMachineRepository(database).productionMachineCosts(farmId);
  }

  @override
  Future<List<ProductionLaborCost>> productionLaborCosts(String farmId) =>
      SqlitePersonnelRepository(database).productionLaborCosts(farmId);
}
