import 'dart:math' as math;

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
            .map((point) => {
                  'lat': point.latitude,
                  'lng': point.longitude,
                })
            .toList(growable: false),
        'segmentDistances': segmentDistances,
        'totalDistance': totalDistance,
        'measuredAt': measuredAt.toUtc().toIso8601String(),
      };

  factory DistanceMeasurement.fromJson(Map<String, dynamic> json) =>
      DistanceMeasurement.fromCloudMap(json);

  factory DistanceMeasurement.fromCloudMap(Map<String, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final measuredAt = _parseDistanceDate(map['measuredAt']);
    final points = _parseDistancePoints(map);

    if (id.isEmpty || measuredAt == null || points.length < 2) {
      throw const FormatException('Dữ liệu đo khoảng cách không hợp lệ.');
    }

    final segments = _parseSegmentDistances(map, points);
    final calculatedTotal =
        segments.fold<double>(0, (sum, distance) => sum + distance);
    final providedTotal = _nonNegativeNumber(
      map['totalDistance'] ?? map['distanceMeters'],
    );
    final totalDistance =
        providedTotal == null || (providedTotal == 0 && calculatedTotal > 0)
            ? calculatedTotal
            : providedTotal;

    if (!totalDistance.isFinite || totalDistance < 0) {
      throw const FormatException('Tổng khoảng cách không hợp lệ.');
    }

    return DistanceMeasurement(
      id: id,
      points: List<LatLng>.unmodifiable(points),
      segmentDistances: List<double>.unmodifiable(segments),
      totalDistance: totalDistance,
      measuredAt: measuredAt,
    );
  }
}

List<DistanceMeasurement> parseDistanceMeasurementDocuments(
  Iterable<Map<String, dynamic>> documents,
) {
  final byId = <String, DistanceMeasurement>{};

  for (final document in documents) {
    try {
      final measurement = DistanceMeasurement.fromCloudMap(document);
      byId[measurement.id] = measurement;
    } on FormatException {
      // Bỏ qua tài liệu Cloud thiếu mã, thời gian hoặc tọa độ hợp lệ.
    }
  }

  final measurements = byId.values.toList(growable: false)
    ..sort((a, b) {
      final byDate = b.measuredAt.compareTo(a.measuredAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  return List<DistanceMeasurement>.unmodifiable(measurements);
}

List<LatLng> _parseDistancePoints(Map<String, dynamic> map) {
  final rawPoints = map['points'];
  if (rawPoints is Iterable) {
    final points = <LatLng>[];
    for (final rawPoint in rawPoints) {
      points.add(_parseDistancePoint(rawPoint));
    }
    return points;
  }

  final start = map['start'];
  final end = map['end'];
  if (start != null && end != null) {
    return [_parseDistancePoint(start), _parseDistancePoint(end)];
  }

  throw const FormatException('Thiếu tọa độ đo khoảng cách.');
}

LatLng _parseDistancePoint(dynamic rawPoint) {
  if (rawPoint is! Map) {
    throw const FormatException('Tọa độ đo khoảng cách không hợp lệ.');
  }

  final latitude = _finiteNumber(rawPoint['lat'] ?? rawPoint['latitude']);
  final longitude = _finiteNumber(rawPoint['lng'] ?? rawPoint['longitude']);
  if (latitude == null ||
      longitude == null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    throw const FormatException('Tọa độ đo khoảng cách không hợp lệ.');
  }

  return LatLng(latitude, longitude);
}

List<double> _parseSegmentDistances(
  Map<String, dynamic> map,
  List<LatLng> points,
) {
  final rawSegments = map['segmentDistances'];
  if (rawSegments is Iterable) {
    final segments = <double>[];
    var valid = true;
    for (final rawDistance in rawSegments) {
      final distance = _nonNegativeNumber(rawDistance);
      if (distance == null) {
        valid = false;
        break;
      }
      segments.add(distance);
    }
    if (valid && segments.length == points.length - 1) {
      return segments;
    }
  }

  final legacyDistance = _nonNegativeNumber(map['distanceMeters']);
  if (legacyDistance != null && points.length == 2) {
    return [legacyDistance];
  }

  return List<double>.generate(
    points.length - 1,
    (index) => _haversineDistance(points[index], points[index + 1]),
    growable: false,
  );
}

DateTime? _parseDistanceDate(dynamic value) {
  DateTime? parsed;
  if (value is DateTime) {
    parsed = value;
  } else if (value is String) {
    parsed = DateTime.tryParse(value);
  } else if (value is num && value.isFinite) {
    try {
      parsed = DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      );
    } on RangeError {
      return null;
    }
  }
  return parsed?.toUtc();
}

double? _finiteNumber(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  return number != null && number.isFinite ? number : null;
}

double? _nonNegativeNumber(dynamic value) {
  final number = _finiteNumber(value);
  return number != null && number >= 0 ? number : null;
}

double _haversineDistance(LatLng start, LatLng end) {
  const earthRadiusMeters = 6371000.0;
  final startLatitude = _degreesToRadians(start.latitude);
  final endLatitude = _degreesToRadians(end.latitude);
  final latitudeDelta = endLatitude - startLatitude;
  final longitudeDelta =
      _degreesToRadians(end.longitude - start.longitude);
  final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final clampedHaversine = haversine.clamp(0.0, 1.0).toDouble();
  final angle = 2 *
      math.atan2(
        math.sqrt(clampedHaversine),
        math.sqrt(1 - clampedHaversine),
      );
  return earthRadiusMeters * angle;
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;
