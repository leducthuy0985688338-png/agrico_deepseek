import 'package:google_maps_flutter/google_maps_flutter.dart';

class DistanceMeasurementModel {
  final String id;
  final LatLng start;
  final LatLng end;
  final double distanceMeters;
  final DateTime measuredAt;
  final String method;

  const DistanceMeasurementModel({
    required this.id,
    required this.start,
    required this.end,
    required this.distanceMeters,
    required this.measuredAt,
    this.method = 'manual',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': {'lat': start.latitude, 'lng': start.longitude},
        'end': {'lat': end.latitude, 'lng': end.longitude},
        'distanceMeters': distanceMeters,
        'measuredAt': measuredAt.toUtc().toIso8601String(),
        'method': method,
      };
}
