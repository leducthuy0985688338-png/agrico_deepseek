/// A parcel may have several immutable observations, each pointing to a
/// retained boundary revision. The geometry remains in LandParcel history.
enum ParcelLandStage { beforeClearing, afterClearing, cultivation }

class ParcelStageSnapshot {
  const ParcelStageSnapshot({
    required this.id, required this.farmId, required this.parcelId,
    required this.stage, required this.boundaryVersion,
    required this.areaM2, required this.recordedAt,
    required this.actorMembershipId,
  });

  final String id;
  final String farmId;
  final String parcelId;
  final ParcelLandStage stage;
  final int boundaryVersion;
  final double areaM2;
  final DateTime recordedAt;
  final String actorMembershipId;

  void validate() {
    if ([id, farmId, parcelId, actorMembershipId]
        .any((value) => value.trim().isEmpty) || boundaryVersion < 1 ||
        !areaM2.isFinite || areaM2 <= 0) {
      throw const FormatException('Invalid parcel stage observation.');
    }
  }
}

enum ParcelDerivationKind { subdivision, merge, partialDerivation }

/// Many-to-many source/target links preserve the old and new parcel identity.
class ParcelDerivation {
  const ParcelDerivation({
    required this.id, required this.farmId,
    required this.sourceParcelId, required this.targetParcelId,
    required this.kind, required this.derivedAreaM2,
    required this.occurredAt, required this.actorMembershipId,
  });

  final String id;
  final String farmId;
  final String sourceParcelId;
  final String targetParcelId;
  final ParcelDerivationKind kind;
  final double derivedAreaM2;
  final DateTime occurredAt;
  final String actorMembershipId;

  void validate() {
    if ([id, farmId, sourceParcelId, targetParcelId, actorMembershipId]
        .any((value) => value.trim().isEmpty) ||
        sourceParcelId == targetParcelId ||
        !derivedAreaM2.isFinite || derivedAreaM2 <= 0) {
      throw const FormatException('Invalid parcel derivation.');
    }
  }
}
