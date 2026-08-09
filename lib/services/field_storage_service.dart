import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/distance_measurement.dart';
import '../models/field_model.dart';
import 'field_database.dart';

/// Local persistence facade for field data and measurement history.
class FieldStorageService {
  static const _legacyKey = 'agrico_fields_v1';
  static const _migrationKey = 'agrico_fields_sqlite_migrated_v1';

  final FieldDatabase _database;
  final FirebaseFirestore _firestore;

  FieldStorageService({FieldDatabase? database, FirebaseFirestore? firestore})
      : _database = database ?? FieldDatabase(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<FieldModel>> loadFields() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_migrationKey) ?? false;

    if (!migrated) {
      await _migrateLegacyData(prefs);
      await prefs.setBool(_migrationKey, true);
    }

    return _database.getAll();
  }

  Future<void> saveField(FieldModel field) => _database.upsert(field);

  Future<void> recordMeasurement(FieldModel field) => _database.addMeasurementHistory(field);

  Future<List<FieldMeasurementHistory>> loadMeasurementHistory({String? fieldId}) => _database.getMeasurementHistory(fieldId: fieldId);

  Future<void> saveFields(List<FieldModel> fields) async {
    for (final field in fields) {
      await _database.upsert(field);
    }
  }

  Future<void> deleteField(String id) => _database.delete(id);

  Future<void> saveDistanceMeasurement(DistanceMeasurement measurement) async {
    await _database.addDistanceMeasurement(measurement);
    await _firestore.collection('distance_measurements').doc(measurement.id).set({
      'points': measurement.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(growable: false),
      'segmentDistances': measurement.segmentDistances,
      'totalDistance': measurement.totalDistance,
      'measuredAt': Timestamp.fromDate(measurement.measuredAt.toUtc()),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<DistanceMeasurement>> loadDistanceMeasurements() => _database.getDistanceMeasurements();

  Future<void> deleteDistanceMeasurement(String id) async {
    await _database.deleteDistanceMeasurement(id);
    await _firestore.collection('distance_measurements').doc(id).delete();
  }

  Future<void> _migrateLegacyData(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_legacyKey) ?? const [];
    for (final item in raw) {
      try {
        final json = jsonDecode(item) as Map<String, dynamic>;
        await _database.upsert(FieldModel.fromJson(json));
      } catch (_) {
        // Ignore one malformed legacy record and continue migrating the rest.
      }
    }
  }
}
