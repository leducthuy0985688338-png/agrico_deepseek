import '../domain/repositories/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature_revision.dart';

/// Read-only application boundary for Spatial Feature revision history.
///
/// Responsibilities:
/// - read the complete revision history of a SpatialFeature;
/// - read a specific revision number;
/// - read the current/latest revision;
/// - keep revision ordering explicit for history consumers.
///
/// This boundary deliberately contains no persistence logic, UI logic,
/// or mutation operations.
class SpatialRevisionHistoryQueries {
  const SpatialRevisionHistoryQueries({required this.revisionRepository});

  final SpatialFeatureRevisionRepository revisionRepository;

  /// Returns the complete revision history of a SpatialFeature.
  ///
  /// The result is ordered from the oldest revision to the newest revision.
  Future<List<SpatialFeatureRevision>> getRevisionHistory(
    String spatialFeatureId,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    final ordered = List<SpatialFeatureRevision>.of(revisions)
      ..sort((a, b) => a.revision.compareTo(b.revision));

    return List.unmodifiable(ordered);
  }

  /// Returns a specific revision number for a SpatialFeature.
  ///
  /// For example, revision 1 represents R1, revision 2 represents R2, etc.
  Future<SpatialFeatureRevision?> getRevision(
    String spatialFeatureId,
    int revisionNumber,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    if (revisionNumber <= 0) {
      throw FormatException('revisionNumber must be greater than zero.');
    }

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    for (final revision in revisions) {
      if (revision.revision == revisionNumber) {
        return revision;
      }
    }

    return null;
  }

  /// Returns the latest persisted revision of a SpatialFeature.
  ///
  /// The latest revision is treated as the current revision for read/query
  /// purposes, consistent with the Spatial Core read model.
  Future<SpatialFeatureRevision?> getCurrentRevision(String spatialFeatureId) {
    _requireId(spatialFeatureId, 'spatialFeatureId');
    return revisionRepository.findLatestByFeatureId(spatialFeatureId);
  }

  /// Returns the revision immediately preceding [revisionNumber].
  ///
  /// Returns null when the requested revision is R1 or when the previous
  /// revision does not exist.
  Future<SpatialFeatureRevision?> getPreviousRevision(
    String spatialFeatureId,
    int revisionNumber,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    if (revisionNumber <= 0) {
      throw FormatException('revisionNumber must be greater than zero.');
    }

    if (revisionNumber == 1) {
      return null;
    }

    return getRevision(spatialFeatureId, revisionNumber - 1);
  }

  static void _requireId(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
