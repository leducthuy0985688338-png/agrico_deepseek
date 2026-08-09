import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/field_model.dart';
import 'field_database.dart';

/// Local persistence facade for field data.
///
/// SQLite is the source of truth. Existing SharedPreferences data is migrated
/// once so users do not lose fields created by earlier builds.
class FieldStorageService {
  static const _legacyKey = 'agrico_fields_v1';
  static const _migrationKey = 'agrico_fields_sqlite_migrated_v1';

  final FieldDatabase _database;

  FieldStorageService({FieldDatabase? database})
      : _database = database ?? FieldDatabase();

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

  Future<void> saveFields(List<FieldModel> fields) async {
    for (final field in fields) {
      await _database.upsert(field);
    }
  }

  Future<void> deleteField(String id) => _database.delete(id);

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
