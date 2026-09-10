enum SpatialTemporalState {
  /// Surveyed or recorded before the company project/intervention.
  baseline,

  /// Existing state during planning, compensation, or site preparation.
  preConstruction,

  /// State recorded while construction or transformation is in progress.
  underConstruction,

  /// Verified state after construction or company intervention.
  asBuilt,

  /// Later operational or periodic survey state.
  operational,

  /// Historical state no longer current but retained for audit.
  superseded,
}

class SpatialEffectivePeriod {
  const SpatialEffectivePeriod({required this.validFrom, this.validTo});

  final DateTime validFrom;
  final DateTime? validTo;

  bool get isOpenEnded => validTo == null;

  void validate() {
    if (validTo != null && validTo!.isBefore(validFrom)) {
      throw const FormatException(
        'Spatial effective period cannot end before it starts.',
      );
    }
  }

  bool contains(DateTime instant) =>
      !instant.isBefore(validFrom) &&
      (validTo == null || instant.isBefore(validTo!));
}

class SpatialRevisionIdentity {
  const SpatialRevisionIdentity({
    required this.featureId,
    required this.revision,
  });

  final String featureId;
  final int revision;

  void validate() {
    if (featureId.trim().isEmpty) {
      throw const FormatException(
        'Spatial revision featureId cannot be blank.',
      );
    }

    if (revision <= 0) {
      throw const FormatException(
        'Spatial revision number must be greater than zero.',
      );
    }
  }
}
