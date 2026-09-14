import '../../../features/farm/domain/repositories/land_parcel_spatial_link_repository.dart';
import '../data/spatial_feature_repository.dart';
import '../data/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature.dart';
import '../domain/entities/spatial_feature_revision.dart';

/// Stable association between a business LandParcel and its Spatial Core
/// identity.
///
/// This is an application read model, not a replacement for a domain
/// SpatialIdentity entity. The stable Spatial Core identity remains
/// [spatialFeatureId].
class LandParcelSpatialIdentity {
  const LandParcelSpatialIdentity({
    required this.landParcelId,
    required this.spatialFeatureId,
  });

  final String landParcelId;
  final String spatialFeatureId;
}

/// Read-only application boundary for Spatial Core.
///
/// Responsibilities:
/// - read a SpatialFeature by stable id;
/// - read the current/latest revision of a SpatialFeature;
/// - resolve the stable SpatialFeature identity associated with a LandParcel;
/// - list SpatialFeatures;
/// - resolve a SpatialFeature by its stable identity.
///
/// This boundary deliberately contains no persistence logic, no UI logic,
/// and no mutation operations.
class SpatialReadQueries {
  const SpatialReadQueries({
    required this.featureRepository,
    required this.revisionRepository,
    required this.landParcelSpatialLinkRepository,
  });

  final SpatialFeatureRepository featureRepository;
  final SpatialFeatureRevisionRepository revisionRepository;
  final LandParcelSpatialLinkRepository landParcelSpatialLinkRepository;

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

  /// Resolves the stable Spatial Core identity associated with a LandParcel.
  ///
  /// Returns null when the LandParcel has not yet been linked to Spatial Core.
  Future<LandParcelSpatialIdentity?> getLandParcelSpatialIdentity(
    String landParcelId,
  ) async {
    _requireId(landParcelId, 'landParcelId');

    final link = await landParcelSpatialLinkRepository.findByLandParcelId(
      landParcelId,
    );

    if (link == null) {
      return null;
    }

    return LandParcelSpatialIdentity(
      landParcelId: link.landParcelId,
      spatialFeatureId: link.spatialFeatureId,
    );
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
