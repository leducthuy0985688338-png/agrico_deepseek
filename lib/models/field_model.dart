import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldModel {
  final String id;
  final String name;
  final double area;
  final String crop;
  final String status;
  final List<LatLng> polygon;
  final List<String> photoPaths;

  const FieldModel({
    required this.id,
    required this.name,
    required this.area,
    required this.crop,
    required this.status,
    this.polygon = const [],
    this.photoPaths = const [],
  });

  FieldModel copyWith({
    String? id,
    String? name,
    double? area,
    String? crop,
    String? status,
    List<LatLng>? polygon,
    List<String>? photoPaths,
  }) {
    return FieldModel(
      id: id ?? this.id,
      name: name ?? this.name,
      area: area ?? this.area,
      crop: crop ?? this.crop,
      status: status ?? this.status,
      polygon: polygon ?? this.polygon,
      photoPaths: photoPaths ?? this.photoPaths,
    );
  }
}
