import '../domain/repositories/spatial_feature_repository.dart';
import '../domain/repositories/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

/// Read-only application boundary for Spatial Core.
///
/// Responsibilities:
/// - read a SpatialFeature by stable id;
/// - read the current/latest revision of a SpatialFeature;
/// - list SpatialFeatures;
/// - resolve a SpatialFeature by its stable identity.
///
/// This boundary deliberately contains no persistence logic, no UI logic,
/// no mutation operations, and no feature-module dependencies.
class SpatialReadQueries {
  const SpatialReadQueries({
    required this.featureRepository,
    required this.revisionRepository,
  });

  final SpatialFeatureRepository featureRepository;
  final SpatialFeatureRevisionRepository revisionRepository;

  /// Returns a SpatialFeature by its stable Spatial Core id.
  Future<SpatialFeature?> getSpatialFeature(String spatialFeatureId) {
    _requireId(spatialFeatureId, 'spatialFeatureId');
    return featureRepository.findById(spatialFeatureId);
  }

  /// Returns the latest persisted revision of a SpatialFeature.
  Future<SpatialFeatureRevision?> getCurrentRevision(String spatialFeatureId) {
    _requireId(spatialFeatureId, 'spatialFeatureId');
    return revisionRepository.findLatestByFeatureId(spatialFeatureId);
  }

  /// Returns all persisted SpatialFeatures.
  Future<List<SpatialFeature>> listSpatialFeatures() {
    return featureRepository.findAll();
  }

  /// Resolves a SpatialFeature using its stable Spatial Core identity.
  ///
  /// This intentionally delegates to the same repository lookup as
  /// [getSpatialFeature] so that identity resolution remains centralized.
  Future<SpatialFeature?> findSpatialFeatureByIdentity(
    String spatialFeatureId,
  ) {
    _requireId(spatialFeatureId, 'spatialFeatureId');
    return featureRepository.findById(spatialFeatureId);
  }

  static void _requireId(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
