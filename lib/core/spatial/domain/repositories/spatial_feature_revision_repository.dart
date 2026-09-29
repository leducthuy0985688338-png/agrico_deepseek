import '../entities/spatial_feature_revision.dart';

abstract interface class SpatialFeatureRevisionRepository {
  Future<SpatialFeatureRevision?> findById(String id);

  Future<List<SpatialFeatureRevision>> findByFeatureId(String featureId);

  Future<SpatialFeatureRevision?> findLatestByFeatureId(String featureId);

  Future<void> create(SpatialFeatureRevision revision);
}
