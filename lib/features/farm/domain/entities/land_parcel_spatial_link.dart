class LandParcelSpatialLink {
  const LandParcelSpatialLink({
    required this.id,
    required this.landParcelId,
    required this.spatialFeatureId,
    required this.createdAt,
    required this.createdBy,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String landParcelId;
  final String spatialFeatureId;
  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'Land parcel spatial link id cannot be blank.',
      );
    }
    if (landParcelId.trim().isEmpty) {
      throw const FormatException('Land parcel id cannot be blank.');
    }
    if (spatialFeatureId.trim().isEmpty) {
      throw const FormatException('Spatial feature id cannot be blank.');
    }
    if (createdBy.trim().isEmpty) {
      throw const FormatException('Created by cannot be blank.');
    }
    if (schemaVersion <= 0) {
      throw const FormatException(
        'Land parcel spatial link schema version must be greater than zero.',
      );
    }
  }
}
