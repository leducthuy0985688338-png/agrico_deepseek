import 'package:sqflite/sqflite.dart';

import '../application/spatial_feature_revision_update_transaction.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';
import 'sqlite_spatial_feature_repository.dart';
import 'sqlite_spatial_feature_revision_repository.dart';

/// SQLite-backed atomic update of a spatial feature snapshot and revision.
///
/// When backed by a [Database], both writes execute inside one SQLite
/// transaction. When already backed by a [Transaction], the caller-owned
/// transaction is reused to avoid nesting transactions.
class SqliteSpatialFeatureRevisionUpdateTransaction
    implements SpatialFeatureRevisionUpdateTransaction {
  SqliteSpatialFeatureRevisionUpdateTransaction(DatabaseExecutor executor)
    : _executor = executor;

  final DatabaseExecutor _executor;

  @override
  Future<void> update({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) async {
    feature.validate();
    revision.validateAgainstFeature(feature);

    if (revision.revision < 2) {
      throw StateError(
        'Updated spatial feature revision must be at least 2, '
        'but received ${revision.revision}.',
      );
    }

    if (_executor is Transaction) {
      await _updateWithin(_executor, feature: feature, revision: revision);
      return;
    }

    final database = _executor as Database;
    await database.transaction(
      (transaction) =>
          _updateWithin(transaction, feature: feature, revision: revision),
    );
  }

  Future<void> _updateWithin(
    DatabaseExecutor executor, {
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) async {
    final featureRepository = SqliteSpatialFeatureRepository(executor);
    final revisionRepository = SqliteSpatialFeatureRevisionRepository(executor);

    final existingFeature = await featureRepository.findById(feature.id);

    if (existingFeature == null) {
      throw StateError('Spatial feature not found: ${feature.id}');
    }

    if (existingFeature.featureType != feature.featureType) {
      throw StateError(
        'Spatial feature featureType is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.geometryType != feature.geometryType) {
      throw StateError(
        'Spatial feature geometryType is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.createdAt != feature.createdAt) {
      throw StateError(
        'Spatial feature createdAt is immutable for ${feature.id}.',
      );
    }

    if (existingFeature.createdBy != feature.createdBy) {
      throw StateError(
        'Spatial feature createdBy is immutable for ${feature.id}.',
      );
    }

    final latestRevision = await revisionRepository.findLatestByFeatureId(
      feature.id,
    );

    if (latestRevision == null) {
      throw StateError(
        'Spatial feature has no revision history: ${feature.id}',
      );
    }

    final expectedRevision = latestRevision.revision + 1;

    if (revision.revision != expectedRevision) {
      throw StateError(
        'Expected spatial feature revision $expectedRevision '
        'for ${feature.id}, but received ${revision.revision}.',
      );
    }

    await featureRepository.update(feature);
    await revisionRepository.create(revision);
  }
}
