import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldMeasurementHistory {
  final String id;
  final String fieldId;
  final String fieldName;
  final String measurementMethod;
  final List<LatLng> polygon;
  final double area;
  final double perimeter;
  final double? gpsAccuracy;
  final DateTime measuredAt;
  final DateTime createdAt;

  const FieldMeasurementHistory({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.measurementMethod,
    required this.polygon,
    required this.area,
    required this.perimeter,
    required this.measuredAt,
    required this.createdAt,
    this.gpsAccuracy,
  });

  factory FieldMeasurementHistory.fromCloudMap(Map<String, dynamic> json) {
    final id = _requiredText(json['id'], 'id');
    final fieldId = _requiredText(json['fieldId'] ?? json['field_id'], 'fieldId');
    final fieldName = _requiredText(
      json['fieldName'] ?? json['field_name'],
      'fieldName',
    );
    final rawPolygon = json['polygon'];
    if (rawPolygon is! List) {
      throw const FormatException('polygon must be a list');
    }

    final polygon = rawPolygon.map((rawPoint) {
      if (rawPoint is! Map) {
        throw const FormatException('polygon point must be a map');
      }
      final point = Map<String, dynamic>.from(rawPoint);
      final latitude = _requiredNumber(
        point['lat'] ?? point['latitude'],
        'latitude',
      );
      final longitude = _requiredNumber(
        point['lng'] ?? point['longitude'],
        'longitude',
      );
      if (latitude < -90 || latitude > 90) {
        throw const FormatException('latitude is outside its valid range');
      }
      if (longitude < -180 || longitude > 180) {
        throw const FormatException('longitude is outside its valid range');
      }
      return LatLng(latitude, longitude);
    }).toList(growable: false);

    if (polygon.length < 3) {
      throw const FormatException('field measurement requires 3 points');
    }

    final area = _requiredNumber(json['area'], 'area');
    final perimeter = _requiredNumber(json['perimeter'] ?? 0, 'perimeter');
    if (area <= 0) {
      throw const FormatException('area must be positive');
    }
    if (perimeter < 0) {
      throw const FormatException('perimeter cannot be negative');
    }

    final measuredAt = _requiredDate(json['measuredAt'] ?? json['measured_at']);
    final createdAt = _optionalDate(
          json['createdAt'] ?? json['created_at'],
        ) ??
        measuredAt;
    final rawAccuracy = json['gpsAccuracy'] ?? json['gps_accuracy'];
    final gpsAccuracy = rawAccuracy == null
        ? null
        : _requiredNumber(rawAccuracy, 'gpsAccuracy');
    if (gpsAccuracy != null && gpsAccuracy < 0) {
      throw const FormatException('gpsAccuracy cannot be negative');
    }

    return FieldMeasurementHistory(
      id: id,
      fieldId: fieldId,
      fieldName: fieldName,
      measurementMethod:
          _optionalText(json['measurementMethod'] ?? json['measurement_method']) ??
              'unknown',
      polygon: polygon,
      area: area,
      perimeter: perimeter,
      gpsAccuracy: gpsAccuracy,
      measuredAt: measuredAt.toUtc(),
      createdAt: createdAt.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fieldId': fieldId,
        'fieldName': fieldName,
        'measurementMethod': measurementMethod,
        'polygon': polygon
            .map(
              (point) => {
                'lat': point.latitude,
                'lng': point.longitude,
              },
            )
            .toList(growable: false),
        'area': area,
        'perimeter': perimeter,
        'gpsAccuracy': gpsAccuracy,
        'measuredAt': measuredAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

List<FieldMeasurementHistory> parseFieldMeasurementDocuments(
  Iterable<Map<String, dynamic>> documents,
) {
  final byId = <String, FieldMeasurementHistory>{};

  for (final document in documents) {
    try {
      final measurement = FieldMeasurementHistory.fromCloudMap(document);
      final current = byId[measurement.id];
      if (current == null ||
          !measurement.createdAt.isBefore(current.createdAt)) {
        byId[measurement.id] = measurement;
      }
    } on FormatException {
      // Ignore one malformed Cloud document and continue restoring the rest.
    } on TypeError {
      // Ignore documents with unexpected nested value types.
    }
  }

  final measurements = byId.values.toList(growable: false)
    ..sort((a, b) {
      final byCreatedAt = b.createdAt.compareTo(a.createdAt);
      if (byCreatedAt != 0) return byCreatedAt;
      final byMeasuredAt = b.measuredAt.compareTo(a.measuredAt);
      if (byMeasuredAt != 0) return byMeasuredAt;
      return a.id.compareTo(b.id);
    });
  return measurements;
}

List<FieldMeasurementHistory> keepMeasurementsForFields(
  Iterable<FieldMeasurementHistory> measurements,
  Set<String> fieldIds,
) =>
    measurements
        .where((measurement) => fieldIds.contains(measurement.fieldId))
        .toList(growable: false);

String _requiredText(Object? value, String fieldName) {
  final text = _optionalText(value);
  if (text == null) {
    throw FormatException('$fieldName is required');
  }
  return text;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _requiredNumber(Object? value, String fieldName) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  if (number == null || !number.isFinite) {
    throw FormatException('$fieldName must be a finite number');
  }
  return number;
}

DateTime _requiredDate(Object? value) {
  final date = _optionalDate(value);
  if (date == null) {
    throw const FormatException('measurement date is required');
  }
  return date;
}

DateTime? _optionalDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
