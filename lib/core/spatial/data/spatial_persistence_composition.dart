import 'package:sqflite/sqflite.dart';

import '../application/create_spatial_feature_with_initial_revision.dart';
import '../application/update_spatial_feature_with_revision.dart';
import 'spatial_feature_repository.dart';
import 'spatial_feature_revision_repository.dart';
import 'sqlite_spatial_feature_creation_transaction.dart';
import 'sqlite_spatial_feature_repository.dart';
import 'sqlite_spatial_feature_revision_repository.dart';
import 'sqlite_spatial_feature_revision_update_transaction.dart';

/// Runtime composition for SQLite-backed Spatial Core persistence.
///
/// This object owns no database lifecycle. The supplied [DatabaseExecutor]
/// remains owned by the application composition root or caller.
class SpatialPersistenceComposition {
  SpatialPersistenceComposition(DatabaseExecutor executor)
    : featureRepository = SqliteSpatialFeatureRepository(executor),
      revisionRepository = SqliteSpatialFeatureRevisionRepository(executor),
      createFeature = CreateSpatialFeatureWithInitialRevision(
        SqliteSpatialFeatureCreationTransaction(executor),
      ),
      updateFeature = UpdateSpatialFeatureWithRevision(
        SqliteSpatialFeatureRevisionUpdateTransaction(executor),
      );

  final SpatialFeatureRepository featureRepository;
  final SpatialFeatureRevisionRepository revisionRepository;

  final CreateSpatialFeatureWithInitialRevision createFeature;
  final UpdateSpatialFeatureWithRevision updateFeature;
}
