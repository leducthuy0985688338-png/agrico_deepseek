enum ParcelLineageType {
  subdivision,
  merge,
  partialDerivation,
  fullDerivation,
  relocation,
  replacement,
  boundaryAdjustment,
  other,
}

class ParcelLineage {
  const ParcelLineage({
    required this.id,
    required this.preCompensationParcelId,
    required this.productionParcelId,
    required this.lineageType,
    required this.effectiveAt,
    required this.createdAt,
    required this.createdBy,
    this.sourceAreaM2,
    this.derivedAreaM2,
    this.derivedShare,
    this.compensationReference,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  /// Stable identity of this lineage record.
  final String id;

  /// Historical source parcel before compensation/GPMB.
  final String preCompensationParcelId;

  /// Current production LandParcel derived from the historical source.
  final String productionParcelId;

  final ParcelLineageType lineageType;

  /// Area of the historical source parcel relevant to this lineage record.
  final double? sourceAreaM2;

  /// Area transferred/derived into the production parcel.
  final double? derivedAreaM2;

  /// Optional share in the range (0, 1]. It is deliberately stored
  /// independently from area because verified compensation records may
  /// provide one value without the other.
  final double? derivedShare;

  final DateTime effectiveAt;

  /// Optional compensation/GPMB dossier or decision reference.
  final String? compensationReference;
  final String? notes;

  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;

  void validate() {
    _requireText(id, 'id');
    _requireText(preCompensationParcelId, 'preCompensationParcelId');
    _requireText(productionParcelId, 'productionParcelId');
    _requireText(createdBy, 'createdBy');

    if (preCompensationParcelId == productionParcelId) {
      throw const FormatException(
        'Parcel lineage source and production parcel cannot be the same id.',
      );
    }

    _validatePositiveArea(sourceAreaM2, 'sourceAreaM2');
    _validatePositiveArea(derivedAreaM2, 'derivedAreaM2');

    if (sourceAreaM2 != null &&
        derivedAreaM2 != null &&
        derivedAreaM2! > sourceAreaM2!) {
      throw const FormatException(
        'Parcel lineage derivedAreaM2 cannot exceed sourceAreaM2.',
      );
    }

    if (derivedShare != null &&
        (!derivedShare!.isFinite || derivedShare! <= 0 || derivedShare! > 1)) {
      throw const FormatException(
        'Parcel lineage derivedShare must be greater than zero and at most one.',
      );
    }

    if (createdAt.isBefore(effectiveAt)) {
      throw const FormatException(
        'Parcel lineage creation cannot precede its effective date.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Parcel lineage schemaVersion must be greater than zero.',
      );
    }

    _validateOptionalText(compensationReference, 'compensationReference');
    _validateOptionalText(notes, 'notes');
  }

  static void _validatePositiveArea(double? value, String fieldName) {
    if (value != null && (!value.isFinite || value <= 0)) {
      throw FormatException(
        'Parcel lineage $fieldName must be finite and greater than zero.',
      );
    }
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Parcel lineage $fieldName cannot be blank.');
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Parcel lineage $fieldName cannot be blank when provided.',
      );
    }
  }
}
