import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Handles location permissions, live GPS tracking and geodesic calculations
/// used by the field measurement workflow.
class GpsFieldService {
  Future<bool> ensureLocationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    );
  }

  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    );
  }

  /// Returns polygon area in square metres using a local tangent-plane
  /// approximation. Suitable for normal farm plots and avoids map projection
  /// dependencies.
  double calculateAreaSquareMeters(List<LatLng> points) {
    if (points.length < 3) return 0;

    final lat0 = points.map((p) => p.latitude).reduce((a, b) => a + b) /
        points.length;
    const earthRadius = 6371000.0;
    final cosLat = math.cos(_toRadians(lat0));

    final xy = points.map((p) {
      final x = earthRadius * _toRadians(p.longitude) * cosLat;
      final y = earthRadius * _toRadians(p.latitude);
      return (x, y);
    }).toList();

    var sum = 0.0;
    for (var i = 0; i < xy.length; i++) {
      final j = (i + 1) % xy.length;
      sum += xy[i].$1 * xy[j].$2 - xy[j].$1 * xy[i].$2;
    }
    return sum.abs() / 2;
  }

  double calculatePerimeterMeters(List<LatLng> points) {
    if (points.length < 2) return 0;

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

  double _toRadians(double value) => value * math.pi / 180.0;
}
