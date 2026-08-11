import 'package:agrico_deepseek/models/field_measurement_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('field measurement cloud round trip keeps the full boundary', () {
    final source = FieldMeasurementHistory(
      id: 'FM-001',
      fieldId: 'FIELD-001',
      fieldName: 'Lô lạc A1',
      measurementMethod: 'gps',
      polygon: const [
        LatLng(16.5500, 104.7500),
        LatLng(16.5510, 104.7500),
        LatLng(16.5510, 104.7510),
      ],
      area: 6150.5,
      perimeter: 340.2,
      gpsAccuracy: 2.8,
      measuredAt: DateTime.utc(2026, 8, 11, 6),
      createdAt: DateTime.utc(2026, 8, 11, 6, 1),
    );

    final restored = FieldMeasurementHistory.fromCloudMap(source.toJson());

    expect(restored.id, source.id);
    expect(restored.fieldId, source.fieldId);
    expect(restored.fieldName, source.fieldName);
    expect(restored.measurementMethod, source.measurementMethod);
    expect(restored.polygon, source.polygon);
    expect(restored.area, source.area);
    expect(restored.perimeter, source.perimeter);
    expect(restored.gpsAccuracy, source.gpsAccuracy);
    expect(restored.measuredAt, source.measuredAt);
    expect(restored.createdAt, source.createdAt);
  });

  test('legacy keys and numeric strings are normalized safely', () {
    final restored = FieldMeasurementHistory.fromCloudMap({
      'id': 'FM-LEGACY',
      'field_id': 'FIELD-LEGACY',
      'field_name': 'Lô cũ',
      'measurement_method': 'manual-edited',
      'polygon': [
        {'latitude': '16.55', 'longitude': '104.75'},
        {'latitude': '16.551', 'longitude': '104.75'},
        {'latitude': '16.551', 'longitude': '104.751'},
      ],
      'area': '6200.5',
      'perimeter': '345.8',
      'gps_accuracy': '3.5',
      'measured_at': '2026-08-10T03:00:00.000Z',
    });

    expect(restored.fieldId, 'FIELD-LEGACY');
    expect(restored.polygon, hasLength(3));
    expect(restored.area, 6200.5);
    expect(restored.perimeter, 345.8);
    expect(restored.gpsAccuracy, 3.5);
    expect(restored.createdAt, restored.measuredAt);
  });

  test('documents are deduplicated, sorted, and invalid rows are skipped', () {
    final restored = parseFieldMeasurementDocuments([
      _document(
        id: 'FM-DUPLICATE',
        fieldId: 'FIELD-1',
        createdAt: '2026-08-10T00:00:00.000Z',
        area: 5000,
      ),
      _document(
        id: 'FM-NEWEST',
        fieldId: 'FIELD-2',
        createdAt: '2026-08-12T00:00:00.000Z',
        area: 7000,
      ),
      _document(
        id: 'FM-DUPLICATE',
        fieldId: 'FIELD-1',
        createdAt: '2026-08-11T00:00:00.000Z',
        area: 6500,
      ),
      {
        ..._document(
          id: 'FM-BROKEN',
          fieldId: 'FIELD-3',
          createdAt: '2026-08-13T00:00:00.000Z',
          area: 8000,
        ),
        'polygon': [
          {'lat': 999, 'lng': 104.75},
          {'lat': 16.55, 'lng': 104.75},
          {'lat': 16.56, 'lng': 104.76},
        ],
      },
    ]);

    expect(restored.map((item) => item.id), [
      'FM-NEWEST',
      'FM-DUPLICATE',
    ]);
    expect(restored.last.area, 6500);
  });

  test('history without a current field link is filtered before restore', () {
    final measurements = parseFieldMeasurementDocuments([
      _document(
        id: 'FM-KEEP',
        fieldId: 'FIELD-KEEP',
        createdAt: '2026-08-12T00:00:00.000Z',
        area: 7000,
      ),
      _document(
        id: 'FM-SKIP',
        fieldId: 'FIELD-MISSING',
        createdAt: '2026-08-11T00:00:00.000Z',
        area: 6500,
      ),
    ]);

    final valid =
        keepMeasurementsForFields(measurements, {'FIELD-KEEP'});

    expect(valid.map((item) => item.id), ['FM-KEEP']);
  });

  test('empty or wholly invalid Cloud payload normalizes to an empty list', () {
    expect(parseFieldMeasurementDocuments(const []), isEmpty);
    expect(
      parseFieldMeasurementDocuments([
        {
          'id': ' ',
          'fieldId': 'FIELD-1',
          'fieldName': 'Lô lỗi',
          'polygon': const [],
          'area': 0,
          'measuredAt': 'not-a-date',
        },
      ]),
      isEmpty,
    );
  });
}

Map<String, dynamic> _document({
  required String id,
  required String fieldId,
  required String createdAt,
  required double area,
}) =>
    {
      'id': id,
      'fieldId': fieldId,
      'fieldName': 'Lô kiểm thử',
      'measurementMethod': 'gps',
      'polygon': [
        {'lat': 16.55, 'lng': 104.75},
        {'lat': 16.551, 'lng': 104.75},
        {'lat': 16.551, 'lng': 104.751},
      ],
      'area': area,
      'perimeter': 350,
      'measuredAt': createdAt,
      'createdAt': createdAt,
    };
