import '../../domain/geometry/parcel_subdivision_plan.dart';
import '../../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../../application/land_parcel_spatial_sync_workflow.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';
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
    List<CropRecord> crops = const [],
    required SpatialTemporalState temporalState,
  }) => workflow.createProductionLandBlock(
    draft: draft,
    projectCode: projectCode,
    crops: crops,
    temporalState: temporalState,
  );

  @override
  Future<LandParcel> createStandaloneFieldPlot({
    required LandParcel draft,
    required String projectCode,
    required SpatialTemporalState temporalState,
  }) => workflow.createProductionStandaloneFieldPlot(
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
  @override
  Future<List<LandParcel>> createFieldPlots({
    required List<LandParcel> drafts,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
    required List<ParcelSketchDetails> details,
  }) => workflow.createProductionFieldPlots(
    drafts: drafts,
    parentLandBlockId: parentLandBlockId,
    expectedParentBoundaryVersion: expectedParentBoundaryVersion,
    temporalState: temporalState,
    details: details,
  );
}
