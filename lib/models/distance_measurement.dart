import 'package:google_maps_flutter/google_maps_flutter.dart';

class DistanceMeasurement {
  final String id;
  final List<LatLng> points;
  final List<double> segmentDistances;
  final double totalDistance;
  final DateTime measuredAt;

  const DistanceMeasurement({
    required this.id,
    required this.points,
    required this.segmentDistances,
    required this.totalDistance,
    required this.measuredAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(growable: false),
        'segmentDistances': segmentDistances,
        'totalDistance': totalDistance,
        'measuredAt': measuredAt.toUtc().toIso8601String(),
      };

  factory DistanceMeasurement.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List<dynamic>? ?? const []);
    return DistanceMeasurement(
      id: json['id'] as String,
      points: rawPoints.map((raw) {
        final item = raw as Map<String, dynamic>;
        return LatLng(
          (item['lat'] as num).toDouble(),
          (item['lng'] as num).toDouble(),
        );
      }).toList(growable: false),
      segmentDistances: (json['segmentDistances'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(growable: false),
      totalDistance: (json['totalDistance'] as num).toDouble(),
      measuredAt: DateTime.parse(json['measuredAt'] as String),
    );
  }
}
