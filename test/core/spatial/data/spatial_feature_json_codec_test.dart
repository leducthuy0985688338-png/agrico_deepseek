import 'dart:convert';

import 'package:agrico_deepseek/core/spatial/data/spatial_feature_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.parse('2026-01-02T03:04:05+07:00');
  final updatedAt = DateTime.parse('2026-01-03T04:05:06+07:00');

  SpatialFeature buildFeature({
    SpatialPoint? geometry = const SpatialPoint(
      coordinate: SpatialCoordinate(
        latitude: 16.500000000123,
        longitude: 104.700000000456,
        altitudeM: 125.4,
      ),
    ),
    SpatialGeometryType geometryType = SpatialGeometryType.point,
    SpatialFeatureLifecycleStatus lifecycleStatus =
        SpatialFeatureLifecycleStatus.active,
    String? projectId = 'project-1',
    String? businessUnitId = 'unit-1',
    String? code = 'ລະຫັດ-01',
    String? name = 'Thửa đất Việt–Lào',
    int schemaVersion = 3,
  }) => SpatialFeature(
    id: 'feature-1',
    featureType: SpatialFeatureTypes.landParcel,
    geometryType: geometryType,
    geometry: geometry,
    lifecycleStatus: lifecycleStatus,
    projectId: projectId,
    businessUnitId: businessUnitId,
    code: code,
    name: name,
    createdAt: createdAt,
    createdBy: 'user-1',
    updatedAt: updatedAt,
    updatedBy: 'user-2',
    schemaVersion: schemaVersion,
  );

  Map<String, Object?> completeJson() => {
    'id': 'feature-1',
    'featureType': 'landParcel',
    'geometryType': 'point',
    'geometry': {
      'type': 'point',
      'coordinate': {
        'latitude': 16.500000000123,
        'longitude': 104.700000000456,
        'altitudeM': 125.4,
      },
    },
    'lifecycleStatus': 'active',
    'projectId': 'project-1',
    'businessUnitId': 'unit-1',
    'code': 'ລະຫັດ-01',
    'name': 'Thửa đất Việt–Lào',
    'createdAt': '2026-01-01T20:04:05.000Z',
    'createdBy': 'user-1',
    'updatedAt': '2026-01-02T21:05:06.000Z',
    'updatedBy': 'user-2',
    'schemaVersion': 3,
  };

  void expectFeature(SpatialFeature actual, SpatialFeature expected) {
    expect(actual.id, expected.id);
    expect(actual.featureType, expected.featureType);
    expect(actual.geometryType, expected.geometryType);
    expect(actual.lifecycleStatus, expected.lifecycleStatus);
    expect(actual.projectId, expected.projectId);
    expect(actual.businessUnitId, expected.businessUnitId);
    expect(actual.code, expected.code);
    expect(actual.name, expected.name);
    expect(actual.createdAt, expected.createdAt.toUtc());
    expect(actual.createdBy, expected.createdBy);
    expect(actual.updatedAt, expected.updatedAt.toUtc());
    expect(actual.updatedBy, expected.updatedBy);
    expect(actual.schemaVersion, expected.schemaVersion);
    final actualPoint = actual.geometry as SpatialPoint?;
    final expectedPoint = expected.geometry as SpatialPoint?;
    expect(actualPoint?.coordinate, expectedPoint?.coordinate);
  }

  test('encodes a complete feature using the exact canonical structure', () {
    expect(SpatialFeatureJsonCodec.encode(buildFeature()), completeJson());
  });

  test('round-trips a feature with concrete geometry', () {
    final source = buildFeature();
    expectFeature(SpatialFeatureJsonCodec.decode(completeJson()), source);
  });

  test('round-trips null geometry and nullable scope fields', () {
    final source = buildFeature(
      geometry: null,
      projectId: null,
      businessUnitId: null,
      code: null,
      name: null,
    );
    final decoded = SpatialFeatureJsonCodec.decode(
      SpatialFeatureJsonCodec.encode(source),
    );
    expectFeature(decoded, source);
  });

  test('preserves every lifecycle enum', () {
    for (final status in SpatialFeatureLifecycleStatus.values) {
      final source = buildFeature(lifecycleStatus: status);
      expect(
        SpatialFeatureJsonCodec.decode(
          SpatialFeatureJsonCodec.encode(source),
        ).lifecycleStatus,
        status,
      );
    }
  });

  test('uses UTC ISO-8601 timestamps and preserves schemaVersion', () {
    final encoded = SpatialFeatureJsonCodec.encode(buildFeature());
    expect(encoded['createdAt'], '2026-01-01T20:04:05.000Z');
    expect(encoded['updatedAt'], '2026-01-02T21:05:06.000Z');
    expect(encoded['schemaVersion'], 3);
  });

  test('preserves Unicode code and name', () {
    final decoded = SpatialFeatureJsonCodec.decode(completeJson());
    expect(decoded.code, 'ລະຫັດ-01');
    expect(decoded.name, 'Thửa đất Việt–Lào');
  });

  test('jsonEncode/jsonDecode round-trip is semantically lossless', () {
    final source = buildFeature();
    final json =
        jsonDecode(jsonEncode(SpatialFeatureJsonCodec.encode(source)))
            as Map<String, dynamic>;
    expectFeature(SpatialFeatureJsonCodec.decode(json), source);
  });

  test('rejects unknown lifecycle enum', () {
    final json = completeJson()..['lifecycleStatus'] = 'retired';
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects unknown geometryType', () {
    final json = completeJson()..['geometryType'] = 'circle';
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects missing id', () {
    final json = completeJson()..remove('id');
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects blank required strings through validation', () {
    for (final field in ['id', 'featureType', 'createdBy', 'updatedBy']) {
      final json = completeJson()..[field] = '   ';
      expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
    }
  });

  test('rejects invalid DateTime', () {
    final json = completeJson()..['createdAt'] = 'not-a-date';
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects wrong or non-positive schemaVersion', () {
    for (final value in <Object?>['3', 0, -1, null]) {
      final json = completeJson()..['schemaVersion'] = value;
      expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
    }
  });

  test(
    'does not substitute the constructor default for missing schemaVersion',
    () {
      final json = completeJson()..remove('schemaVersion');
      expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
    },
  );

  test('rejects malformed geometry payload', () {
    final json = completeJson()..['geometry'] = 'point';
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects geometryType and concrete geometry mismatch', () {
    final json = completeJson()..['geometryType'] = 'polygon';
    expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
  });

  test('rejects wrong primitive and container types', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (json) => json['id'] = 1,
      (json) => json['geometry'] = <Object?>[],
      (json) => json['projectId'] = 1,
      (json) => json['schemaVersion'] = 1.0,
    ]) {
      final json = completeJson();
      mutation(json);
      expect(() => SpatialFeatureJsonCodec.decode(json), throwsFormatException);
    }
  });
}
