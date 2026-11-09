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

  /// Marker row name for the P02A migration ledger.
  static const _migrationLedgerTable = 'agrico_schema_migrations';

  final DatabaseExecutor _executor;
  final bool _spatialWriteScope;
  final void Function(String farmId, String parcelId)? _onSpatialWrite;

  /// Creates the canonical schema for a fresh database.
  ///
  /// The fresh schema already carries the P02A typed columns and triggers,
  /// so a new database and an upgraded database share the same final shape.
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
        project_id TEXT,
        kind TEXT NOT NULL DEFAULT 'landBlock',
        parent_block_id TEXT,
        UNIQUE(farm_id, parcel_code),
        FOREIGN KEY (parent_block_id) REFERENCES $parcelTable(id)
          ON UPDATE RESTRICT ON DELETE RESTRICT
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_land_parcels_project_kind '
      'ON $parcelTable(project_id, kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_land_parcels_parent '
      'ON $parcelTable(parent_block_id)',
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_migrationLedgerTable (
        id TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL
      )
    ''');
    await _createParentTriggers(db);
  }

  /// Adds the P02A typed columns to an existing database.
  ///
  /// Runs exactly once per database: a ledger row records completion, and
  /// any error rolls back the DDL, the backfill and the ledger entry. The
  /// function accepts a [DatabaseExecutor] so callers can wrap it inside a
  /// transaction when needed.
  static Future<void> migrateAddTypedColumns(DatabaseExecutor db) async {
    // Ledger lookup.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_migrationLedgerTable (
        id TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL
      )
    ''');
    final ledger = await db.query(
      _migrationLedgerTable,
      where: 'id = ?',
      whereArgs: ['p02a_add_typed_columns'],
      limit: 1,
    );
    if (ledger.isNotEmpty) return;

    // Detect column presence.
    final columns = await db.rawQuery('PRAGMA table_info($parcelTable)');
    final names = columns.map((row) => row['name'] as String).toSet();

    // Additive column additions (idempotent per-column).
    if (!names.contains('project_id')) {
      await db.execute('ALTER TABLE $parcelTable ADD COLUMN project_id TEXT');
    }
    if (!names.contains('kind')) {
      await db.execute(
        "ALTER TABLE $parcelTable ADD COLUMN kind TEXT NOT NULL DEFAULT 'landBlock'",
      );
    }
    if (!names.contains('parent_block_id')) {
      await db.execute(
        'ALTER TABLE $parcelTable ADD COLUMN parent_block_id TEXT',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_land_parcels_project_kind '
      'ON $parcelTable(project_id, kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_land_parcels_parent '
      'ON $parcelTable(parent_block_id)',
    );

    // Install triggers BEFORE the backfill, so the backfill itself is
    // validated by the same rules used at runtime.
    await _createParentTriggers(db);

    // Backfill from payload_json. Any malformed payload aborts the whole
    // migration — no silent skipping.
    final rows = await db.query(
      parcelTable,
      columns: ['id', 'payload_json', 'kind', 'parent_block_id'],
    );
    for (final row in rows) {
      final id = row['id'] as String;
      final rawPayload = row['payload_json'];
      if (rawPayload is! String) {
        throw FormatException(
          'Parcel $id: payload_json is not a string during P02A migration.',
        );
      }
      final Map<String, Object?> payload;
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is! Map) {
          throw FormatException(
            'Parcel $id: payload_json is not a JSON object.',
          );
        }
        payload = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } on FormatException {
        rethrow;
      } catch (error) {
        throw FormatException(
          'Parcel $id: payload_json could not be decoded: $error',
        );
      }

      final metadataRaw = payload['legacyMetadata'];
      final Map<String, Object?> metadata;
      if (metadataRaw == null) {
        metadata = const {};
      } else if (metadataRaw is Map) {
        metadata = metadataRaw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else {
        throw FormatException(
          'Parcel $id: legacyMetadata is not a JSON object.',
        );
      }

      // Determine the kind.
      final rawKind = metadata['parcelLayer'];
      final String expectedKind;
      if (rawKind == null) {
        expectedKind = 'landBlock';
      } else if (rawKind == 'landBlock') {
        expectedKind = 'landBlock';
      } else if (rawKind == 'fieldPlot') {
        expectedKind = 'fieldPlot';
      } else {
        throw FormatException(
          'Parcel $id: unsupported legacy parcelLayer value: $rawKind',
        );
      }

      // Determine parent (only meaningful for fieldPlot).
      final rawParent = metadata['parentLandBlockId'];
      final String? expectedParent;
      if (rawParent == null) {
        expectedParent = null;
      } else if (rawParent is String && rawParent.isNotEmpty) {
        if (expectedKind != 'fieldPlot') {
          throw FormatException(
            'Parcel $id: land block carries a parentLandBlockId in legacy metadata.',
          );
        }
        expectedParent = rawParent;
      } else {
        throw FormatException(
          'Parcel $id: parentLandBlockId must be a non-empty string.',
        );
      }

      final currentKind = row['kind'] as String?;
      final currentParent = row['parent_block_id'] as String?;
      final needsUpdate =
          currentKind != expectedKind || currentParent != expectedParent;
      if (needsUpdate) {
        // The triggers installed above validate this UPDATE, including the
        // parent link, farm, project and self-reference checks.
        await db.update(
          parcelTable,
          {'kind': expectedKind, 'parent_block_id': expectedParent},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    // Final sanity check after backfill: no self-reference, no orphan.
    // Runs BEFORE the ledger row, so a broken database never records the
    // migration as complete.
    final broken = await db.rawQuery('''
      SELECT id FROM $parcelTable
      WHERE parent_block_id IS NOT NULL
        AND (parent_block_id = id
             OR parent_block_id NOT IN (SELECT id FROM $parcelTable))
    ''');
    if (broken.isNotEmpty) {
      final ids = broken.map((row) => row['id']).join(', ');
      throw FormatException(
        'P02A migration left orphan or self-referencing parcels: $ids',
      );
    }
    final stillBadKind = await db.rawQuery('''
      SELECT id FROM $parcelTable
      WHERE kind NOT IN ('landBlock', 'fieldPlot')
    ''');
    if (stillBadKind.isNotEmpty) {
      final ids = stillBadKind.map((row) => row['id']).join(', ');
      throw FormatException(
        'P02A migration left parcels with unsupported kind: $ids',
      );
    }

    // Record completion.
    await db.insert(
      _migrationLedgerTable,
      {
        'id': 'p02a_add_typed_columns',
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Parent integrity triggers. Installed on both fresh and upgraded
  /// databases so both share the same final behaviour.
  static Future<void> _createParentTriggers(DatabaseExecutor db) async {
    // Cleanup of superseded trigger names so the canonical set always wins.
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_land_parcels_parent_protect_update',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_kind_check_insert
      BEFORE INSERT ON $parcelTable
      FOR EACH ROW
      WHEN NEW.kind NOT IN ('landBlock', 'fieldPlot')
      BEGIN
        SELECT RAISE(ABORT, 'land_parcels.kind must be landBlock or fieldPlot');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_kind_check_update
      BEFORE UPDATE OF kind ON $parcelTable
      FOR EACH ROW
      WHEN NEW.kind NOT IN ('landBlock', 'fieldPlot')
      BEGIN
        SELECT RAISE(ABORT, 'land_parcels.kind must be landBlock or fieldPlot');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_check_insert
      BEFORE INSERT ON $parcelTable
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.parent_block_id IS NOT NULL AND NEW.kind != 'fieldPlot'
            THEN RAISE(ABORT, 'only field plots may have a parent block id')
          WHEN NEW.parent_block_id IS NOT NULL AND NEW.parent_block_id = NEW.id
            THEN RAISE(ABORT, 'a parcel cannot be its own parent')
        END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_check_update
      BEFORE UPDATE OF parent_block_id, kind ON $parcelTable
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.parent_block_id IS NOT NULL AND NEW.kind != 'fieldPlot'
            THEN RAISE(ABORT, 'only field plots may have a parent block id')
          WHEN NEW.parent_block_id IS NOT NULL AND NEW.parent_block_id = NEW.id
            THEN RAISE(ABORT, 'a parcel cannot be its own parent')
        END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_fk_insert
      BEFORE INSERT ON $parcelTable
      FOR EACH ROW
      WHEN NEW.parent_block_id IS NOT NULL
      BEGIN
        SELECT CASE
          WHEN (SELECT COUNT(*) FROM $parcelTable
                WHERE id = NEW.parent_block_id) = 0
            THEN RAISE(ABORT, 'parent block does not exist')
          WHEN (SELECT kind FROM $parcelTable
                WHERE id = NEW.parent_block_id) != 'landBlock'
            THEN RAISE(ABORT, 'parent must be a land block')
          WHEN (SELECT farm_id FROM $parcelTable
                WHERE id = NEW.parent_block_id) != NEW.farm_id
            THEN RAISE(ABORT, 'parent block must share the same farm')
          WHEN (SELECT project_id FROM $parcelTable
                WHERE id = NEW.parent_block_id) IS NOT NULL
               AND NEW.project_id IS NOT NULL
               AND (SELECT project_id FROM $parcelTable
                    WHERE id = NEW.parent_block_id) != NEW.project_id
            THEN RAISE(ABORT, 'parent block and field plot must share the same project')
        END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_fk_update
      BEFORE UPDATE OF parent_block_id, farm_id, project_id ON $parcelTable
      FOR EACH ROW
      WHEN NEW.parent_block_id IS NOT NULL
      BEGIN
        SELECT CASE
          WHEN (SELECT COUNT(*) FROM $parcelTable
                WHERE id = NEW.parent_block_id) = 0
            THEN RAISE(ABORT, 'parent block does not exist')
          WHEN (SELECT kind FROM $parcelTable
                WHERE id = NEW.parent_block_id) != 'landBlock'
            THEN RAISE(ABORT, 'parent must be a land block')
          WHEN (SELECT farm_id FROM $parcelTable
                WHERE id = NEW.parent_block_id) != NEW.farm_id
            THEN RAISE(ABORT, 'parent block must share the same farm')
          WHEN (SELECT project_id FROM $parcelTable
                WHERE id = NEW.parent_block_id) IS NOT NULL
               AND NEW.project_id IS NOT NULL
               AND (SELECT project_id FROM $parcelTable
                    WHERE id = NEW.parent_block_id) != NEW.project_id
            THEN RAISE(ABORT, 'parent block and field plot must share the same project')
        END;
      END
    ''');
    // Block destructive parent updates that would orphan children.
    // Covers kind, id, farm_id and project_id changes when the row has
    // children pointing at it.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_protect_update
      BEFORE UPDATE OF kind, id, farm_id, project_id ON $parcelTable
      FOR EACH ROW
      WHEN (SELECT COUNT(*) FROM $parcelTable
            WHERE parent_block_id = OLD.id) > 0
      BEGIN
        SELECT CASE
          WHEN NEW.kind != 'landBlock'
            THEN RAISE(ABORT, 'a parcel that has children cannot leave the land block kind')
          WHEN NEW.id != OLD.id
            THEN RAISE(ABORT, 'a parcel that has children cannot change its id')
          WHEN NEW.farm_id != OLD.farm_id
            THEN RAISE(ABORT, 'a parcel that has children cannot change its farm')
          WHEN EXISTS (
                SELECT 1 FROM $parcelTable child
                WHERE child.parent_block_id = OLD.id
                  AND child.project_id IS NOT NULL
                  AND (NEW.project_id IS NULL
                       OR child.project_id != NEW.project_id)
              )
            THEN RAISE(ABORT, 'a parcel that has children cannot change to a conflicting project')
        END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_land_parcels_parent_orphan_delete
      BEFORE DELETE ON $parcelTable
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN (SELECT COUNT(*) FROM $parcelTable
                WHERE parent_block_id = OLD.id) > 0
            THEN RAISE(ABORT, 'cannot delete a land block that still has field plots')
        END;
      END
    ''');
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
    'project_id': parcel.projectId,
    'kind': _kindColumnValue(parcel.kind),
    'parent_block_id': parcel.parentBlockId,
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
    // P02A: enrich with typed columns when they are present.
    if (parcelRow.containsKey('project_id')) {
      parcelJson['projectId'] = parcelRow['project_id'];
    }
    if (parcelRow.containsKey('kind') && parcelRow['kind'] is String) {
      parcelJson['kind'] = parcelRow['kind'];
    }
    if (parcelRow.containsKey('parent_block_id')) {
      parcelJson['parentBlockId'] = parcelRow['parent_block_id'];
    }
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

  static String _kindColumnValue(ParcelLayer kind) => switch (kind) {
    ParcelLayer.landBlock => 'landBlock',
    ParcelLayer.fieldPlot => 'fieldPlot',
  };

  static Map<String, Object?> _decodeObject(Object? value) {
    final decoded = jsonDecode(value! as String);
    if (decoded is! Map) throw const FormatException('Expected JSON object.');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}