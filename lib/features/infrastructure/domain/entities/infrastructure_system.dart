enum InfrastructureSystemType {
  irrigation,
  roadNetwork,
  waterSupply,
  drainage,
  pipelineNetwork,
  other,
}

/// Business-level grouping of infrastructure assets.
///
/// A system does not own geometry. Each member InfrastructureAsset keeps its
/// own stable SpatialFeature identity, while Spatial Core owns geometry and
/// revision history.
class InfrastructureSystem {
  InfrastructureSystem({
    required this.id,
    required this.systemType,
    required List<String> assetIds,
    required this.createdAt,
    required this.createdBy,
    this.projectId,
    this.businessUnitId,
    this.code,
    this.name,
    this.notes,
    this.active = true,
    this.schemaVersion = currentSchemaVersion,
  }) : assetIds = List.unmodifiable(assetIds);

  static const int currentSchemaVersion = 1;

  final String id;
  final InfrastructureSystemType systemType;

  /// Stable InfrastructureAsset identities belonging to this system.
  ///
  /// Membership is business metadata only. Geometry remains on each asset's
  /// SpatialFeature in Spatial Core.
  final List<String> assetIds;

  final String? projectId;
  final String? businessUnitId;
  final String? code;
  final String? name;
  final String? notes;
  final bool active;

  final DateTime createdAt;
  final String createdBy;

  final int schemaVersion;

  void validate() {
    _validateRequiredText(id, 'id');
    _validateRequiredText(createdBy, 'createdBy');

    _validateOptionalText(projectId, 'projectId');
    _validateOptionalText(businessUnitId, 'businessUnitId');
    _validateOptionalText(code, 'code');
    _validateOptionalText(name, 'name');
    _validateOptionalText(notes, 'notes');

    for (final assetId in assetIds) {
      _validateRequiredText(assetId, 'assetId');
    }

    if (assetIds.toSet().length != assetIds.length) {
      throw const FormatException(
        'Infrastructure system must not contain duplicate asset IDs.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Infrastructure system schemaVersion must be positive.',
      );
    }
  }

  static void _validateRequiredText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException(
        'Infrastructure system $fieldName must not be blank.',
      );
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Infrastructure system $fieldName must not be blank when provided.',
      );
    }
  }
}
