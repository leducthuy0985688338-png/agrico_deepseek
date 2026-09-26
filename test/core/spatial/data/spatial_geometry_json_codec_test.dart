import 'dart:convert';

import 'package:agrico_deepseek/core/spatial/data/spatial_geometry_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_multi_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinate = SpatialCoordinate(
    latitude: 16.5,
    longitude: 104.7,
    altitudeM: 125.4,
  );
  const secondCoordinate = SpatialCoordinate(
    latitude: 16.500000000123,
    longitude: 104.700000000456,
  );

  SpatialPolygon polygon() => SpatialPolygon.fromOuterRing(const [
    SpatialCoordinate(latitude: 16.0, longitude: 104.0),
    SpatialCoordinate(latitude: 16.0, longitude: 105.0),
    SpatialCoordinate(latitude: 17.0, longitude: 105.0),
  ]);

  void expectCoordinate(SpatialCoordinate actual, SpatialCoordinate expected) {
    expect(actual.latitude, expected.latitude);
    expect(actual.longitude, expected.longitude);
    expect(actual.altitudeM, expected.altitudeM);
  }

  void expectGeometry(SpatialGeometry actual, SpatialGeometry expected) {
    expect(actual.geometryType, expected.geometryType);

    if (actual is SpatialPoint && expected is SpatialPoint) {
      expectCoordinate(actual.coordinate, expected.coordinate);
    } else if (actual is SpatialLineString && expected is SpatialLineString) {
      expect(actual.coordinates, expected.coordinates);
    } else if (actual is SpatialPolygon && expected is SpatialPolygon) {
      expect(actual.outerRing, expected.outerRing);
    } else if (actual is SpatialMultiPoint && expected is SpatialMultiPoint) {
      expect(
        actual.points.map((point) => point.coordinate),
        expected.points.map((point) => point.coordinate),
      );
    } else if (actual is SpatialMultiLineString &&
        expected is SpatialMultiLineString) {
      expect(
        actual.lineStrings.map((lineString) => lineString.coordinates),
        expected.lineStrings.map((lineString) => lineString.coordinates),
      );
    } else if (actual is SpatialMultiPolygon &&
        expected is SpatialMultiPolygon) {
      expect(
        actual.polygons.map((part) => part.outerRing),
        expected.polygons.map((part) => part.outerRing),
      );
    } else {
      fail('Geometry runtime types do not match.');
    }
  }

  SpatialGeometry jsonRoundTrip(SpatialGeometry geometry) {
    final encoded = SpatialGeometryJsonCodec.encode(geometry);
    final decodedJson = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
    return SpatialGeometryJsonCodec.decode(decodedJson);
  }

  group('SpatialGeometryJsonCodec encode', () {
    test('encodes Point using the exact canonical structure', () {
      expect(
        SpatialGeometryJsonCodec.encode(
          const SpatialPoint(coordinate: coordinate),
        ),
        {
          'type': 'point',
          'coordinate': {
            'latitude': 16.5,
            'longitude': 104.7,
            'altitudeM': 125.4,
          },
        },
      );
    });

    test('emits null altitude when altitude is unknown', () {
      expect(
        SpatialGeometryJsonCodec.encode(
          const SpatialPoint(coordinate: secondCoordinate),
        )['coordinate'],
        {
          'latitude': 16.500000000123,
          'longitude': 104.700000000456,
          'altitudeM': null,
        },
      );
    });

    test('contains only values accepted by jsonEncode for all families', () {
      final geometries = <SpatialGeometry>[
        const SpatialPoint(coordinate: coordinate),
        SpatialLineString.fromCoordinates([coordinate, secondCoordinate]),
        polygon(),
        SpatialMultiPoint.fromPoints(const [
          SpatialPoint(coordinate: coordinate),
          SpatialPoint(coordinate: secondCoordinate),
        ]),
        SpatialMultiLineString.fromLineStrings([
          SpatialLineString.fromCoordinates([coordinate, secondCoordinate]),
        ]),
        SpatialMultiPolygon.fromPolygons([polygon()]),
      ];

      for (final geometry in geometries) {
        expect(
          () => jsonEncode(SpatialGeometryJsonCodec.encode(geometry)),
          returnsNormally,
        );
      }
    });
  });

  group('SpatialGeometryJsonCodec round-trip', () {
    test('decodes Point', () {
      final decoded =
          SpatialGeometryJsonCodec.decode({
                'type': 'point',
                'coordinate': {
                  'latitude': 16.5,
                  'longitude': 104.7,
                  'altitudeM': 125.4,
                },
              })
              as SpatialPoint;

      expectCoordinate(decoded.coordinate, coordinate);
    });

    test('round-trips Point including altitude', () {
      final source = const SpatialPoint(coordinate: coordinate);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('round-trips Point with null altitude', () {
      final source = const SpatialPoint(coordinate: secondCoordinate);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('round-trips LineString', () {
      final source = SpatialLineString.fromCoordinates([
        coordinate,
        secondCoordinate,
      ]);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('round-trips Polygon and preserves its closed ring', () {
      final source = polygon();
      final decoded = jsonRoundTrip(source) as SpatialPolygon;

      expectGeometry(decoded, source);
      expect(decoded.outerRing, hasLength(4));
      expect(decoded.outerRing.first, decoded.outerRing.last);
    });

    test('round-trips MultiPoint', () {
      final source = SpatialMultiPoint.fromPoints(const [
        SpatialPoint(coordinate: coordinate),
        SpatialPoint(coordinate: secondCoordinate),
      ]);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('round-trips MultiLineString', () {
      final source = SpatialMultiLineString.fromLineStrings([
        SpatialLineString.fromCoordinates([coordinate, secondCoordinate]),
      ]);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('round-trips MultiPolygon', () {
      final source = SpatialMultiPolygon.fromPolygons([polygon()]);
      expectGeometry(jsonRoundTrip(source), source);
    });

    test('preserves coordinate numeric precision without truncation', () {
      final decoded =
          jsonRoundTrip(const SpatialPoint(coordinate: secondCoordinate))
              as SpatialPoint;
      expectCoordinate(decoded.coordinate, secondCoordinate);
    });
  });

  group('SpatialGeometryJsonCodec rejection', () {
    test('rejects an unknown geometry type discriminator', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({'type': 'circle'}),
        throwsFormatException,
      );
    });

    test('rejects a missing geometry type discriminator', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'coordinate': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    for (final malformed in <Map<String, Object?>>[
      {'longitude': 104.7, 'altitudeM': null},
      {'latitude': 16.5, 'altitudeM': null},
      {'latitude': '16.5', 'longitude': 104.7, 'altitudeM': null},
    ]) {
      test('rejects malformed coordinate $malformed', () {
        expect(
          () => SpatialGeometryJsonCodec.decode({
            'type': 'point',
            'coordinate': malformed,
          }),
          throwsFormatException,
        );
      });
    }

    test('rejects invalid latitude and longitude through validation', () {
      for (final coordinateJson in [
        {'latitude': 91.0, 'longitude': 104.7, 'altitudeM': null},
        {'latitude': 16.5, 'longitude': 181.0, 'altitudeM': null},
      ]) {
        expect(
          () => SpatialGeometryJsonCodec.decode({
            'type': 'point',
            'coordinate': coordinateJson,
          }),
          throwsFormatException,
        );
      }
    });

    test('rejects malformed geometry structure', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'type': 'lineString',
          'coordinates': 'not-a-list',
        }),
        throwsFormatException,
      );
    });

    test('rejects geometry type and payload mismatch', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'type': 'point',
          'coordinates': [
            {'latitude': 16.5, 'longitude': 104.7, 'altitudeM': null},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects an invalid polygon through domain validation', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'type': 'polygon',
          'outerRing': [
            {'latitude': 16.0, 'longitude': 104.0, 'altitudeM': null},
            {'latitude': 17.0, 'longitude': 105.0, 'altitudeM': null},
            {'latitude': 16.0, 'longitude': 105.0, 'altitudeM': null},
            {'latitude': 17.0, 'longitude': 104.0, 'altitudeM': null},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects an invalid LineString through domain validation', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'type': 'lineString',
          'coordinates': [
            {'latitude': 16.5, 'longitude': 104.7, 'altitudeM': null},
          ],
        }),
        throwsFormatException,
      );
    });

    test(
      'does not accept unsupported fields as required-field substitutes',
      () {
        expect(
          () => SpatialGeometryJsonCodec.decode({
            'type': 'polygon',
            'coordinates': [
              {'latitude': 16.0, 'longitude': 104.0, 'altitudeM': null},
              {'latitude': 16.0, 'longitude': 105.0, 'altitudeM': null},
              {'latitude': 17.0, 'longitude': 105.0, 'altitudeM': null},
            ],
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects malformed nested multi geometry', () {
      expect(
        () => SpatialGeometryJsonCodec.decode({
          'type': 'multiPolygon',
          'polygons': [
            {'coordinates': <Object?>[]},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
