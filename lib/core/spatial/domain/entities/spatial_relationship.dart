class SpatialRelationship {
  const SpatialRelationship({
    required this.id,
    required this.sourceFeatureId,
    required this.targetFeatureId,
    required this.relationshipType,
    required this.createdAt,
    required this.createdBy,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String sourceFeatureId;
  final String targetFeatureId;
  final String relationshipType;
  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Spatial relationship id cannot be blank.');
    }

    if (sourceFeatureId.trim().isEmpty) {
      throw const FormatException('Source SpatialFeature id cannot be blank.');
    }

    if (targetFeatureId.trim().isEmpty) {
      throw const FormatException('Target SpatialFeature id cannot be blank.');
    }

    if (relationshipType.trim().isEmpty) {
      throw const FormatException('Spatial relationship type cannot be blank.');
    }

    if (createdBy.trim().isEmpty) {
      throw const FormatException('Created by cannot be blank.');
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Spatial relationship schema version must be greater than zero.',
      );
    }

    if (sourceFeatureId == targetFeatureId) {
      throw const FormatException('A SpatialFeature cannot relate to itself.');
    }
  }
}
