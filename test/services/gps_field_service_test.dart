import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:agrico_deepseek/services/gps_field_service.dart';

void main() {
  final service = GpsFieldService();

  test('calculates area for a small square', () {
    final points = [
      const LatLng(0, 0),
      const LatLng(0, 0.0001),
      const LatLng(0.0001, 0.0001),
      const LatLng(0.0001, 0),
    ];

    final area = service.calculateAreaSquareMeters(points);
    expect(area, closeTo(123.9, 2.0));
  });

  test('returns zero area with fewer than three points', () {
    expect(
      service.calculateAreaSquareMeters([
        const LatLng(0, 0),
        const LatLng(0, 0.0001),
      ]),
      0,
    );
  });
}
