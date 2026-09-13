import 'package:sqflite/sqflite.dart';

import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_revision_repository.dart';
import 'spatial_feature_revision_sqlite_mapper.dart';
import 'sqlite_spatial_schema.dart';

/// Append-only SQLite persistence for [SpatialFeatureRevision] history.
class SqliteSpatialFeatureRevisionRepository
    implements SpatialFeatureRevisionRepository {
  SqliteSpatialFeatureRevisionRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<SpatialFeatureRevision?> findById(String id) async {
    final rows = await _executor.query(
      SqliteSpatialSchema.revisionsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : SpatialFeatureRevisionSqliteMapper.fromRow(rows.single);
  }

  @override
  Future<List<SpatialFeatureRevision>> findByFeatureId(String featureId) async {
    final rows = await _executor.query(
      SqliteSpatialSchema.revisionsTable,
      where: 'feature_id = ?',
      whereArgs: [featureId],
      orderBy: 'revision ASC',
    );
    return List<SpatialFeatureRevision>.unmodifiable(
      rows.map(SpatialFeatureRevisionSqliteMapper.fromRow),
    );
  }

  @override
  Future<SpatialFeatureRevision?> findLatestByFeatureId(
    String featureId,
  ) async {
    final rows = await _executor.query(
      SqliteSpatialSchema.revisionsTable,
      where: 'feature_id = ?',
      whereArgs: [featureId],
      orderBy: 'revision DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : SpatialFeatureRevisionSqliteMapper.fromRow(rows.single);
  }

  @override
  Future<void> create(SpatialFeatureRevision revision) async {
    await _executor.insert(
      SqliteSpatialSchema.revisionsTable,
      SpatialFeatureRevisionSqliteMapper.toRow(revision),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
