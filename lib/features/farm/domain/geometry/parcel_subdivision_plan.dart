import 'parcel_boundary_splitter.dart';
import 'parcel_enclosed_splitter.dart';
import 'wgs84_geometry.dart';
import '../entities/land_parcel.dart';
import '../entities/land_survey.dart';

/// Business data recorded for one independently surveyed outline.
class ParcelSketchDetails {
  const ParcelSketchDetails({
    this.layer = ParcelLayer.fieldPlot,
    this.parentSketchIndex,
    this.landUseType = LandUseType.agricultural,
    this.landCondition = LandCondition.unknown,
    this.clearingStatus = ClearingStatus.unknown,
    this.readinessStatus = ReadinessStatus.unknown,
    this.notes,
    this.cropType,
    this.cropQuantity,
    this.cropUnit,
    this.cropGrowthStage,
  });

  final ParcelLayer layer;
  /// A previously drawn land block; null means the source block.
  final int? parentSketchIndex;
  final LandUseType landUseType;
  final LandCondition landCondition;
  final ClearingStatus clearingStatus;
  final ReadinessStatus readinessStatus;
  final String? notes;
  final String? cropType;
  final double? cropQuantity;
  final String? cropUnit;
  final CropGrowthStage? cropGrowthStage;
}

/// Each cut targets one of the current fragments. The selected fragment is
/// replaced by the two resulting polygons; other fragments remain unchanged.
class ParcelSubdivisionCut {
  const ParcelSubdivisionCut({required this.fragmentIndex, required this.path})
      : enclosedPolygon = null;
  const ParcelSubdivisionCut.enclosed({required this.fragmentIndex,
      required Wgs84Polygon polygon})
      : enclosedPolygon = polygon, path = const [];
  final int fragmentIndex;
  final List<Wgs84Vertex> path;
  final Wgs84Polygon? enclosedPolygon;
}

class ParcelSubdivisionPlan {
  const ParcelSubdivisionPlan();

  /// Survey sketches are independent closed outlines. Their measured areas
  /// are not a partition of the source and may overlap each other or its edge.
  List<Wgs84Polygon> sketches(List<ParcelSubdivisionCut> cuts) {
    if (cuts.isEmpty || cuts.length > 99 ||
        cuts.any((cut) => cut.enclosedPolygon == null)) {
      throw const FormatException('Provide 1–99 closed survey outlines.');
    }
    return List.unmodifiable(cuts.map((cut) => cut.enclosedPolygon!));
  }

  List<Wgs84Polygon> apply(
      Wgs84Polygon source, List<ParcelSubdivisionCut> cuts) {
    if (cuts.isEmpty || cuts.length > 99) {
      throw const FormatException('Subdivision needs 1–99 cuts.');
    }
    final parts = <Wgs84Polygon>[source];
    for (final cut in cuts) {
      if (cut.fragmentIndex < 0 || cut.fragmentIndex >= parts.length) {
        throw const FormatException('Cut refers to a missing fragment.');
      }
      final children = cut.enclosedPolygon == null
          ? const ParcelBoundarySplitter()
              .splitAlongPath(parts[cut.fragmentIndex], cut.path)
          : const ParcelEnclosedSplitter()
              .split(parts[cut.fragmentIndex], cut.enclosedPolygon!);
      parts.replaceRange(cut.fragmentIndex, cut.fragmentIndex + 1, children);
    }
    return List.unmodifiable(parts);
  }
}
