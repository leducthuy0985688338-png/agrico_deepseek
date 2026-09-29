import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/land_parcel.dart';
import '../../domain/repositories/land_parcel_repository.dart';
import '../models/land_parcel_mapper.dart';

class SqliteLandParcelRepository implements LandParcelRepository {
  SqliteLandParcelRepository(DatabaseExecutor executor)
    : _executor = executor,
      _spatialWriteScope = false,
      _onSpatialWrite = null;

  /// Only the shared LandParcel/Spatial transaction coordinator uses this
  /// scope; direct repository transactions cannot authorize spatial writes.
  SqliteLandParcelRepository.spatialTransactionScope(
    Transaction transaction,
    void Function(String farmId, String parcelId) onSpatialWrite,
  )
    : _executor = transaction,
      _spatialWriteScope = true,
      _onSpatialWrite = onSpatialWrite;

  SqliteLandParcelRepository._(
    this._executor,
    this._spatialWriteScope,
    this._onSpatialWrite,
  );

  static const parcelTable = 'land_parcels';
  static const boundaryVersionTable = 'land_parcel_boundary_versions';

  final DatabaseExecutor _executor;
  final bool _spatialWriteScope;
  final void Function(String farmId, String parcelId)? _onSpatialWrite;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $parcelTable (
        id TEXT PRIMARY KEY,
        farm_id TEXT NOT NULL,
        parcel_code TEXT NOT NULL,
        active INTEGER NOT NULL,
        boundary_version INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(farm_id, parcel_code)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_land_parcels_farm '
      'ON $parcelTable(farm_id, active)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_land_parcels_farm_code '
      'ON $parcelTable(farm_id, parcel_code)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $boundaryVersionTable (
        id TEXT PRIMARY KEY,
        parcel_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(parcel_id, version),
        FOREIGN KEY(parcel_id) REFERENCES $parcelTable(id)
          ON UPDATE RESTRICT ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_boundary_parcel_version '
      'ON $boundaryVersionTable(parcel_id, version)',
    );
  }

  @override
  Future<LandParcel?> getById({
    required String farmId,
    required String id,
  }) async {
    final rows = await _executor.query(
      parcelTable,
      where: 'farm_id = ? AND id = ?',
      whereArgs: [farmId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.single);
  }

  @override
  Future<LandParcel?> getByParcelCode({
    required String farmId,
    required String parcelCode,
  }) async {
    final rows = await _executor.query(
      parcelTable,
      where: 'farm_id = ? AND parcel_code = ?',
      whereArgs: [farmId, parcelCode],
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.single);
  }

  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async {
    final rows = await _executor.query(
      parcelTable,
      where: includeInactive ? 'farm_id = ?' : 'farm_id = ? AND active = 1',
      whereArgs: [farmId],
      orderBy: 'parcel_code COLLATE NOCASE, id',
    );
    final parcels = <LandParcel>[];
    for (final row in rows) {
      parcels.add(await _hydrate(row));
    }
    return List.unmodifiable(parcels);
  }

  @override
  Future<void> create(LandParcel parcel) => transaction(
    (repository) =>
        (repository as SqliteLandParcelRepository)._createWithin(parcel),
  );

  @override
  Future<void> update(LandParcel parcel) => transaction((repository) async {
    final sqlite = repository as SqliteLandParcelRepository;
    final existing = await repository.getById(
      farmId: parcel.farmId,
      id: parcel.id,
    );
    if (existing == null) {
      throw StateError('Land parcel ${parcel.id} does not exist.');
    }
    if (existing.spatialFeatureId != null &&
        parcel.spatialFeatureId != existing.spatialFeatureId) {
      throw StateError('Established LandParcel spatial identity is immutable.');
    }
    if (existing.spatialFeatureId == null &&
        parcel.spatialFeatureId != null &&
        !sqlite._spatialWriteScope) {
      throw StateError('Spatial identity establishment requires the shared spatial transaction.');
    }
    final newHistory = parcel.boundaryHistory.where(
      (version) => version.version > existing.boundaryVersion,
    ).toList();
    if (newHistory.any((version) => version.version > parcel.boundaryVersion)) {
      throw StateError('Boundary history cannot advance beyond the current boundary version.');
    }
    final boundaryChanged = newHistory.isNotEmpty ||
        parcel.boundaryVersion != existing.boundaryVersion ||
        parcel.boundary != existing.boundary ||
        parcel.centroid != existing.centroid ||
        parcel.areaM2 != existing.areaM2 ||
        parcel.perimeterM != existing.perimeterM ||
        parcel.boundarySource != existing.boundarySource ||
        parcel.horizontalAccuracyM != existing.horizontalAccuracyM ||
        parcel.measuredAt != existing.measuredAt ||
        parcel.measuredBy != existing.measuredBy ||
        parcel.boundaryConfidence != existing.boundaryConfidence;
    if (boundaryChanged &&
        !sqlite._spatialWriteScope &&
        (existing.spatialFeatureId != null ||
            await sqlite._hasPersistedSpatialLink(parcel.id))) {
      throw StateError('Spatial-enabled LandParcel boundary write requires the shared spatial transaction.');
    }
    if (parcel.boundaryVersion < existing.boundaryVersion) {
      throw StateError(
        'A parcel update cannot move boundary history backwards.',
      );
    }
    for (final storedVersion in existing.boundaryHistory) {
      final submitted = parcel.boundaryHistory.where(
        (version) => version.version == storedVersion.version,
      );
      if (submitted.length != 1 ||
          jsonEncode(
                LandParcelMapper.boundaryVersionToJson(submitted.single),
              ) !=
              jsonEncode(
                LandParcelMapper.boundaryVersionToJson(storedVersion),
              )) {
        throw StateError(
          'Immutable boundary version ${storedVersion.version} was changed.',
        );
      }
    }
    for (final version in newHistory) {
      await sqlite._insertBoundaryVersion(version, ConflictAlgorithm.abort);
    }
    await sqlite._updateParcel(parcel);
    if (boundaryChanged ||
        existing.spatialFeatureId != parcel.spatialFeatureId) {
      sqlite._onSpatialWrite?.call(parcel.farmId, parcel.id);
    }
  });

  Future<void> _createWithin(LandParcel parcel) async {
    if (parcel.spatialFeatureId != null && !_spatialWriteScope) {
      throw StateError('Spatial-enabled LandParcel creation requires the shared spatial transaction.');
    }
    await _insertParcel(parcel, ConflictAlgorithm.abort);
    for (final version in parcel.boundaryHistory) {
      await _insertBoundaryVersion(version, ConflictAlgorithm.abort);
    }
    if (parcel.spatialFeatureId != null) {
      _onSpatialWrite?.call(parcel.farmId, parcel.id);
    }
  }

  @override
  Future<void> saveBoundaryVersion(LandParcelBoundaryVersion version) async {
    final rows = await _executor.query(
      parcelTable,
      columns: ['payload_json'],
      where: 'id = ?',
      whereArgs: [version.parcelId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final payload = jsonDecode(rows.single['payload_json']! as String)
          as Map<String, dynamic>;
      if (payload['spatialFeatureId'] != null ||
          await _hasPersistedSpatialLink(version.parcelId)) {
        throw StateError('Spatial-enabled LandParcel boundary history requires the shared spatial transaction.');
      }
    }
    await _insertBoundaryVersion(version, ConflictAlgorithm.abort);
  }

  @override
  Future<void> setActive({
    required String farmId,
    required String id,
    required bool active,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) async {
    final parcel = await getById(farmId: farmId, id: id);
    if (parcel == null) throw StateError('Land parcel $id does not exist.');
    final json = LandParcelMapper.toJson(parcel, includeHistory: false)
      ..['active'] = active
      ..['updatedAt'] = occurredAt.toUtc().toIso8601String()
      ..['updatedBy'] = actorMembershipId;
    await _executor.update(
      parcelTable,
      {'active': active ? 1 : 0, 'payload_json': jsonEncode(json)},
      where: 'farm_id = ? AND id = ?',
      whereArgs: [farmId, id],
    );
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(LandParcelRepository repository) action,
  ) async {
    if (_executor is Transaction) return action(this);
    final database = _executor as Database;
    return database.transaction(
      (transaction) => action(
        SqliteLandParcelRepository._(
          transaction,
          _spatialWriteScope,
          _onSpatialWrite,
        ),
      ),
    );
  }

  Future<void> _insertParcel(
    LandParcel parcel,
    ConflictAlgorithm conflictAlgorithm,
  ) async {
    await _executor.insert(
      parcelTable,
      _parcelRow(parcel),
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  Future<bool> _hasPersistedSpatialLink(String parcelId) async {
    final table = await _executor.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'land_parcel_spatial_links'",
    );
    if (table.isEmpty) return false;
    final links = await _executor.query(
      'land_parcel_spatial_links',
      columns: ['id'],
      where: 'land_parcel_id = ?',
      whereArgs: [parcelId],
      limit: 1,
    );
    return links.isNotEmpty;
  }

  Future<void> _updateParcel(LandParcel parcel) async {
    final updated = await _executor.update(
      parcelTable,
      _parcelRow(parcel),
      where: 'farm_id = ? AND id = ?',
      whereArgs: [parcel.farmId, parcel.id],
    );
    if (updated != 1) {
      throw StateError('Land parcel ${parcel.id} could not be updated.');
    }
  }

  Map<String, Object?> _parcelRow(LandParcel parcel) => {
    'id': parcel.id,
    'farm_id': parcel.farmId,
    'parcel_code': parcel.parcelCode,
    'active': parcel.active ? 1 : 0,
    'boundary_version': parcel.boundaryVersion,
    'schema_version': parcel.schemaVersion,
    'payload_json': jsonEncode(
      LandParcelMapper.toJson(parcel, includeHistory: false),
    ),
  };

  Future<void> _insertBoundaryVersion(
    LandParcelBoundaryVersion version,
    ConflictAlgorithm conflictAlgorithm,
  ) async {
    await _executor.insert(boundaryVersionTable, {
      'id': version.id,
      'parcel_id': version.parcelId,
      'version': version.version,
      'schema_version': LandParcel.currentSchemaVersion,
      'payload_json': jsonEncode(
        LandParcelMapper.boundaryVersionToJson(version),
      ),
    }, conflictAlgorithm: conflictAlgorithm);
  }

  Future<LandParcel> _hydrate(Map<String, Object?> parcelRow) async {
    final parcelJson = _decodeObject(parcelRow['payload_json']);
    final historyRows = await _executor.query(
      boundaryVersionTable,
      columns: ['payload_json'],
      where: 'parcel_id = ?',
      whereArgs: [parcelRow['id']],
      orderBy: 'version ASC',
    );
    return LandParcelMapper.fromJson(
      parcelJson,
      history: historyRows.map((row) => _decodeObject(row['payload_json'])),
    );
  }

  static Map<String, Object?> _decodeObject(Object? value) {
    final decoded = jsonDecode(value! as String);
    if (decoded is! Map) throw const FormatException('Expected JSON object.');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
