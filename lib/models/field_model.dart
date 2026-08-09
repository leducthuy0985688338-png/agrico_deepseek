import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldModel {
  final String id;
  final String name;
  final double area;
  final String crop;
  final String status;
  final List<LatLng> polygon;
  final List<String> photoPaths;
  final double perimeter;
  final String measurementMethod;
  final double? gpsAccuracy;
  final DateTime? measuredAt;

  const FieldModel({
    required this.id,
    required this.name,
    required this.area,
    required this.crop,
    required this.status,
    this.polygon = const [],
    this.photoPaths = const [],
    this.perimeter = 0,
    this.measurementMethod = 'unknown',
    this.gpsAccuracy,
    this.measuredAt,
  });

  factory FieldModel.fromJson(Map<String, dynamic> json) {
    final rawPolygon = (json['polygon'] as List<dynamic>? ?? const []);
    final rawMeasuredAt = json['measuredAt'];
    return FieldModel(
      id: json['id'] as String,
      name: json['name'] as String,
      area: (json['area'] as num).toDouble(),
      crop: json['crop'] as String,
      status: json['status'] as String,
      polygon: rawPolygon.map((point) {
        final item = point as Map<String, dynamic>;
        return LatLng(
          (item['lat'] as num).toDouble(),
          (item['lng'] as num).toDouble(),
        );
      }).toList(growable: false),
      photoPaths: List<String>.from(json['photoPaths'] as List<dynamic>? ?? const []),
      perimeter: (json['perimeter'] as num?)?.toDouble() ?? 0,
      measurementMethod: json['measurementMethod'] as String? ?? 'unknown',
      gpsAccuracy: (json['gpsAccuracy'] as num?)?.toDouble(),
      measuredAt: rawMeasuredAt == null ? null : DateTime.tryParse(rawMeasuredAt.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'area': area,
        'crop': crop,
        'status': status,
        'polygon': polygon
            .map((point) => {'lat': point.latitude, 'lng': point.longitude})
            .toList(growable: false),
        'photoPaths': photoPaths,
        'perimeter': perimeter,
        'measurementMethod': measurementMethod,
        'gpsAccuracy': gpsAccuracy,
        'measuredAt': measuredAt?.toUtc().toIso8601String(),
      };

  FieldModel copyWith({
    String? id,
    String? name,
    double? area,
    String? crop,
    String? status,
    List<LatLng>? polygon,
    List<String>? photoPaths,
    double? perimeter,
    String? measurementMethod,
    double? gpsAccuracy,
    DateTime? measuredAt,
  }) {
    return FieldModel(
      id: id ?? this.id,
      name: name ?? this.name,
      area: area ?? this.area,
      crop: crop ?? this.crop,
      status: status ?? this.status,
      polygon: polygon ?? this.polygon,
      photoPaths: photoPaths ?? this.photoPaths,
      perimeter: perimeter ?? this.perimeter,
      measurementMethod: measurementMethod ?? this.measurementMethod,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      measuredAt: measuredAt ?? this.measuredAt,
    );
  }
}
