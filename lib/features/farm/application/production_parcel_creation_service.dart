import '../../../core/permissions/authorization.dart';
import '../../../core/project/agrico_project.dart';
import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/land_survey.dart';
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
      if (draft.boundarySource == BoundarySource.gps)
        PermissionCodes.fieldMeasure,
      if (draft.boundarySource == BoundarySource.googleEarth ||
          draft.boundarySource == BoundarySource.imported)
        PermissionCodes.fieldGoogleEarthImport,
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

  /// Verifies that the supplied (id, code) pair matches the configured
  /// project. When a project catalog is introduced, this is where the pair
  /// will be validated against the catalog instead of the shipped constant.
  void _requireProjectMatches({
    required AgricoProject project,
    required String projectCode,
  }) {
    if (project.code != projectCode) {
      throw const FormatException(
        'Project code does not match the configured project.',
      );
    }
  }

  /// Creates a production land block.
  ///
  /// P02A contract:
  /// - The draft must carry the configured project id.
  /// - A production land block must never carry crops. Crops belong to
  ///   field plots only; any caller bypassing the UI is rejected here.
  Future<LandParcel> createLandBlock({
    required AuthorizationSubject subject,
    required LandParcel draft,
    required String projectCode,
    required AgricoProject project,
    List<CropRecord> crops = const [],
  }) {
    _authorize(subject, draft);
    _requireProjectMatches(project: project, projectCode: projectCode);
    if (draft.projectId == null || draft.projectId!.trim().isEmpty) {
      throw const FormatException(
        'A production land block requires a project id on the draft.',
      );
    }
    if (draft.projectId != project.id) {
      throw const FormatException(
        'Production block draft must carry the configured project id.',
      );
    }
    if (crops.isNotEmpty) {
      throw const FormatException(
        'A production land block cannot carry crops.',
      );
    }
    return repository.createLandBlock(
      draft: draft,
      projectCode: projectCode,
      crops: const [],
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
