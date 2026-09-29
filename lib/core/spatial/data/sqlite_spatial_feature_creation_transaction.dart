import 'package:sqflite/sqflite.dart';

import '../application/spatial_feature_creation_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import '../domain/geometry/spatial_geometry_pair.dart';
import 'sqlite_spatial_feature_repository.dart';
import 'sqlite_spatial_feature_revision_repository.dart';

/// SQLite-backed atomic creation of a spatial feature and its initial revision.
///
/// When backed by a [Database], both writes are executed inside one SQLite
/// transaction. When already backed by a [Transaction], the caller-owned
/// transaction is reused to avoid nesting transactions.
class SqliteSpatialFeatureCreationTransaction
    implements SpatialFeatureCreationTransaction {
  SqliteSpatialFeatureCreationTransaction(DatabaseExecutor executor)
    : _executor = executor;

  final DatabaseExecutor _executor;

  @override
  Future<void> create({
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  }) async {
    feature.validate();
    validateSpatialGeometryPair(feature, initialRevision);

    if (initialRevision.revision != 1) {
      throw StateError(
        'Initial spatial feature revision must be 1, '
        'but received ${initialRevision.revision}.',
      );
    }

    if (_executor is Transaction) {
      await _createWithin(
        _executor,
        feature: feature,
        initialRevision: initialRevision,
      );
      return;
    }

    final database = _executor as Database;
    await database.transaction(
      (transaction) => _createWithin(
        transaction,
        feature: feature,
        initialRevision: initialRevision,
      ),
    );
  }

  Future<void> _createWithin(
    DatabaseExecutor executor, {
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  }) async {
    final featureRepository = SqliteSpatialFeatureRepository(executor);
    final revisionRepository = SqliteSpatialFeatureRevisionRepository(executor);

    await featureRepository.create(feature);

    final existingRevisions = await revisionRepository.findByFeatureId(
      feature.id,
    );

    if (existingRevisions.isNotEmpty) {
      throw StateError(
        'Spatial feature already has revision history: ${feature.id}',
      );
    }

    await revisionRepository.create(initialRevision);
  }
}
