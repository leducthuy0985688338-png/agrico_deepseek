import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/harvest_record_model.dart';

class HarvestDatabase {
  static const _dbName = 'agrico.db';
  static const _version = 4;
  static const _table = 'harvest_records';
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
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        moisture_percent REAL NOT NULL,
        selling_price REAL NOT NULL,
        revenue REAL NOT NULL,
        notes TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_harvest_season ON $_table(season_id, date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_harvest_field ON $_table(field_id, date DESC)');
  }

  Future<List<HarvestRecordModel>> getBySeason(String seasonId) async {
    final db = await database;
    final rows = await db.query(_table, where: 'season_id = ?', whereArgs: [seasonId], orderBy: 'date DESC');
    return rows.map((r) => HarvestRecordModel.fromJson({
      'id': r['id'], 'seasonId': r['season_id'], 'fieldId': r['field_id'], 'date': r['date'],
      'quantity': r['quantity'], 'unit': r['unit'], 'moisturePercent': r['moisture_percent'],
      'sellingPrice': r['selling_price'], 'revenue': r['revenue'], 'notes': r['notes'],
    })).toList(growable: false);
  }

  Future<void> upsert(HarvestRecordModel record) async {
    final db = await database;
    await db.insert(
      _table,
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceAll(List<HarvestRecordModel> records) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_table);
      for (final record in records) {
        await transaction.insert(
          _table,
          _toRow(record),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Map<String, Object?> _toRow(HarvestRecordModel record) => {
        'id': record.id,
        'season_id': record.seasonId,
        'field_id': record.fieldId,
        'date': record.date.toIso8601String(),
        'quantity': record.quantity,
        'unit': record.unit,
        'moisture_percent': record.moisturePercent,
        'selling_price': record.sellingPrice,
        'revenue': record.revenue,
        'notes': record.notes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
