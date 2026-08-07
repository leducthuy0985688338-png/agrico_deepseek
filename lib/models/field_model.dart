import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldModel {
  final String id;
  final String name;
  final double area; // m²
  final String crop;
  final String status;
  final List<LatLng> polygon;
  List<String> photoPaths; // <-- ĐÃ THÊM: danh sách đường dẫn ảnh

  FieldModel({
    required this.id,
    required this.name,
    required this.area,
    required this.crop,
    required this.status,
    this.polygon = const [],
    this.photoPaths = const [], // khởi tạo rỗng
  });

  // Hàm copyWith để cập nhật ảnh
  FieldModel copyWith({List<String>? photoPaths}) {
    return FieldModel(
      id: id,
      name: name,
      area: area,
      crop: crop,
      status: status,
      polygon: polygon,
      photoPaths: photoPaths ?? this.photoPaths,
    );
  }
}
