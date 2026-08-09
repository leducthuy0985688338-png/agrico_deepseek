import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/field_model.dart';

class FieldDatabase {
  static const _databaseName = 'agrico.db';
  static const _databaseVersion = 1;
  static const _table = 'fields';

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
          CREATE TABLE $_table (
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
        await db.execute(
          'CREATE INDEX idx_fields_updated_at ON $_table(updated_at)',
        );
      },
    );
    return _database!;
  }

  Future<List<FieldModel>> getAll() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'updated_at DESC');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(FieldModel field) async {
    final db = await database;
    await db.insert(
      _table,
      _toRow(field),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Map<String, Object?> _toRow(FieldModel field) => {
        'id': field.id,
        'name': field.name,
        'area': field.area,
        'crop': field.crop,
        'status': field.status,
        'polygon': jsonEncode(field.polygon
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(growable: false)),
        'photo_paths': jsonEncode(field.photoPaths),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  FieldModel _fromRow(Map<String, Object?> row) {
    final polygon = jsonDecode(row['polygon']! as String) as List<dynamic>;
    final photos = jsonDecode(row['photo_paths']! as String) as List<dynamic>;
    return FieldModel.fromJson({
      'id': row['id'],
      'name': row['name'],
      'area': row['area'],
      'crop': row['crop'],
      'status': row['status'],
      'polygon': polygon,
      'photoPaths': photos,
    });
  }
}
