import '../domain/entities/spatial_feature_revision.dart';

abstract interface class SpatialFeatureRevisionRepository {
  SpatialFeatureRevision? findById(String id);

  List<SpatialFeatureRevision> findByFeatureId(String featureId);

  SpatialFeatureRevision? findLatestByFeatureId(String featureId);

  void create(SpatialFeatureRevision revision);
}
