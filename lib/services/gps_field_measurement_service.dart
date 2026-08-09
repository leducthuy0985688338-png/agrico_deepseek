import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GpsFieldMeasurementService {
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const GpsMeasurementException('Dịch vụ vị trí đang tắt. Hãy bật GPS trên điện thoại.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const GpsMeasurementException('Chưa được cấp quyền vị trí.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const GpsMeasurementException('Quyền vị trí đã bị từ chối vĩnh viễn. Hãy cấp quyền trong Cài đặt.');
    }
  }

  Future<Position> currentPosition() async {
    await ensurePermission();
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  Stream<Position> positionStream() async* {
    await ensurePermission();
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      ),
    );
  }

  double polygonAreaSquareMeters(List<LatLng> points) {
    if (points.length < 3) return 0;
    final lat0 = points.fold<double>(0, (sum, p) => sum + p.latitude) / points.length;
    final latScale = 111320.0;
    final lngScale = 111320.0 * math.cos(lat0 * math.pi / 180.0);
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final ax = a.longitude * lngScale;
      final ay = a.latitude * latScale;
      final bx = b.longitude * lngScale;
      final by = b.latitude * latScale;
      area += ax * by - bx * ay;
    }
    return area.abs() / 2;
  }

  double polygonPerimeterMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[(i + 1) % points.length].latitude,
        points[(i + 1) % points.length].longitude,
      );
    }
    return total;
  }

  double accuracyScore(double accuracyMeters) {
    if (accuracyMeters <= 3) return 1;
    if (accuracyMeters >= 30) return 0;
    return 1 - ((accuracyMeters - 3) / 27);
  }
}

class GpsMeasurementException implements Exception {
  final String message;
  const GpsMeasurementException(this.message);
  @override
  String toString() => message;
}
