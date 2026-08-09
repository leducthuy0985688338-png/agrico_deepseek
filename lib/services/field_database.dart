import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/field_model.dart';

class FieldMeasurementHistory {
  final String id;
  final String fieldId;
  final String fieldName;
  final String measurementMethod;
  final List<LatLng> polygon;
  final double area;
  final double perimeter;
  final double? gpsAccuracy;
  final DateTime measuredAt;
  final DateTime createdAt;

  const FieldMeasurementHistory({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.measurementMethod,
    required this.polygon,
    required this.area,
    required this.perimeter,
    required this.measuredAt,
    required this.createdAt,
    this.gpsAccuracy,
  });
}

class FieldDatabase {
  static const _databaseName = 'agrico.db';
  static const _databaseVersion = 3;
  static const _table = 'fields';
  static const _historyTable = 'field_measurement_history';

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
            perimeter REAL NOT NULL DEFAULT 0,
            measurement_method TEXT NOT NULL DEFAULT 'unknown',
            gps_accuracy REAL,
            measured_at TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_fields_updated_at ON $_table(updated_at)');
        await _createHistoryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE $_table ADD COLUMN perimeter REAL NOT NULL DEFAULT 0");
          await db.execute("ALTER TABLE $_table ADD COLUMN measurement_method TEXT NOT NULL DEFAULT 'unknown'");
          await db.execute('ALTER TABLE $_table ADD COLUMN gps_accuracy REAL');
          await db.execute('ALTER TABLE $_table ADD COLUMN measured_at TEXT');
        }
        if (oldVersion < 3) {
          await _createHistoryTable(db);
        }
      },
    );
    return _database!;
  }

  Future<void> _createHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_historyTable (
        id TEXT PRIMARY KEY,
        field_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        measurement_method TEXT NOT NULL,
        polygon TEXT NOT NULL,
        area REAL NOT NULL,
        perimeter REAL NOT NULL DEFAULT 0,
        gps_accuracy REAL,
        measured_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_history_field ON $_historyTable(field_id, created_at DESC)');
  }

  Future<List<FieldModel>> getAll() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'updated_at DESC');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(FieldModel field) async {
    final db = await database;
    await db.insert(_table, _toRow(field), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    await db.delete(_historyTable, where: 'field_id = ?', whereArgs: [id]);
  }

  Future<void> addMeasurementHistory(FieldModel field) async {
    final db = await database;
    final measuredAt = field.measuredAt ?? DateTime.now().toUtc();
    await db.insert(_historyTable, {
      'id': '${field.id}_${DateTime.now().microsecondsSinceEpoch}',
      'field_id': field.id,
      'field_name': field.name,
      'measurement_method': field.measurementMethod,
      'polygon': jsonEncode(field.polygon.map((point) => {'lat': point.latitude, 'lng': point.longitude}).toList(growable: false)),
      'area': field.area,
      'perimeter': field.perimeter,
      'gps_accuracy': field.gpsAccuracy,
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<FieldMeasurementHistory>> getMeasurementHistory({String? fieldId}) async {
    final db = await database;
    final rows = await db.query(
      _historyTable,
      where: fieldId == null ? null : 'field_id = ?',
      whereArgs: fieldId == null ? null : [fieldId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      final rawPolygon = jsonDecode(row['polygon']! as String) as List<dynamic>;
      return FieldMeasurementHistory(
        id: row['id']! as String,
        fieldId: row['field_id']! as String,
        fieldName: row['field_name']! as String,
        measurementMethod: row['measurement_method']! as String,
        polygon: rawPolygon.map((point) {
          final item = point as Map<String, dynamic>;
          return LatLng((item['lat'] as num).toDouble(), (item['lng'] as num).toDouble());
        }).toList(growable: false),
        area: (row['area']! as num).toDouble(),
        perimeter: (row['perimeter']! as num).toDouble(),
        gpsAccuracy: (row['gps_accuracy'] as num?)?.toDouble(),
        measuredAt: DateTime.parse(row['measured_at']! as String),
        createdAt: DateTime.parse(row['created_at']! as String),
      );
    }).toList(growable: false);
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
        'polygon': jsonEncode(field.polygon.map((point) => {'lat': point.latitude, 'lng': point.longitude}).toList(growable: false)),
        'photo_paths': jsonEncode(field.photoPaths),
        'perimeter': field.perimeter,
        'measurement_method': field.measurementMethod,
        'gps_accuracy': field.gpsAccuracy,
        'measured_at': field.measuredAt?.toUtc().toIso8601String(),
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
      'perimeter': row['perimeter'],
      'measurementMethod': row['measurement_method'],
      'gpsAccuracy': row['gps_accuracy'],
      'measuredAt': row['measured_at'],
    });
  }
}
