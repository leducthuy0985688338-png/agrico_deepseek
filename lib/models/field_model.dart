import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldModel {
  final String id;
  final String name;
  final double area; // m²
  final String crop; // loại cây trồng
  final String status; // Đang trồng, Thu hoạch, Bỏ hoang
  final List<LatLng> polygon; // tọa độ đa giác (để vẽ ranh giới)
  final List<String> photoUrls; // danh sách ảnh

  FieldModel({
    required this.id,
    required this.name,
    required this.area,
    required this.crop,
    required this.status,
    this.polygon = const [],
    this.photoUrls = const [],
  });
}
