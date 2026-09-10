enum SpatialSourceType {
  gps,
  googleEarth,
  survey,
  autocad,
  satellite,
  drone,
  imported,
  manual,
  other,
}

class SpatialSource {
  const SpatialSource({
    required this.type,
    this.surveyedAt,
    this.surveyedBy,
    this.horizontalAccuracyM,
    this.sourceReference,
    this.sourceFileName,
    this.sourceFileHash,
    this.notes,
  });

  final SpatialSourceType type;

  /// Date/time at which the spatial information was observed or surveyed.
  final DateTime? surveyedAt;

  /// Membership/user identifier of the person responsible for the survey.
  final String? surveyedBy;

  /// Estimated horizontal accuracy in metres when known.
  final double? horizontalAccuracyM;

  /// External source reference, such as a survey job, CAD drawing,
  /// satellite scene, Google Earth reference, or other source identifier.
  final String? sourceReference;

  final String? sourceFileName;
  final String? sourceFileHash;
  final String? notes;

  void validate() {
    if (horizontalAccuracyM != null &&
        (!horizontalAccuracyM!.isFinite || horizontalAccuracyM! < 0)) {
      throw const FormatException(
        'Spatial source horizontal accuracy must be finite and non-negative.',
      );
    }

    if (surveyedBy != null && surveyedBy!.trim().isEmpty) {
      throw const FormatException(
        'Spatial source surveyedBy cannot be blank when provided.',
      );
    }

    if (sourceReference != null && sourceReference!.trim().isEmpty) {
      throw const FormatException(
        'Spatial source reference cannot be blank when provided.',
      );
    }

    if (sourceFileName != null && sourceFileName!.trim().isEmpty) {
      throw const FormatException(
        'Spatial source file name cannot be blank when provided.',
      );
    }

    if (sourceFileHash != null && sourceFileHash!.trim().isEmpty) {
      throw const FormatException(
        'Spatial source file hash cannot be blank when provided.',
      );
    }
  }
}
