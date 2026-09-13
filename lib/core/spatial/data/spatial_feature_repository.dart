import '../domain/entities/spatial_feature.dart';

abstract interface class SpatialFeatureRepository {
  Future<SpatialFeature?> findById(String id);

  Future<List<SpatialFeature>> findAll();

  Future<void> create(SpatialFeature feature);

  Future<void> update(SpatialFeature feature);

  Future<void> deleteById(String id);
}
