import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/production_log_model.dart';

class ProductionLogDatabase {
  static const _dbName = 'agrico.db';
  static const _version = 4;
  static const _table = 'production_logs';
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, _dbName),
      version: _version,
      onUpgrade: (db, oldVersion, newVersion) async => _createTable(db),
      onCreate: (db, version) async => _createTable(db),
      onOpen: (db) async => _createTable(db),
    );
    return _db!;
  }

  Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        season_id TEXT NOT NULL,
        field_id TEXT NOT NULL,
        date TEXT NOT NULL,
        activity_type TEXT NOT NULL,
        title TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        cost REAL NOT NULL,
        worker TEXT NOT NULL,
        notes TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_season ON $_table(season_id, date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_field ON $_table(field_id, date DESC)');
  }

  Future<List<ProductionLogModel>> getBySeason(String seasonId) async {
    final db = await database;
    final rows = await db.query(_table, where: 'season_id = ?', whereArgs: [seasonId], orderBy: 'date DESC');
    return rows.map((r) => ProductionLogModel.fromJson({
      'id': r['id'], 'seasonId': r['season_id'], 'fieldId': r['field_id'],
      'date': r['date'], 'activityType': r['activity_type'], 'title': r['title'],
      'quantity': r['quantity'], 'unit': r['unit'], 'cost': r['cost'],
      'worker': r['worker'], 'notes': r['notes'],
    })).toList(growable: false);
  }

  Future<void> upsert(ProductionLogModel log) async {
    final db = await database;
    await db.insert(
      _table,
      _toRow(log),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceAll(List<ProductionLogModel> logs) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_table);
      for (final log in logs) {
        await transaction.insert(
          _table,
          _toRow(log),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Map<String, Object?> _toRow(ProductionLogModel log) => {
        'id': log.id,
        'season_id': log.seasonId,
        'field_id': log.fieldId,
        'date': log.date.toIso8601String(),
        'activity_type': log.activityType,
        'title': log.title,
        'quantity': log.quantity,
        'unit': log.unit,
        'cost': log.cost,
        'worker': log.worker,
        'notes': log.notes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
