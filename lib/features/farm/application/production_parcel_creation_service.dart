import '../../../core/permissions/authorization.dart';
import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/repositories/production_parcel_creation_repository.dart';

class ProductionParcelCreationService {
  const ProductionParcelCreationService(this.repository);
  final ProductionParcelCreationRepository repository;

  void _authorize(
    AuthorizationSubject subject,
    LandParcel draft, {
    String? parentId,
  }) {
    if (draft.farmId != subject.farmId ||
        draft.createdBy != subject.membershipId ||
        draft.updatedBy != subject.membershipId ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError(
        'Production creation requires the current farm membership.',
      );
    }
    final resource = ResourceContext(farmId: subject.farmId, fieldId: parentId);
    final permissions = [
      PermissionCodes.fieldCreate,
      if (parentId != null) PermissionCodes.fieldView,
    ];
    for (final permission in permissions) {
      if (!const AuthorizationService().can(
        subject: subject,
        permission: permission,
        resource: resource,
      )) {
        throw StateError('Production creation permission denied.');
      }
    }
  }

  Future<LandParcel> createLandBlock({
    required AuthorizationSubject subject,
    required LandParcel draft,
    required String projectCode,
  }) {
    _authorize(subject, draft);
    return repository.createLandBlock(
      draft: draft,
      projectCode: projectCode,
      temporalState: SpatialTemporalState.baseline,
    );
  }

  Future<LandParcel> createFieldPlot({
    required AuthorizationSubject subject,
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
  }) {
    _authorize(subject, draft, parentId: parentLandBlockId);
    if (parentLandBlockId.trim().isEmpty || expectedParentBoundaryVersion < 1) {
      throw const FormatException(
        'Parent identity and boundary version are required.',
      );
    }
    return repository.createFieldPlot(
      draft: draft,
      parentLandBlockId: parentLandBlockId,
      expectedParentBoundaryVersion: expectedParentBoundaryVersion,
      temporalState: SpatialTemporalState.underConstruction,
    );
  }
}
