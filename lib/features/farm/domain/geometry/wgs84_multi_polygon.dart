import 'dart:collection';

import 'wgs84_geometry.dart';

/// Tập hợp một hoặc nhiều `Wgs84Polygon` biểu diễn một đối tượng không gian
/// duy nhất (ví dụ: Lô có nhiều vùng rời nhau).
///
/// Bất biến:
/// - Luôn chứa ít nhất một polygon.
/// - Danh sách `polygons` không thể sửa từ bên ngoài.
/// - Không tự kiểm chồng nội thất — việc đó thuộc
///   `Wgs84MultiGeometryService.validateNoInteriorOverlap`.
class Wgs84MultiPolygon {
  Wgs84MultiPolygon._(List<Wgs84Polygon> polygons)
    : polygons = UnmodifiableListView(polygons);

  factory Wgs84MultiPolygon.fromPolygons(Iterable<Wgs84Polygon> input) {
    final polygons = List<Wgs84Polygon>.of(input);
    if (polygons.isEmpty) {
      throw const FormatException(
        'Wgs84MultiPolygon requires at least one polygon.',
      );
    }
    for (final polygon in polygons) {
      _assertValid(polygon);
    }
    return Wgs84MultiPolygon._(polygons);
  }

  /// Bọc một polygon đơn thành tập một vùng trong bộ nhớ.
  ///
  /// Chuyển đổi trong bộ nhớ cho tương thích dữ liệu Lô cũ một Polygon.
  /// KHÔNG cập nhật bản ghi hay đổi mã. Migration lưu trữ thuộc P02.
  factory Wgs84MultiPolygon.fromSingle(Wgs84Polygon polygon) {
    _assertValid(polygon);
    return Wgs84MultiPolygon._([polygon]);
  }

  final UnmodifiableListView<Wgs84Polygon> polygons;

  String get crs => Wgs84Polygon.crsCode;

  int get regionCount => polygons.length;

  bool get isSingleRegion => polygons.length == 1;

  void validate() {
    if (polygons.isEmpty) {
      throw const FormatException(
        'Wgs84MultiPolygon requires at least one polygon.',
      );
    }
    for (final polygon in polygons) {
      _assertValid(polygon);
    }
  }

  static void _assertValid(Wgs84Polygon polygon) {
    Wgs84Polygon.fromVertices(polygon.vertices, holes: polygon.holes);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Wgs84MultiPolygon) return false;
    if (polygons.length != other.polygons.length) return false;
    for (var i = 0; i < polygons.length; i++) {
      if (polygons[i] != other.polygons[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(polygons);

  @override
  String toString() => 'Wgs84MultiPolygon(${polygons.length} region(s), $crs)';
}
