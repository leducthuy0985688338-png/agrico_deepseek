import 'package:sqflite/sqflite.dart';

import '../../domain/entities/land_parcel_spatial_link.dart';
import '../../domain/repositories/land_parcel_spatial_link_repository.dart';
import 'sqlite_land_parcel_repository.dart';

class SqliteLandParcelSpatialLinkRepository
    implements LandParcelSpatialLinkRepository {
  SqliteLandParcelSpatialLinkRepository(this._executor);

  static const table = 'land_parcel_spatial_links';

  final DatabaseExecutor _executor;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id TEXT PRIMARY KEY,
        land_parcel_id TEXT NOT NULL UNIQUE,
        spatial_feature_id TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        FOREIGN KEY(land_parcel_id)
          REFERENCES ${SqliteLandParcelRepository.parcelTable}(id)
          ON UPDATE RESTRICT ON DELETE RESTRICT,
        FOREIGN KEY(spatial_feature_id)
          REFERENCES spatial_features(id)
          ON UPDATE RESTRICT ON DELETE RESTRICT
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_land_parcel_spatial_link_parcel '
      'ON $table(land_parcel_id)',
    );

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_land_parcel_spatial_link_feature '
      'ON $table(spatial_feature_id)',
    );
  }

  @override
  Future<LandParcelSpatialLink?> findById(String id) =>
      _findOne('id = ?', [id]);

  @override
  Future<LandParcelSpatialLink?> findByLandParcelId(String landParcelId) =>
      _findOne('land_parcel_id = ?', [landParcelId]);

  @override
  Future<LandParcelSpatialLink?> findBySpatialFeatureId(
    String spatialFeatureId,
  ) => _findOne('spatial_feature_id = ?', [spatialFeatureId]);

  @override
  Future<void> create(LandParcelSpatialLink link) async {
    link.validate();
    await _executor.insert(
      table,
      _toRow(link),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<LandParcelSpatialLink?> _findOne(
    String where,
    List<Object?> whereArgs,
  ) async {
    final rows = await _executor.query(
      table,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );

    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  static Map<String, Object?> _toRow(LandParcelSpatialLink link) => {
    'id': link.id,
    'land_parcel_id': link.landParcelId,
    'spatial_feature_id': link.spatialFeatureId,
    'created_at': link.createdAt.toUtc().toIso8601String(),
    'created_by': link.createdBy,
    'schema_version': link.schemaVersion,
  };

  static LandParcelSpatialLink _fromRow(Map<String, Object?> row) {
    final createdAt = DateTime.tryParse(row['created_at']! as String);
    if (createdAt == null) {
      throw const FormatException(
        'Land parcel spatial link created_at must be ISO-8601 TEXT.',
      );
    }

    final link = LandParcelSpatialLink(
      id: row['id']! as String,
      landParcelId: row['land_parcel_id']! as String,
      spatialFeatureId: row['spatial_feature_id']! as String,
      createdAt: createdAt.toUtc(),
      createdBy: row['created_by']! as String,
      schemaVersion: row['schema_version']! as int,
    );

    link.validate();
    return link;
  }
}
