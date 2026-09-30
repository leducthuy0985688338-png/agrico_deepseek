import '../../../core/permissions/authorization.dart';
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

  Future<LandParcel> createLandBlock({
    required AuthorizationSubject subject,
    required LandParcel draft,
    required String projectCode,
    List<CropRecord> crops = const [],
  }) {
    _authorize(subject, draft);
    final normalized = <CropRecord>[];
    for (var index = 0; index < crops.length; index++) {
      final crop = crops[index];
      if (crop.cropType.trim().isEmpty ||
          crop.unit.trim().isEmpty ||
          !crop.quantity.isFinite ||
          crop.quantity <= 0 ||
          (crop.ageMonths != null && crop.ageMonths! < 0)) {
        throw const FormatException(
          'Invalid crop type, unit, quantity or age.',
        );
      }
      normalized.add(
        CropRecord(
          id: 'crop-${draft.id}-$index',
          parcelId: draft.id,
          cropType: crop.cropType.trim(),
          quantity: crop.quantity,
          unit: crop.unit.trim(),
          variety: crop.variety,
          plantingYear: crop.plantingYear,
          plantingDate: crop.plantingDate,
          ageMonths: crop.ageMonths,
          growthStage: crop.growthStage,
          condition: crop.condition,
          notes: crop.notes,
          active: crop.active,
          createdAt: draft.createdAt,
          createdBy: subject.membershipId,
          updatedAt: draft.updatedAt,
          updatedBy: subject.membershipId,
        ),
      );
    }
    return repository.createLandBlock(
      draft: draft,
      projectCode: projectCode,
      crops: normalized,
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
