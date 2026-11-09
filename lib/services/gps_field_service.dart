import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../features/farm/domain/geometry/wgs84_geometry.dart';

/// Handles location permissions, live GPS tracking and geodesic calculations
/// used by the field measurement workflow.
class GpsFieldService {
  Future<bool> ensureLocationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<Position?> getCurrentPosition() async {
    if (!await ensureLocationReady()) return null;
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Stream<Position> positionStream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    ),
  );

  double calculateAreaSquareMeters(List<LatLng> points) {
    if (points.length < 3) return 0;
    try {
      return const Wgs84GeometryService()
          .measure(buildCanonicalPolygon(points))
          .areaM2;
    } on PolygonValidationException {
      return 0;
    }
  }

  double calculatePerimeterMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    if (points.length >= 3) {
      try {
        return const Wgs84GeometryService()
            .measure(buildCanonicalPolygon(points))
            .perimeterM;
      } on PolygonValidationException {
        return 0;
      }
    }
    var total = 0.0;
    for (var i = 0; i < points.length; i++) {
      final next = (i + 1) % points.length;
      total += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[next].latitude,
        points[next].longitude,
      );
    }
    return total;
  }

  Wgs84Polygon buildCanonicalPolygon(List<LatLng> completedPoints) =>
      Wgs84Polygon.fromVertices(
        completedPoints.map(
          (point) =>
              Wgs84Vertex(latitude: point.latitude, longitude: point.longitude),
        ),
      );
}
