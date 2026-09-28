import 'parcel_boundary_splitter.dart';
import 'parcel_enclosed_splitter.dart';
import 'wgs84_geometry.dart';

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
