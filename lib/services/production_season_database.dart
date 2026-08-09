import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/production_season_model.dart';

class ProductionSeasonDatabase {
  static const _databaseName = 'agrico.db';
  static const _databaseVersion = 2;
  static const _table = 'production_seasons';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _databaseName);
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE fields (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            area REAL NOT NULL,
            crop TEXT NOT NULL,
            status TEXT NOT NULL,
            polygon TEXT NOT NULL,
            photo_paths TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await _createSeasonTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSeasonTable(db);
      },
    );
    return _database!;
  }

  Future<void> _createSeasonTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        field_id TEXT NOT NULL,
        name TEXT NOT NULL,
        crop TEXT NOT NULL,
        variety TEXT NOT NULL,
        start_date TEXT NOT NULL,
        expected_harvest_date TEXT,
        status TEXT NOT NULL,
        planned_area REAL NOT NULL,
        notes TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(field_id) REFERENCES fields(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_seasons_field ON $_table(field_id)',
    );
  }

  Future<List<ProductionSeasonModel>> getByField(String fieldId) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'field_id = ?',
      whereArgs: [fieldId],
      orderBy: 'start_date DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(ProductionSeasonModel season) async {
    final db = await database;
    await db.insert(
      _table,
      {
        'id': season.id,
        'field_id': season.fieldId,
        'name': season.name,
        'crop': season.crop,
        'variety': season.variety,
        'start_date': season.startDate.toIso8601String(),
        'expected_harvest_date': season.expectedHarvestDate?.toIso8601String(),
        'status': season.status,
        'planned_area': season.plannedArea,
        'notes': season.notes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  ProductionSeasonModel _fromRow(Map<String, Object?> row) {
    return ProductionSeasonModel.fromJson({
      'id': row['id'],
      'fieldId': row['field_id'],
      'name': row['name'],
      'crop': row['crop'],
      'variety': row['variety'],
      'startDate': row['start_date'],
      'expectedHarvestDate': row['expected_harvest_date'],
      'status': row['status'],
      'plannedArea': row['planned_area'],
      'notes': row['notes'],
    });
  }
}
