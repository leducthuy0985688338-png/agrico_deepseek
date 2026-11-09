import '../geometry/parcel_subdivision_plan.dart';
import '../../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../entities/land_parcel.dart';
import '../entities/land_survey.dart';

/// Atomic creation port: implementations persist numbering and spatial data together.
abstract interface class ProductionParcelCreationRepository {
  Future<LandParcel> createLandBlock({
    required LandParcel draft,
    required String projectCode,
    List<CropRecord> crops = const [],
    required SpatialTemporalState temporalState,
  });
  Future<LandParcel> createStandaloneFieldPlot({
    required LandParcel draft,
    required String projectCode,
    required SpatialTemporalState temporalState,
  });

  Future<LandParcel> createFieldPlot({
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
  });
  Future<List<LandParcel>> createFieldPlots({
    required List<LandParcel> drafts,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
    required List<ParcelSketchDetails> details,
  });
}
