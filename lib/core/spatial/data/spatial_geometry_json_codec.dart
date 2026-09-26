import '../domain/geometry/spatial_coordinate.dart';
import '../domain/geometry/spatial_geometry.dart';
import '../domain/geometry/spatial_linear_geometry.dart';
import '../domain/geometry/spatial_multi_geometry.dart';
import '../domain/geometry/spatial_polygon.dart';

/// Converts Spatial Core geometries to and from their canonical JSON shape.
abstract final class SpatialGeometryJsonCodec {
  static Map<String, Object?> encode(SpatialGeometry geometry) {
    geometry.validate();

    return switch (geometry) {
      SpatialPoint() => {
        'type': geometry.geometryType.name,
        'coordinate': _encodeCoordinate(geometry.coordinate),
      },
      SpatialLineString() => {
        'type': geometry.geometryType.name,
        'coordinates': geometry.coordinates.map(_encodeCoordinate).toList(),
      },
      SpatialPolygon() => {
        'type': geometry.geometryType.name,
        'outerRing': geometry.outerRing.map(_encodeCoordinate).toList(),
      },
      SpatialMultiPoint() => {
        'type': geometry.geometryType.name,
        'points': geometry.points
            .map((point) => _encodeCoordinate(point.coordinate))
            .toList(),
      },
      SpatialMultiLineString() => {
        'type': geometry.geometryType.name,
        'lineStrings': geometry.lineStrings
            .map(
              (lineString) =>
                  lineString.coordinates.map(_encodeCoordinate).toList(),
            )
            .toList(),
      },
      SpatialMultiPolygon() => {
        'type': geometry.geometryType.name,
        'polygons': geometry.polygons
            .map(
              (polygon) => <String, Object?>{
                'outerRing': polygon.outerRing.map(_encodeCoordinate).toList(),
              },
            )
            .toList(),
      },
      _ => throw FormatException(
        'Unsupported SpatialGeometry implementation: ${geometry.runtimeType}.',
      ),
    };
  }

  static SpatialGeometry decode(Map<String, Object?> json) {
    final type = _requiredString(json, 'type');

    final geometry = switch (type) {
      'point' => SpatialPoint(
        coordinate: _decodeCoordinate(_requiredMap(json, 'coordinate')),
      ),
      'lineString' => SpatialLineString.fromCoordinates(
        _decodeCoordinates(_requiredList(json, 'coordinates')),
      ),
      'polygon' => SpatialPolygon.fromOuterRing(
        _decodeCoordinates(_requiredList(json, 'outerRing')),
      ),
      'multiPoint' => SpatialMultiPoint.fromPoints(
        _decodeCoordinates(
          _requiredList(json, 'points'),
        ).map((coordinate) => SpatialPoint(coordinate: coordinate)),
      ),
      'multiLineString' => SpatialMultiLineString.fromLineStrings(
        _requiredList(json, 'lineStrings').map(
          (value) => SpatialLineString.fromCoordinates(
            _decodeCoordinates(_asList(value, 'lineStrings item')),
          ),
        ),
      ),
      'multiPolygon' => SpatialMultiPolygon.fromPolygons(
        _requiredList(json, 'polygons').map((value) {
          final polygon = _asMap(value, 'polygons item');
          return SpatialPolygon.fromOuterRing(
            _decodeCoordinates(_requiredList(polygon, 'outerRing')),
          );
        }),
      ),
      _ => throw FormatException(
        'Unknown SpatialGeometry type discriminator: "$type".',
      ),
    };

    geometry.validate();
    return geometry;
  }

  static Map<String, Object?> _encodeCoordinate(SpatialCoordinate coordinate) =>
      {
        'latitude': coordinate.latitude,
        'longitude': coordinate.longitude,
        'altitudeM': coordinate.altitudeM,
      };

  static Iterable<SpatialCoordinate> _decodeCoordinates(List<Object?> values) =>
      values.map(
        (value) => _decodeCoordinate(_asMap(value, 'coordinate item')),
      );

  static SpatialCoordinate _decodeCoordinate(Map<String, Object?> json) {
    final altitude = _requiredNullableNumber(json, 'altitudeM');
    final coordinate = SpatialCoordinate(
      latitude: _requiredNumber(json, 'latitude').toDouble(),
      longitude: _requiredNumber(json, 'longitude').toDouble(),
      altitudeM: altitude?.toDouble(),
    );
    coordinate.validate();
    return coordinate;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('SpatialGeometry "$key" must be a string.');
    }
    return value;
  }

  static num _requiredNumber(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num) {
      throw FormatException('Spatial coordinate "$key" must be numeric.');
    }
    return value;
  }

  static num? _requiredNullableNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw FormatException('Spatial coordinate is missing "$key".');
    }
    final value = json[key];
    if (value != null && value is! num) {
      throw FormatException(
        'Spatial coordinate "$key" must be numeric or null.',
      );
    }
    return value as num?;
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    if (!json.containsKey(key)) {
      throw FormatException('SpatialGeometry is missing "$key".');
    }
    return _asMap(json[key], key);
  }

  static List<Object?> _requiredList(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw FormatException('SpatialGeometry is missing "$key".');
    }
    return _asList(json[key], key);
  }

  static Map<String, Object?> _asMap(Object? value, String context) {
    if (value is! Map) {
      throw FormatException('SpatialGeometry "$context" must be an object.');
    }
    if (value.keys.any((key) => key is! String)) {
      throw FormatException(
        'SpatialGeometry "$context" must have string keys.',
      );
    }
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _asList(Object? value, String context) {
    if (value is! List) {
      throw FormatException('SpatialGeometry "$context" must be a list.');
    }
    return List<Object?>.from(value);
  }
}
