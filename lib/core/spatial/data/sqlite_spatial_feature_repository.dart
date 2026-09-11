import 'package:sqflite/sqflite.dart';

import '../domain/entities/spatial_feature.dart';
import 'spatial_feature_repository.dart';
import 'spatial_feature_sqlite_mapper.dart';
import 'sqlite_spatial_schema.dart';

/// SQLite persistence for canonical [SpatialFeature] snapshots.
class SqliteSpatialFeatureRepository implements SpatialFeatureRepository {
  SqliteSpatialFeatureRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<SpatialFeature?> findById(String id) async {
    final rows = await _executor.query(
      SqliteSpatialSchema.featuresTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : SpatialFeatureSqliteMapper.fromRow(rows.single);
  }

  @override
  Future<List<SpatialFeature>> findAll() async {
    final rows = await _executor.query(
      SqliteSpatialSchema.featuresTable,
      orderBy: 'id ASC',
    );
    return List<SpatialFeature>.unmodifiable(
      rows.map(SpatialFeatureSqliteMapper.fromRow),
    );
  }

  @override
  Future<void> create(SpatialFeature feature) async {
    await _executor.insert(
      SqliteSpatialSchema.featuresTable,
      SpatialFeatureSqliteMapper.toRow(feature),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> update(SpatialFeature feature) async {
    final affected = await _executor.update(
      SqliteSpatialSchema.featuresTable,
      SpatialFeatureSqliteMapper.toRow(feature),
      where: 'id = ?',
      whereArgs: [feature.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (affected != 1) {
      throw StateError(
        'Spatial feature with id "${feature.id}" does not exist.',
      );
    }
  }

  @override
  Future<void> deleteById(String id) async {
    final affected = await _executor.delete(
      SqliteSpatialSchema.featuresTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected != 1) {
      throw StateError('Spatial feature with id "$id" does not exist.');
    }
  }
}
