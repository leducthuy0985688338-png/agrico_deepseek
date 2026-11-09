import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

class InMemorySpatialStore {
  InMemorySpatialStore()
    : _state = _InMemorySpatialState(
        features: <String, SpatialFeature>{},
        revisions: <String, SpatialFeatureRevision>{},
      );

  InMemorySpatialStore._(this._state);

  _InMemorySpatialState _state;

  InMemorySpatialStore copy() {
    return InMemorySpatialStore._(_state.copy());
  }

  void replaceWith(InMemorySpatialStore other) {
    _state = other._state.copy();
  }

  SpatialFeature? findFeatureById(String id) {
    return _state.features[id];
  }

  Iterable<SpatialFeature> get features => _state.features.values;

  bool containsFeature(String id) {
    return _state.features.containsKey(id);
  }

  void putFeature(SpatialFeature feature) {
    _state.features[feature.id] = feature;
  }

  bool removeFeature(String id) {
    return _state.features.remove(id) != null;
  }

  SpatialFeatureRevision? findRevisionById(String id) {
    return _state.revisions[id];
  }

  Iterable<SpatialFeatureRevision> get revisions => _state.revisions.values;

  bool containsRevision(String id) {
    return _state.revisions.containsKey(id);
  }

  void putRevision(SpatialFeatureRevision revision) {
    _state.revisions[revision.id] = revision;
  }
}

class _InMemorySpatialState {
  _InMemorySpatialState({required this.features, required this.revisions});

  final Map<String, SpatialFeature> features;
  final Map<String, SpatialFeatureRevision> revisions;

  _InMemorySpatialState copy() {
    return _InMemorySpatialState(
      features: Map<String, SpatialFeature>.of(features),
      revisions: Map<String, SpatialFeatureRevision>.of(revisions),
    );
  }
}
