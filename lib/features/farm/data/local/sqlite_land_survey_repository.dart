import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/land_survey.dart';
import '../../domain/repositories/land_survey_repository.dart';
import '../models/land_survey_mapper.dart';
import 'sqlite_land_parcel_repository.dart';

class SqliteLandSurveyRepository implements LandSurveyRepository {
  SqliteLandSurveyRepository(Database database) : _executor = database;
  SqliteLandSurveyRepository._(this._executor);

  static const schemaVersion = 1;
  static const householdsTable = 'households';
  static const surveysTable = 'land_parcel_surveys';
  static const landUseTable = 'land_use_profiles';
  static const cropsTable = 'land_parcel_crops';
  static const attachmentsTable = 'land_parcel_attachments';
  final DatabaseExecutor _executor;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await SqliteLandParcelRepository.createSchema(db);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''CREATE TABLE IF NOT EXISTS $householdsTable (
      id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, household_code TEXT NOT NULL,
      active INTEGER NOT NULL, schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL,
      UNIQUE(farm_id, household_code))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_households_farm ON $householdsTable(farm_id, active)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS $surveysTable (
      id TEXT PRIMARY KEY, parcel_id TEXT NOT NULL, boundary_version INTEGER NOT NULL,
      schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
      UNIQUE(parcel_id, id))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_surveys_parcel ON $surveysTable(parcel_id, boundary_version)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $landUseTable (
      parcel_id TEXT PRIMARY KEY, schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id) ON UPDATE RESTRICT ON DELETE RESTRICT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $cropsTable (
      id TEXT PRIMARY KEY, parcel_id TEXT NOT NULL, active INTEGER NOT NULL,
      schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id) ON UPDATE RESTRICT ON DELETE RESTRICT)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crops_parcel ON $cropsTable(parcel_id, active)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $attachmentsTable (
      id TEXT PRIMARY KEY, parcel_id TEXT NOT NULL, attachment_type TEXT NOT NULL,
      schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL,
      FOREIGN KEY(parcel_id) REFERENCES ${SqliteLandParcelRepository.parcelTable}(id) ON UPDATE RESTRICT ON DELETE RESTRICT)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_parcel ON $attachmentsTable(parcel_id, attachment_type)',
    );
  }

  @override
  Future<void> createHousehold(Household value) => _executor
      .insert(
        householdsTable,
        _householdRow(value),
        conflictAlgorithm: ConflictAlgorithm.abort,
      )
      .then((_) {});
  @override
  Future<void> updateHousehold(Household value) =>
      _update(householdsTable, _householdRow(value), value.id);
  @override
  Future<Household?> getHousehold(String id) =>
      _one(householdsTable, id, LandSurveyMapper.householdFromJson);
  @override
  Future<List<Household>> listHouseholds(String farmId) => _list(
    householdsTable,
    'farm_id = ?',
    [farmId],
    LandSurveyMapper.householdFromJson,
  );
  @override
  Future<void> createSurvey(LandParcelSurvey value) => _executor
      .insert(surveysTable, {
        'id': value.id,
        'parcel_id': value.parcelId,
        'boundary_version': value.boundaryVersion,
        'schema_version': value.schemaVersion,
        'payload_json': jsonEncode(LandSurveyMapper.surveyToJson(value)),
      }, conflictAlgorithm: ConflictAlgorithm.abort)
      .then((_) {});
  @override
  Future<List<LandParcelSurvey>> listSurveys(String parcelId) => _list(
    surveysTable,
    'parcel_id = ?',
    [parcelId],
    LandSurveyMapper.surveyFromJson,
  );
  @override
  Future<void> saveLandUseProfile(LandUseProfile value) async {
    final row = {
      'parcel_id': value.parcelId,
      'schema_version': value.schemaVersion,
      'payload_json': jsonEncode(LandSurveyMapper.landUseToJson(value)),
    };
    final updated = await _executor.update(
      landUseTable,
      row,
      where: 'parcel_id = ?',
      whereArgs: [value.parcelId],
    );
    if (updated == 0) {
      await _executor.insert(
        landUseTable,
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  @override
  Future<LandUseProfile?> getLandUseProfile(String parcelId) => _one(
    landUseTable,
    parcelId,
    LandSurveyMapper.landUseFromJson,
    idColumn: 'parcel_id',
  );
  @override
  Future<void> createCrop(CropRecord value) => _executor
      .insert(
        cropsTable,
        _cropRow(value),
        conflictAlgorithm: ConflictAlgorithm.abort,
      )
      .then((_) {});
  @override
  Future<void> updateCrop(CropRecord value) =>
      _update(cropsTable, _cropRow(value), value.id);
  @override
  Future<List<CropRecord>> listCrops(
    String parcelId, {
    bool includeInactive = false,
  }) => _list(
    cropsTable,
    includeInactive ? 'parcel_id = ?' : 'parcel_id = ? AND active = 1',
    [parcelId],
    LandSurveyMapper.cropFromJson,
  );
  @override
  Future<void> createAttachment(ParcelAttachment value) => _executor
      .insert(attachmentsTable, {
        'id': value.id,
        'parcel_id': value.parcelId,
        'attachment_type': value.attachmentType.name,
        'schema_version': value.schemaVersion,
        'payload_json': jsonEncode(LandSurveyMapper.attachmentToJson(value)),
      }, conflictAlgorithm: ConflictAlgorithm.abort)
      .then((_) {});
  @override
  Future<List<ParcelAttachment>> listAttachments(String parcelId) => _list(
    attachmentsTable,
    'parcel_id = ?',
    [parcelId],
    LandSurveyMapper.attachmentFromJson,
  );

  @override
  Future<T> transaction<T>(
    Future<T> Function(LandSurveyRepository repository) action,
  ) async {
    if (_executor is Transaction) return action(this);
    return (_executor as Database).transaction(
      (txn) => action(SqliteLandSurveyRepository._(txn)),
    );
  }

  Map<String, Object?> _householdRow(Household value) => {
    'id': value.id,
    'farm_id': value.farmId,
    'household_code': value.householdCode,
    'active': value.active ? 1 : 0,
    'schema_version': value.schemaVersion,
    'payload_json': jsonEncode(LandSurveyMapper.householdToJson(value)),
  };
  Map<String, Object?> _cropRow(CropRecord value) => {
    'id': value.id,
    'parcel_id': value.parcelId,
    'active': value.active ? 1 : 0,
    'schema_version': value.schemaVersion,
    'payload_json': jsonEncode(LandSurveyMapper.cropToJson(value)),
  };
  Future<void> _update(
    String table,
    Map<String, Object?> row,
    String id,
  ) async {
    if (await _executor.update(table, row, where: 'id = ?', whereArgs: [id]) !=
        1) {
      throw StateError('$table/$id does not exist.');
    }
  }

  Future<T?> _one<T>(
    String table,
    String id,
    T Function(Map<String, Object?>) decode, {
    String idColumn = 'id',
  }) async {
    final rows = await _executor.query(
      table,
      columns: ['payload_json'],
      where: '$idColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : decode(_decode(rows.single['payload_json']));
  }

  Future<List<T>> _list<T>(
    String table,
    String where,
    List<Object?> args,
    T Function(Map<String, Object?>) decode,
  ) async {
    final rows = await _executor.query(
      table,
      columns: ['payload_json'],
      where: where,
      whereArgs: args,
      orderBy: 'id',
    );
    return List.unmodifiable(
      rows.map((row) => decode(_decode(row['payload_json']))),
    );
  }

  static Map<String, Object?> _decode(Object? value) =>
      (jsonDecode(value! as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
}
