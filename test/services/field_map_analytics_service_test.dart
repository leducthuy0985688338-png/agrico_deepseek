import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/services/field_map_analytics_service.dart';

void main() {
  test('calculates field map statistics by crop, status and measurement method', () {
    final fields = [
      FieldModel(
        id: 'F1',
        name: 'Lô A',
        area: 10000,
        crop: 'Lạc',
        status: 'Đang trồng',
        measurementMethod: 'gps',
        polygon: const [
          LatLng(16.55, 104.75),
          LatLng(16.55, 104.751),
          LatLng(16.551, 104.751),
        ],
      ),
      const FieldModel(
        id: 'F2',
        name: 'Lô B',
        area: 20000,
        crop: 'Lạc',
        status: 'Chuẩn bị thu hoạch',
        measurementMethod: 'manual',
      ),
    ];

    final analytics = FieldMapAnalytics.calculate(fields);

    expect(analytics.totalFields, 2);
    expect(analytics.mappedFields, 1);
    expect(analytics.totalAreaSquareMeters, 30000);
    expect(analytics.totalAreaHa, 3);
    expect(analytics.areaByCrop['Lạc'], 30000);
    expect(analytics.countByStatus['Đang trồng'], 1);
    expect(analytics.countByStatus['Chuẩn bị thu hoạch'], 1);
    expect(analytics.countByMeasurementMethod['gps'], 1);
    expect(analytics.countByMeasurementMethod['manual'], 1);
  });

  test('normalizes empty crop and status values', () {
    const field = FieldModel(
      id: 'F3',
      name: 'Lô C',
      area: 5000,
      crop: '',
      status: '',
    );

    final analytics = FieldMapAnalytics.calculate([field]);

    expect(analytics.areaByCrop['Chưa xác định'], 5000);
    expect(analytics.countByStatus['Chưa xác định'], 1);
    expect(analytics.countByMeasurementMethod['unknown'], 1);
  });
}
