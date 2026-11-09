abstract final class SpatialRelationshipTypes {
  static const contains = 'contains';
  static const partOf = 'partOf';

  static const serves = 'serves';
  static const supplies = 'supplies';
  static const crosses = 'crosses';
  static const providesAccessTo = 'providesAccessTo';

  static const connectedTo = 'connectedTo';
  static const feedsInto = 'feedsInto';

  static const derivedFrom = 'derivedFrom';
  static const replacedBy = 'replacedBy';
  static const upgradedFrom = 'upgradedFrom';
}

class SpatialRelationship {
  const SpatialRelationship({
    required this.id,
    required this.fromFeatureId,
    required this.toFeatureId,
    required this.relationshipType,
    required this.effectiveFrom,
    required this.createdAt,
    required this.createdBy,
    this.effectiveTo,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String fromFeatureId;
  final String toFeatureId;

  /// Controlled relationship identifier. Domain-specific relationships may
  /// use dedicated models when additional business attributes are required.
  final String relationshipType;

  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  final String? notes;

  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  bool get isCurrent => effectiveTo == null;

  void validate() {
    _requireText(id, 'id');
    _requireText(fromFeatureId, 'fromFeatureId');
    _requireText(toFeatureId, 'toFeatureId');
    _requireText(relationshipType, 'relationshipType');
    _requireText(createdBy, 'createdBy');

    if (fromFeatureId == toFeatureId) {
      throw const FormatException(
        'A spatial relationship cannot reference the same feature on both sides.',
      );
    }

    if (effectiveTo != null && effectiveTo!.isBefore(effectiveFrom)) {
      throw const FormatException(
        'Spatial relationship effectiveTo cannot precede effectiveFrom.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Spatial relationship schemaVersion must be greater than zero.',
      );
    }

    if (notes != null && notes!.trim().isEmpty) {
      throw const FormatException(
        'Spatial relationship notes cannot be blank when provided.',
      );
    }
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Spatial relationship $fieldName cannot be blank.');
    }
  }
}
