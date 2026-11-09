import 'package:sqflite/sqflite.dart';
import '../../domain/repositories/warehouse_repository.dart';

abstract final class SqliteWarehouseStock {
  static const tables = {
    'inventory_warehouses_v1',
    'inventory_warehouse_sequences_v1',
    'inventory_warehouse_stock_v1',
    'inventory_transfers_v1',
  };
  static Future<void> ensureDefault(DatabaseExecutor db, String farm) async {
    await db.insert('inventory_warehouses_v1', {
      'id': InventoryWarehouse.defaultId(farm),
      'farm_id': farm,
      'code': 'KHO-000',
      'name': 'Kho mặc định',
      'active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    if (db is Database) {
      await db.transaction((tx) => _createSchema(tx));
    } else {
      await _createSchema(db);
    }
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS inventory_warehouses_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,code TEXT NOT NULL,name TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),UNIQUE(farm_id,code),UNIQUE(farm_id,name))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS inventory_warehouse_sequences_v1(farm_id TEXT PRIMARY KEY,last_value INTEGER NOT NULL CHECK(last_value>0))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS inventory_warehouse_stock_v1(farm_id TEXT NOT NULL,warehouse_id TEXT NOT NULL REFERENCES inventory_warehouses_v1(id),item_id TEXT NOT NULL REFERENCES inventory_items_v2(id),stock_units INTEGER NOT NULL CHECK(stock_units>=0 AND stock_units<=9007199254740991),PRIMARY KEY(warehouse_id,item_id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS inventory_transfers_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,item_id TEXT NOT NULL REFERENCES inventory_items_v2(id),source_id TEXT NOT NULL REFERENCES inventory_warehouses_v1(id),destination_id TEXT NOT NULL REFERENCES inventory_warehouses_v1(id),quantity_units INTEGER NOT NULL CHECK(quantity_units>0),occurred_at TEXT NOT NULL,actor_id TEXT NOT NULL,CHECK(source_id<>destination_id))',
    );
    final columns = await db.rawQuery(
      'PRAGMA table_info(inventory_movements_v2)',
    );
    if (!columns.any((c) => c['name'] == 'warehouse_id')) {
      await db.execute(
        'ALTER TABLE inventory_movements_v2 ADD COLUMN warehouse_id TEXT REFERENCES inventory_warehouses_v1(id)',
      );
      for (final row in await db.rawQuery(
        'SELECT DISTINCT farm_id FROM inventory_items_v2 UNION SELECT DISTINCT farm_id FROM inventory_movements_v2',
      )) {
        final farm = row['farm_id']! as String;
        await ensureDefault(db, farm);
        await db.update(
          'inventory_movements_v2',
          {'warehouse_id': InventoryWarehouse.defaultId(farm)},
          where: 'farm_id=?',
          whereArgs: [farm],
        );
        await db.rawInsert(
          'INSERT INTO inventory_warehouse_stock_v1(farm_id,warehouse_id,item_id,stock_units) SELECT farm_id,?,id,stock_units FROM inventory_items_v2 WHERE farm_id=?',
          [InventoryWarehouse.defaultId(farm), farm],
        );
      }
    }
    if (!columns.any((c) => c['name'] == 'transfer_id'))
      await db.execute(
        'ALTER TABLE inventory_movements_v2 ADD COLUMN transfer_id TEXT REFERENCES inventory_transfers_v1(id)',
      );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movement_warehouse_v1 ON inventory_movements_v2(farm_id,warehouse_id,item_id,occurred_at)',
    );
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='inventory_warehouses_v1'",
    );
    if (exists.isEmpty) return;
    for (final w in await db.query('inventory_warehouses_v1')) {
      final farm = w['farm_id']! as String;
      final code = w['code']! as String;
      if ((w['name']! as String).trim().isEmpty)
        throw StateError('Invalid warehouse name.');
      if (w['id'] == InventoryWarehouse.defaultId(farm)) {
        if (code != 'KHO-000') throw StateError('Invalid default warehouse.');
      } else {
        final match = RegExp(r'^KHO-([0-9]{3,})$').firstMatch(code);
        final seq = await db.query(
          'inventory_warehouse_sequences_v1',
          where: 'farm_id=?',
          whereArgs: [farm],
        );
        if (match == null ||
            int.parse(match.group(1)!) < 1 ||
            seq.length != 1 ||
            (seq.single['last_value']! as int) < int.parse(match.group(1)!))
          throw StateError('Invalid warehouse sequence.');
      }
    }
    final invalid = await db.rawQuery(
      '''SELECT m.id FROM inventory_movements_v2 m LEFT JOIN inventory_warehouses_v1 w ON w.id=m.warehouse_id WHERE w.id IS NULL OR w.farm_id<>m.farm_id
      UNION ALL SELECT s.item_id FROM inventory_warehouse_stock_v1 s LEFT JOIN inventory_warehouses_v1 w ON w.id=s.warehouse_id LEFT JOIN inventory_items_v2 i ON i.id=s.item_id WHERE w.id IS NULL OR i.id IS NULL OR w.farm_id<>s.farm_id OR i.farm_id<>s.farm_id OR s.stock_units<0
      UNION ALL SELECT i.id FROM inventory_items_v2 i WHERE i.stock_units<>COALESCE((SELECT SUM(s.stock_units) FROM inventory_warehouse_stock_v1 s WHERE s.item_id=i.id AND s.farm_id=i.farm_id),0)
      UNION ALL SELECT s.item_id FROM inventory_warehouse_stock_v1 s WHERE s.stock_units<>COALESCE((SELECT SUM(CASE m.kind WHEN 'receipt' THEN m.quantity_units ELSE -m.quantity_units END) FROM inventory_movements_v2 m WHERE m.warehouse_id=s.warehouse_id AND m.item_id=s.item_id AND m.farm_id=s.farm_id),0)
      UNION ALL SELECT m.id FROM inventory_movements_v2 m WHERE NOT EXISTS(SELECT 1 FROM inventory_warehouse_stock_v1 s WHERE s.warehouse_id=m.warehouse_id AND s.item_id=m.item_id) LIMIT 1''',
    );
    if (invalid.isNotEmpty)
      throw StateError('Warehouse stock does not reconcile.');
    for (final transfer in await db.query('inventory_transfers_v1')) {
      final rows = await db.query(
        'inventory_movements_v2',
        where: 'transfer_id=?',
        whereArgs: [transfer['id']],
      );
      if (rows.length != 2 ||
          !rows.any(
            (m) =>
                m['kind'] == 'issue' &&
                m['warehouse_id'] == transfer['source_id'],
          ) ||
          !rows.any(
            (m) =>
                m['kind'] == 'receipt' &&
                m['warehouse_id'] == transfer['destination_id'],
          ) ||
          rows.any(
            (m) =>
                m['farm_id'] != transfer['farm_id'] ||
                m['item_id'] != transfer['item_id'] ||
                m['quantity_units'] != transfer['quantity_units'] ||
                m['occurred_at'] != transfer['occurred_at'] ||
                m['unit_price_text'] != null ||
                m['currency'] != null ||
                m['amount_text'] != null ||
                m['plan_id'] != null,
          ))
        throw StateError('Invalid transfer pair.');
    }
    final orphans = await db.rawQuery(
      'SELECT m.id FROM inventory_movements_v2 m LEFT JOIN inventory_transfers_v1 t ON t.id=m.transfer_id WHERE m.transfer_id IS NOT NULL AND t.id IS NULL LIMIT 1',
    );
    if (orphans.isNotEmpty) throw StateError('Unknown transfer.');
  }
}
