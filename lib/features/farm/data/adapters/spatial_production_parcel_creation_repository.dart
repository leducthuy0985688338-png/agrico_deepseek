import '../../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../../application/land_parcel_spatial_sync_workflow.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/repositories/production_parcel_creation_repository.dart';

/// Reuses the existing atomic spatial workflow; there is no second write path.
class SpatialProductionParcelCreationRepository
    implements ProductionParcelCreationRepository {
  const SpatialProductionParcelCreationRepository(this.workflow);
  final LandParcelSpatialSyncWorkflow workflow;

  @override
  Future<LandParcel> createLandBlock({
    required LandParcel draft,
    required String projectCode,
    required SpatialTemporalState temporalState,
  }) => workflow.createProductionLandBlock(
    draft: draft,
    projectCode: projectCode,
    temporalState: temporalState,
  );

  @override
  Future<LandParcel> createFieldPlot({
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
  }) => workflow.createProductionFieldPlot(
    draft: draft,
    parentLandBlockId: parentLandBlockId,
    expectedParentBoundaryVersion: expectedParentBoundaryVersion,
    temporalState: temporalState,
  );
}
