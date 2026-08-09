import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/production_cost_model.dart';

class ProductionCostDatabase {
  static const _dbName = 'agrico_costs.db';
  static const _version = 1;
  static const _table = 'production_costs';
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final directory = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(directory.path, _dbName),
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            field_id TEXT NOT NULL,
            season_id TEXT NOT NULL,
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            item_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            unit_price REAL NOT NULL,
            amount REAL NOT NULL,
            employee_id TEXT,
            machine_id TEXT,
            notes TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_cost_season ON $_table(season_id, date DESC)');
        await db.execute('CREATE INDEX idx_cost_field ON $_table(field_id, date DESC)');
        await db.execute('CREATE INDEX idx_cost_category ON $_table(season_id, category)');
      },
    );
    return _db!;
  }

  Future<List<ProductionCostModel>> getBySeason(String seasonId) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'season_id = ?',
      whereArgs: [seasonId],
      orderBy: 'date DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(ProductionCostModel record) async {
    final db = await database;
    await db.insert(
      _table,
      {
        'id': record.id,
        'field_id': record.fieldId,
        'season_id': record.seasonId,
        'category': record.category.key,
        'date': record.date.toIso8601String(),
        'item_name': record.itemName,
        'quantity': record.quantity,
        'unit': record.unit,
        'unit_price': record.unitPrice,
        'amount': record.amount,
        'employee_id': record.employeeId,
        'machine_id': record.machineId,
        'notes': record.notes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  ProductionCostModel _fromRow(Map<String, Object?> row) {
    return ProductionCostModel.fromJson({
      'id': row['id'],
      'fieldId': row['field_id'],
      'seasonId': row['season_id'],
      'category': row['category'],
      'date': row['date'],
      'itemName': row['item_name'],
      'quantity': row['quantity'],
      'unit': row['unit'],
      'unitPrice': row['unit_price'],
      'amount': row['amount'],
      'employeeId': row['employee_id'],
      'machineId': row['machine_id'],
      'notes': row['notes'],
    });
  }
}
