import '../../../core/permissions/authorization.dart';
import '../domain/entities/parcel_land_history.dart';
import '../domain/repositories/land_parcel_repository.dart';
import '../domain/repositories/parcel_land_history_repository.dart';

class ParcelLandHistoryService {
  const ParcelLandHistoryService(this.repository, this.parcels);

  final ParcelLandHistoryRepository repository;
  final LandParcelRepository parcels;

  void _authorize(AuthorizationSubject subject, String permission,
      String parcelId) {
    if (!const AuthorizationService().can(
          subject: subject, permission: permission,
          resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
        ) || !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Parcel history requires farm-wide access.');
    }
  }

  Future<ParcelStageSnapshot> capture({
    required AuthorizationSubject subject,
    required String parcelId,
    required ParcelLandStage stage,
    required int boundaryVersion,
  }) async {
    _authorize(subject, PermissionCodes.fieldEdit, parcelId);
    final parcel = await parcels.getById(farmId: subject.farmId, id: parcelId);
    final versions = parcel?.boundaryHistory.where((item) =>
        item.version == boundaryVersion).toList() ?? [];
    if (versions.length != 1) {
      throw StateError('Boundary revision does not exist.');
    }
    final snapshot = ParcelStageSnapshot(
      id: 'stage-${DateTime.now().microsecondsSinceEpoch}',
      farmId: subject.farmId, parcelId: parcelId, stage: stage,
      boundaryVersion: boundaryVersion, areaM2: versions.single.areaM2,
      recordedAt: DateTime.now().toUtc(),
      actorMembershipId: subject.membershipId,
    );
    await repository.capture(snapshot);
    return snapshot;
  }

  Future<void> link({
    required AuthorizationSubject subject,
    required String sourceParcelId,
    required String targetParcelId,
    required ParcelDerivationKind kind,
    required double derivedAreaM2,
  }) {
    _authorize(subject, PermissionCodes.fieldEdit, targetParcelId);
    return repository.link(ParcelDerivation(
      id: 'derivation-${DateTime.now().microsecondsSinceEpoch}',
      farmId: subject.farmId, sourceParcelId: sourceParcelId,
      targetParcelId: targetParcelId, kind: kind,
      derivedAreaM2: derivedAreaM2,
      occurredAt: DateTime.now().toUtc(),
      actorMembershipId: subject.membershipId,
    ));
  }

  Future<List<ParcelStageSnapshot>> snapshots(
      AuthorizationSubject subject, String parcelId) {
    _authorize(subject, PermissionCodes.fieldView, parcelId);
    return repository.snapshots(subject.farmId, parcelId);
  }

  Future<List<ParcelDerivation>> derivations(
      AuthorizationSubject subject, String parcelId) {
    _authorize(subject, PermissionCodes.fieldView, parcelId);
    return repository.derivations(subject.farmId, parcelId);
  }
}
