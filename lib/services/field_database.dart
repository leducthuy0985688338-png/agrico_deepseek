import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/distance_measurement.dart';
import '../models/field_measurement_history.dart';
import '../models/field_model.dart';
import '../features/farm/data/local/sqlite_land_parcel_repository.dart';

class FieldDatabase {
  static const _databaseName = 'agrico.db';
  static const _databaseVersion = 5;
  static const _table = 'fields';
  static const _historyTable = 'field_measurement_history';
  static const _distanceTable = 'distance_measurements';

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
        await db.execute(
          'CREATE INDEX idx_fields_updated_at ON $_table(updated_at)',
        );
        await _createHistoryTable(db);
        await _createDistanceTable(db);
        await SqliteLandParcelRepository.createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN perimeter REAL NOT NULL DEFAULT 0",
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN measurement_method TEXT NOT NULL DEFAULT 'unknown'",
          );
          await db.execute('ALTER TABLE $_table ADD COLUMN gps_accuracy REAL');
          await db.execute('ALTER TABLE $_table ADD COLUMN measured_at TEXT');
        }
        if (oldVersion < 3) await _createHistoryTable(db);
        if (oldVersion < 4) await _createDistanceTable(db);
        if (oldVersion < 5) {
          await SqliteLandParcelRepository.createSchema(db);
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_field ON $_historyTable(field_id, created_at DESC)',
    );
  }

  Future<void> _createDistanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_distanceTable (
        id TEXT PRIMARY KEY,
        points TEXT NOT NULL,
        segment_distances TEXT NOT NULL,
        total_distance REAL NOT NULL,
        measured_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_distance_created ON $_distanceTable(created_at DESC)',
    );
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

  Future<void> replaceAll(List<FieldModel> fields) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_table);
      for (final field in fields) {
        await transaction.insert(
          _table,
          _toRow(field),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    await db.delete(_historyTable, where: 'field_id = ?', whereArgs: [id]);
  }

  Future<FieldMeasurementHistory> addMeasurementHistory(
    FieldModel field,
  ) async {
    final db = await database;
    final createdAt = DateTime.now().toUtc();
    final measurement = FieldMeasurementHistory(
      id: '${field.id}_${createdAt.microsecondsSinceEpoch}',
      fieldId: field.id,
      fieldName: field.name,
      measurementMethod: field.measurementMethod,
      polygon: List.unmodifiable(field.polygon),
      area: field.area,
      perimeter: field.perimeter,
      gpsAccuracy: field.gpsAccuracy,
      measuredAt: (field.measuredAt ?? createdAt).toUtc(),
      createdAt: createdAt,
    );
    await db.insert(
      _historyTable,
      _historyToRow(measurement),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return measurement;
  }

  Future<void> replaceMeasurementHistory(
    List<FieldMeasurementHistory> measurements,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_historyTable);
      for (final measurement in measurements) {
        await transaction.insert(
          _historyTable,
          _historyToRow(measurement),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<FieldMeasurementHistory>> getMeasurementHistory({
    String? fieldId,
  }) async {
    final db = await database;
    final rows = await db.query(
      _historyTable,
      where: fieldId == null ? null : 'field_id = ?',
      whereArgs: fieldId == null ? null : [fieldId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((row) {
          final rawPolygon =
              jsonDecode(row['polygon']! as String) as List<dynamic>;
          return FieldMeasurementHistory(
            id: row['id']! as String,
            fieldId: row['field_id']! as String,
            fieldName: row['field_name']! as String,
            measurementMethod: row['measurement_method']! as String,
            polygon: rawPolygon
                .map((point) {
                  final item = point as Map<String, dynamic>;
                  return LatLng(
                    (item['lat'] as num).toDouble(),
                    (item['lng'] as num).toDouble(),
                  );
                })
                .toList(growable: false),
            area: (row['area']! as num).toDouble(),
            perimeter: (row['perimeter']! as num).toDouble(),
            gpsAccuracy: (row['gps_accuracy'] as num?)?.toDouble(),
            measuredAt: DateTime.parse(row['measured_at']! as String),
            createdAt: DateTime.parse(row['created_at']! as String),
          );
        })
        .toList(growable: false);
  }

  Future<void> addDistanceMeasurement(DistanceMeasurement measurement) async {
    final db = await database;
    await db.insert(
      _distanceTable,
      _distanceToRow(measurement),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceDistanceMeasurements(
    List<DistanceMeasurement> measurements,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_distanceTable);
      for (final measurement in measurements) {
        await transaction.insert(
          _distanceTable,
          _distanceToRow(measurement, createdAt: measurement.measuredAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<DistanceMeasurement>> getDistanceMeasurements() async {
    final db = await database;
    final rows = await db.query(_distanceTable, orderBy: 'created_at DESC');
    return rows
        .map((row) {
          final rawPoints =
              jsonDecode(row['points']! as String) as List<dynamic>;
          final rawSegments =
              jsonDecode(row['segment_distances']! as String) as List<dynamic>;
          return DistanceMeasurement(
            id: row['id']! as String,
            points: rawPoints
                .map((point) {
                  final item = point as Map<String, dynamic>;
                  return LatLng(
                    (item['lat'] as num).toDouble(),
                    (item['lng'] as num).toDouble(),
                  );
                })
                .toList(growable: false),
            segmentDistances: rawSegments
                .map((e) => (e as num).toDouble())
                .toList(growable: false),
            totalDistance: (row['total_distance']! as num).toDouble(),
            measuredAt: DateTime.parse(row['measured_at']! as String),
          );
        })
        .toList(growable: false);
  }

  Future<void> deleteDistanceMeasurement(String id) async {
    final db = await database;
    await db.delete(_distanceTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Map<String, Object?> _historyToRow(FieldMeasurementHistory measurement) => {
    'id': measurement.id,
    'field_id': measurement.fieldId,
    'field_name': measurement.fieldName,
    'measurement_method': measurement.measurementMethod,
    'polygon': jsonEncode(
      measurement.polygon
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(growable: false),
    ),
    'area': measurement.area,
    'perimeter': measurement.perimeter,
    'gps_accuracy': measurement.gpsAccuracy,
    'measured_at': measurement.measuredAt.toUtc().toIso8601String(),
    'created_at': measurement.createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> _distanceToRow(
    DistanceMeasurement measurement, {
    DateTime? createdAt,
  }) => {
    'id': measurement.id,
    'points': jsonEncode(
      measurement.points
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(growable: false),
    ),
    'segment_distances': jsonEncode(measurement.segmentDistances),
    'total_distance': measurement.totalDistance,
    'measured_at': measurement.measuredAt.toUtc().toIso8601String(),
    'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  Map<String, Object?> _toRow(FieldModel field) => {
    'id': field.id,
    'name': field.name,
    'area': field.area,
    'crop': field.crop,
    'status': field.status,
    'polygon': jsonEncode(
      field.polygon
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(growable: false),
    ),
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
