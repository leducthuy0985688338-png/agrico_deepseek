import '../domain/repositories/land_parcel_spatial_link_repository.dart';

/// Stable association between a business LandParcel and its Spatial Core
/// identity.
///
/// This is a Farm application read model, not a replacement for a Spatial
/// Core domain entity. The stable Spatial Core identity remains
/// [spatialFeatureId].
class LandParcelSpatialIdentity {
  const LandParcelSpatialIdentity({
    required this.landParcelId,
    required this.spatialFeatureId,
  });

  final String landParcelId;
  final String spatialFeatureId;
}

/// Farm application boundary that resolves the Spatial Core identity
/// associated with a LandParcel.
///
/// This boundary belongs to the Farm feature because the concept it exposes
/// is LandParcel-specific. It uses the Farm domain repository
/// [LandParcelSpatialLinkRepository] to resolve the stable association.
class LandParcelSpatialIdentityQueries {
  const LandParcelSpatialIdentityQueries({required this.linkRepository});

  final LandParcelSpatialLinkRepository linkRepository;

  /// Resolves the stable Spatial Core identity associated with a LandParcel.
  ///
  /// Returns null when the LandParcel has not yet been linked to Spatial Core.
  Future<LandParcelSpatialIdentity?> getLandParcelSpatialIdentity(
    String landParcelId,
  ) async {
    _requireId(landParcelId, 'landParcelId');

    final link = await linkRepository.findByLandParcelId(landParcelId);

    if (link == null) {
      return null;
    }

    return LandParcelSpatialIdentity(
      landParcelId: link.landParcelId,
      spatialFeatureId: link.spatialFeatureId,
    );
  }

  static void _requireId(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
