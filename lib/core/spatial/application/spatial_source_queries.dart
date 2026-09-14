import '../data/spatial_feature_revision_repository.dart';
import '../domain/entities/spatial_feature_revision.dart';
import '../domain/entities/spatial_source.dart';

/// Read-only application boundary for Spatial Source / provenance queries.
///
/// SpatialSource is provenance metadata owned by a
/// SpatialFeatureRevision. It is intentionally not treated as an independent
/// entity with its own repository or identity.
///
/// The stable SpatialFeature identity remains [SpatialFeatureRevision.featureId]
/// and revision history remains owned by [SpatialFeatureRevisionRepository].
class SpatialSourceQueries {
  const SpatialSourceQueries({required this.revisionRepository});

  final SpatialFeatureRevisionRepository revisionRepository;

  /// Returns the source metadata of the latest revision.
  Future<SpatialSource?> getCurrentSource(String spatialFeatureId) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    final revision = await revisionRepository.findLatestByFeatureId(
      spatialFeatureId,
    );

    return revision?.source;
  }

  /// Returns the source metadata of a specific revision.
  Future<SpatialSource?> getRevisionSource(
    String spatialFeatureId,
    int revisionNumber,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    if (revisionNumber <= 0) {
      throw const FormatException('revisionNumber must be greater than zero.');
    }

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    for (final revision in revisions) {
      if (revision.revision == revisionNumber) {
        return revision.source;
      }
    }

    return null;
  }

  /// Returns revisions whose source type matches [sourceType].
  Future<List<SpatialFeatureRevision>> findRevisionsBySourceType(
    String spatialFeatureId,
    SpatialSourceType sourceType,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    final matches =
        revisions
            .where((revision) => revision.source.type == sourceType)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));

    return List.unmodifiable(matches);
  }

  /// Returns revisions surveyed by [surveyedBy].
  ///
  /// Revisions without surveyor information are ignored.
  Future<List<SpatialFeatureRevision>> findRevisionsBySurveyor(
    String spatialFeatureId,
    String surveyedBy,
  ) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');
    _requireText(surveyedBy, 'surveyedBy');

    final expectedSurveyor = surveyedBy.trim();

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    final matches =
        revisions
            .where(
              (revision) =>
                  revision.source.surveyedBy?.trim() == expectedSurveyor,
            )
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));

    return List.unmodifiable(matches);
  }

  /// Returns revisions surveyed within the inclusive date range.
  ///
  /// Revisions without a survey date are ignored.
  Future<List<SpatialFeatureRevision>> findRevisionsBetweenSurveyDates({
    required String spatialFeatureId,
    required DateTime from,
    required DateTime to,
  }) async {
    _requireId(spatialFeatureId, 'spatialFeatureId');

    if (from.isAfter(to)) {
      throw const FormatException(
        'The start date cannot be after the end date.',
      );
    }

    final revisions = await revisionRepository.findByFeatureId(
      spatialFeatureId,
    );

    final matches =
        revisions.where((revision) {
          final surveyedAt = revision.source.surveyedAt;

          if (surveyedAt == null) {
            return false;
          }

          return !surveyedAt.isBefore(from) && !surveyedAt.isAfter(to);
        }).toList()..sort((a, b) {
          final aDate = a.source.surveyedAt!;
          final bDate = b.source.surveyedAt!;
          return aDate.compareTo(bDate);
        });

    return List.unmodifiable(matches);
  }

  /// Returns the complete revision history in revision-number order.
  ///
  /// Each returned revision retains its own SpatialSource provenance.
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

  static void _requireId(String value, String fieldName) {
    _requireText(value, fieldName);
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
