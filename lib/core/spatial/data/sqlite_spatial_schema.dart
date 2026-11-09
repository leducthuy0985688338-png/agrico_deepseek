import 'package:sqflite/sqflite.dart';

/// Creates the isolated SQLite storage foundation for Spatial Core.
abstract final class SqliteSpatialSchema {
  static const featuresTable = 'spatial_features';
  static const revisionsTable = 'spatial_feature_revisions';

  static Future<void> createSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS $featuresTable (
        id TEXT PRIMARY KEY NOT NULL,
        feature_type TEXT NOT NULL,
        geometry_type TEXT NOT NULL,
        lifecycle_status TEXT NOT NULL,
        project_id TEXT NULL,
        business_unit_id TEXT NULL,
        code TEXT NULL,
        name TEXT NULL,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        updated_by TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        geometry_json TEXT NULL,
        payload_json TEXT NOT NULL
      )
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS $revisionsTable (
        id TEXT PRIMARY KEY NOT NULL,
        feature_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        geometry_type TEXT NOT NULL,
        geometry_json TEXT NULL,
        geometry_reference TEXT NULL,
        temporal_state TEXT NOT NULL,
        valid_from TEXT NOT NULL,
        valid_to TEXT NULL,
        source_type TEXT NOT NULL,
        surveyed_at TEXT NULL,
        surveyed_by TEXT NULL,
        horizontal_accuracy_m REAL NULL,
        source_reference TEXT NULL,
        source_file_name TEXT NULL,
        source_file_hash TEXT NULL,
        source_notes TEXT NULL,
        change_reason TEXT NULL,
        notes TEXT NULL,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(feature_id, revision),
        FOREIGN KEY(feature_id) REFERENCES $featuresTable(id)
          ON UPDATE RESTRICT ON DELETE RESTRICT
      )
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_feature_type
      ON $featuresTable(feature_type)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_geometry_type
      ON $featuresTable(geometry_type)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_lifecycle_status
      ON $featuresTable(lifecycle_status)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_project_id
      ON $featuresTable(project_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_business_unit_id
      ON $featuresTable(business_unit_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_features_updated_at
      ON $featuresTable(updated_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_feature_revisions_temporal_state
      ON $revisionsTable(temporal_state)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_feature_revisions_valid_from
      ON $revisionsTable(valid_from)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_spatial_feature_revisions_source_type
      ON $revisionsTable(source_type)
    ''');
  }
}
