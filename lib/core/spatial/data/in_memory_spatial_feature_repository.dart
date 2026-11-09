import '../domain/entities/spatial_feature.dart';
import 'in_memory_spatial_store.dart';
import '../domain/repositories/spatial_feature_repository.dart';

class InMemorySpatialFeatureRepository implements SpatialFeatureRepository {
  InMemorySpatialFeatureRepository({InMemorySpatialStore? store})
    : _store = store ?? InMemorySpatialStore();

  final InMemorySpatialStore _store;

  @override
  Future<SpatialFeature?> findById(String id) async {
    return _store.findFeatureById(id);
  }

  @override
  Future<List<SpatialFeature>> findAll() async {
    return List<SpatialFeature>.unmodifiable(_store.features);
  }

  @override
  Future<void> create(SpatialFeature feature) async {
    feature.validate();

    if (_store.containsFeature(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" already exists.',
      );
    }

    _store.putFeature(feature);
  }

  @override
  Future<void> update(SpatialFeature feature) async {
    feature.validate();

    if (!_store.containsFeature(feature.id)) {
      throw StateError(
        'Spatial feature with id "${feature.id}" does not exist.',
      );
    }

    _store.putFeature(feature);
  }

  @override
  Future<void> deleteById(String id) async {
    if (!_store.containsFeature(id)) {
      throw StateError('Spatial feature with id "$id" does not exist.');
    }

    _store.removeFeature(id);
  }
}
