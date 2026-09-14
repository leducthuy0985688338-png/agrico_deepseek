enum SpatialTemporalState { before, change, after }

class SpatialTemporalRecord {
  const SpatialTemporalRecord({
    required this.id,
    required this.spatialFeatureId,
    required this.state,
    required this.occurredAt,
    required this.recordedBy,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String spatialFeatureId;
  final SpatialTemporalState state;
  final DateTime occurredAt;
  final String recordedBy;
  final int schemaVersion;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'Spatial temporal record id cannot be blank.',
      );
    }

    if (spatialFeatureId.trim().isEmpty) {
      throw const FormatException('SpatialFeature id cannot be blank.');
    }

    if (recordedBy.trim().isEmpty) {
      throw const FormatException('Recorded by cannot be blank.');
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Spatial temporal record schema version must be greater than zero.',
      );
    }
  }
}
