import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/services/farm_map_management_service.dart';

void main() {
  const service = FarmMapManagementService();

  FieldModel field({
    required String id,
    required String name,
    required double area,
    required String crop,
    required String status,
    String method = 'gps',
    bool polygon = true,
  }) {
    return FieldModel(
      id: id,
      name: name,
      area: area,
      crop: crop,
      status: status,
      measurementMethod: method,
      polygon: polygon
          ? const [
              LatLng(16.55, 104.75),
              LatLng(16.551, 104.75),
              LatLng(16.551, 104.751),
            ]
          : const [],
    );
  }

  test('filters by search, crop, status and area range', () {
    final fields = [
      field(id: 'F01', name: 'Thửa Bắc', area: 10000, crop: 'Lạc', status: 'Đang sản xuất'),
      field(id: 'F02', name: 'Thửa Nam', area: 20000, crop: 'Ngô', status: 'Đã thu hoạch'),
      field(id: 'F03', name: 'Khu Đông', area: 30000, crop: 'Lạc', status: 'Đang sản xuất'),
    ];

    final result = service.filterFields(
      fields,
      query: 'khu',
      crop: 'Lạc',
      status: 'Đang sản xuất',
      minAreaHa: 2,
      maxAreaHa: 3,
    );

    expect(result.map((field) => field.id), ['F03']);
  });

  test('can include fields without polygon when explicitly requested', () {
    final fields = [
      field(id: 'F01', name: 'Có ranh', area: 10000, crop: 'Lạc', status: 'Đang sản xuất'),
      field(id: 'F02', name: 'Chưa đo', area: 10000, crop: 'Lạc', status: 'Đang sản xuất', polygon: false),
    ];

    expect(service.filterFields(fields), hasLength(1));
    expect(service.filterFields(fields, requirePolygon: false), hasLength(2));
  });

  test('summarizes area, crop, status and measurement method', () {
    final fields = [
      field(id: 'F01', name: 'A', area: 10000, crop: 'Lạc', status: 'Đang sản xuất'),
      field(id: 'F02', name: 'B', area: 20000, crop: 'Lạc', status: 'Đã thu hoạch', method: 'manual'),
      field(id: 'F03', name: 'C', area: 30000, crop: 'Ngô', status: 'Đang sản xuất'),
    ];

    final summary = service.summarize(fields);

    expect(summary.fields, hasLength(3));
    expect(summary.totalArea, 60000);
    expect(summary.totalAreaHa, 6);
    expect(summary.cropArea['Lạc'], 30000);
    expect(summary.cropArea['Ngô'], 30000);
    expect(summary.statusArea['Đang sản xuất'], 40000);
    expect(summary.statusArea['Đã thu hoạch'], 20000);
    expect(summary.measurementCount['gps'], 2);
    expect(summary.measurementCount['manual'], 1);
  });

  test('returns distinct filter options with Tất cả first', () {
    final fields = [
      field(id: 'F01', name: 'A', area: 10000, crop: 'Lạc', status: 'Đang sản xuất'),
      field(id: 'F02', name: 'B', area: 20000, crop: 'Ngô', status: 'Đã thu hoạch'),
      field(id: 'F03', name: 'C', area: 30000, crop: 'Lạc', status: 'Đang sản xuất'),
    ];

    expect(service.cropOptions(fields).first, 'Tất cả');
    expect(service.cropOptions(fields).toSet(), {'Tất cả', 'Lạc', 'Ngô'});
    expect(service.statusOptions(fields).first, 'Tất cả');
    expect(service.statusOptions(fields).toSet(), {'Tất cả', 'Đang sản xuất', 'Đã thu hoạch'});
  });
}
