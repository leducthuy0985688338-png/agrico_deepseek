import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/distance_measurement.dart';
import '../models/field_model.dart';
import 'field_database.dart';

/// Local persistence facade for field data and measurement history.
class FieldStorageService {
  static const _legacyKey = 'agrico_fields_v1';
  static const _migrationKey = 'agrico_fields_sqlite_migrated_v1';

  final FieldDatabase _database;

  FieldStorageService({FieldDatabase? database}) : _database = database ?? FieldDatabase();

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

  Future<void> replaceFields(List<FieldModel> fields) =>
      _database.replaceAll(fields);

  Future<void> deleteField(String id) => _database.delete(id);

  Future<bool> saveDistanceMeasurement(
    DistanceMeasurement measurement,
  ) async {
    await _database.addDistanceMeasurement(measurement);
    try {
      await _ensureFirebase();
      await FirebaseFirestore.instance
          .collection('distance_measurements')
          .doc(measurement.id)
          .set({
        ...measurement.toJson(),
        'measuredAt': Timestamp.fromDate(measurement.measuredAt.toUtc()),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DistanceMeasurement>> loadDistanceMeasurements() =>
      _database.getDistanceMeasurements();

  Future<void> replaceDistanceMeasurements(
    List<DistanceMeasurement> measurements,
  ) =>
      _database.replaceDistanceMeasurements(measurements);

  Future<void> deleteDistanceMeasurement(String id) async {
    await _database.deleteDistanceMeasurement(id);
    await _ensureFirebase();
    await FirebaseFirestore.instance.collection('distance_measurements').doc(id).delete();
  }

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
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
