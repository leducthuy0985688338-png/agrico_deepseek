import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/geometry/parcel_subdivision_plan.dart';
import '../domain/geometry/wgs84_geometry.dart';
import '../domain/repositories/land_parcel_repository.dart';
import 'land_parcel_spatial_sync_workflow.dart';

class ParcelSubdivisionPreview {
  const ParcelSubdivisionPreview({
    required this.source, required this.boundaries,
    required this.areasM2,
  });

  final LandParcel source;
  final List<Wgs84Polygon> boundaries;
  final List<double> areasM2;
}

class ParcelSubdivisionService {
  const ParcelSubdivisionService({required this.parcels, required this.workflow});

  final LandParcelRepository parcels;
  final LandParcelSpatialSyncWorkflow workflow;

  void _authorize(AuthorizationSubject subject, String parcelId,
      String permission) {
    if (!const AuthorizationService().can(
      subject: subject, permission: permission,
      resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
    ) || !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Parcel subdivision requires farm-wide access.');
    }
  }

  Future<ParcelSubdivisionPreview> preview({
    required AuthorizationSubject subject,
    required String sourceParcelId,
    required Wgs84Vertex cutStart,
    required Wgs84Vertex cutEnd,
    List<Wgs84Vertex> cutWaypoints = const [],
  }) => previewPlan(subject: subject, sourceParcelId: sourceParcelId,
    cuts: [ParcelSubdivisionCut(fragmentIndex: 0,
      path: [cutStart, ...cutWaypoints, cutEnd])]);

  Future<ParcelSubdivisionPreview> previewPlan({
    required AuthorizationSubject subject,
    required String sourceParcelId,
    required List<ParcelSubdivisionCut> cuts,
  }) async {
    _authorize(subject, sourceParcelId, PermissionCodes.fieldView);
    final source = await parcels.getById(
        farmId: subject.farmId, id: sourceParcelId);
    if (source == null || !source.active) {
      throw StateError('Source parcel is missing or inactive.');
    }
    final boundaries = const ParcelSubdivisionPlan().apply(source.boundary, cuts);
    final geometry = const Wgs84GeometryService();
    return ParcelSubdivisionPreview(
      source: source,
      boundaries: boundaries,
      areasM2: boundaries.map((part) => geometry.measure(part).areaM2).toList(),
    );
  }

  Future<List<LandParcel>> save({
    required AuthorizationSubject subject,
    required String sourceParcelId,
    required String villageId,
    required int expectedBoundaryVersion,
    required Wgs84Vertex cutStart,
    required Wgs84Vertex cutEnd,
    List<Wgs84Vertex> cutWaypoints = const [],
    required String firstName,
    required String secondName,
  }) => savePlan(subject: subject, sourceParcelId: sourceParcelId,
    villageId: villageId, expectedBoundaryVersion: expectedBoundaryVersion,
    cuts: [ParcelSubdivisionCut(fragmentIndex: 0,
      path: [cutStart, ...cutWaypoints, cutEnd])],
    names: [firstName, secondName]);

  Future<List<LandParcel>> savePlan({
    required AuthorizationSubject subject,
    required String sourceParcelId,
    required String villageId,
    required int expectedBoundaryVersion,
    required List<ParcelSubdivisionCut> cuts,
    required List<String> names,
  }) async {
    _authorize(subject, sourceParcelId, PermissionCodes.fieldEdit);
    _authorize(subject, sourceParcelId, PermissionCodes.fieldCreate);
    return workflow.subdividePlan(
      farmId: subject.farmId, sourceParcelId: sourceParcelId,
      villageId: villageId, expectedBoundaryVersion: expectedBoundaryVersion,
      cuts: cuts, names: names,
      actorMembershipId: subject.membershipId,
      occurredAt: DateTime.now().toUtc(),
    );
  }
}
