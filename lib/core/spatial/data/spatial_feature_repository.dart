import '../domain/entities/spatial_feature.dart';

abstract interface class SpatialFeatureRepository {
  SpatialFeature? findById(String id);

  List<SpatialFeature> findAll();

  void create(SpatialFeature feature);

  void update(SpatialFeature feature);

  void deleteById(String id);
}
