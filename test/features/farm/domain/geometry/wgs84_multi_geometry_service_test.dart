import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_multi_geometry_service.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_multi_polygon.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_topology.dart';
import 'package:flutter_test/flutter_test.dart';

Wgs84Polygon box(double x, double y, double w, double h) =>
    Wgs84Polygon.fromVertices([
      Wgs84Vertex(latitude: y, longitude: x),
      Wgs84Vertex(latitude: y, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x),
    ]);

Wgs84MultiPolygon multi(Wgs84Polygon first, [Wgs84Polygon? second]) =>
    Wgs84MultiPolygon.fromPolygons(second == null ? [first] : [first, second]);

void main() {
  const service = Wgs84MultiGeometryService();
  const single = Wgs84GeometryService();

  group('Wgs84MultiPolygon value object', () {
    test('fromSingle yields one region', () {
      final m = Wgs84MultiPolygon.fromSingle(box(0, 0, 1, 1));
      expect(m.regionCount, 1);
      expect(m.isSingleRegion, isTrue);
      expect(m.crs, 'EPSG:4326');
    });

    test('fromPolygons rejects empty', () {
      expect(
        () => Wgs84MultiPolygon.fromPolygons(const []),
        throwsFormatException,
      );
    });

    test('polygons list is immutable', () {
      final source = [box(0, 0, 1, 1), box(5, 5, 1, 1)];
      final m = Wgs84MultiPolygon.fromPolygons(source);
      source.clear();
      expect(m.regionCount, 2);
      expect(() => m.polygons.add(box(9, 9, 1, 1)), throwsUnsupportedError);
    });

    test('== and hashCode are value-based', () {
      final a = Wgs84MultiPolygon.fromPolygons([box(0, 0, 1, 1)]);
      final b = Wgs84MultiPolygon.fromPolygons([box(0, 0, 1, 1)]);
      final c = Wgs84MultiPolygon.fromPolygons([box(0, 0, 2, 2)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('order matters for ==', () {
      final a = Wgs84MultiPolygon.fromPolygons([
        box(0, 0, 1, 1),
        box(5, 5, 1, 1),
      ]);
      final b = Wgs84MultiPolygon.fromPolygons([
        box(5, 5, 1, 1),
        box(0, 0, 1, 1),
      ]);
      expect(a, isNot(b));
    });
  });

  group('validateNoInteriorOverlap', () {
    test('disjoint and shared edge are allowed', () {
      service.validateNoInteriorOverlap(
        Wgs84MultiPolygon.fromPolygons([box(0, 0, 1, 1), box(5, 5, 1, 1)]),
      );
      service.validateNoInteriorOverlap(
        Wgs84MultiPolygon.fromPolygons([box(0, 0, 1, 1), box(1, 0, 1, 1)]),
      );
    });

    test('positive overlap is rejected', () {
      expect(
        () => service.validateNoInteriorOverlap(
          Wgs84MultiPolygon.fromPolygons([box(0, 0, 2, 2), box(1, 1, 2, 2)]),
        ),
        throwsFormatException,
      );
    });

    test('identical polygons are rejected', () {
      expect(
        () => service.validateNoInteriorOverlap(
          Wgs84MultiPolygon.fromPolygons([box(0, 0, 1, 1), box(0, 0, 1, 1)]),
        ),
        throwsFormatException,
      );
    });

    test('nested polygons are rejected', () {
      expect(
        () => service.validateNoInteriorOverlap(
          Wgs84MultiPolygon.fromPolygons([box(0, 0, 10, 10), box(1, 1, 1, 1)]),
        ),
        throwsFormatException,
      );
    });
  });

  group('measure (ChatGPT review #4)', () {
    test('total area equals sum of per-polygon areas', () {
      final a = box(0, 0, 1, 1);
      final b = box(5, 5, 1, 1);
      final metrics = service.measure(Wgs84MultiPolygon.fromPolygons([a, b]));
      final expected = single.measure(a).areaM2 + single.measure(b).areaM2;
      expect(metrics.totalAreaM2, closeTo(expected, 1e-6));
    });

    test('total perimeter equals sum of per-polygon perimeters', () {
      final a = box(0, 0, 1, 1);
      final b = box(5, 5, 1, 1);
      final metrics = service.measure(Wgs84MultiPolygon.fromPolygons([a, b]));
      final expected =
          single.measure(a).perimeterM + single.measure(b).perimeterM;
      expect(metrics.totalPerimeterM, closeTo(expected, 1e-6));
    });

    test('representative point is area-weighted centroid', () {
      final a = box(0, 0, 1, 1);
      final b = box(5, 5, 3, 3);
      final metrics = service.measure(Wgs84MultiPolygon.fromPolygons([a, b]));
      final ma = single.measure(a);
      final mb = single.measure(b);
      final total = ma.areaM2 + mb.areaM2;
      final expectedLat =
          (ma.centroid.latitude * ma.areaM2 +
              mb.centroid.latitude * mb.areaM2) /
          total;
      final expectedLon =
          (ma.centroid.longitude * ma.areaM2 +
              mb.centroid.longitude * mb.areaM2) /
          total;
      expect(metrics.representativePoint.latitude, closeTo(expectedLat, 1e-9));
      expect(metrics.representativePoint.longitude, closeTo(expectedLon, 1e-9));
    });

    test('measure rejects identical polygons (no double counting)', () {
      final a = box(0, 0, 1, 1);
      expect(
        () => service.measure(Wgs84MultiPolygon.fromPolygons([a, a])),
        throwsFormatException,
      );
    });

    test('measure rejects nested polygons (no double counting)', () {
      final outer = box(0, 0, 10, 10);
      final inner = box(1, 1, 1, 1);
      expect(
        () => service.measure(Wgs84MultiPolygon.fromPolygons([outer, inner])),
        throwsFormatException,
      );
    });
  });

  group('covers / relateToMulti', () {
    test('covers multi with plot crossing shared edge', () {
      final m = Wgs84MultiPolygon.fromPolygons([
        box(0, 0, 5, 10),
        box(5, 0, 5, 10),
      ]);
      expect(service.covers(m, box(2, 2, 6, 6)), isTrue);
    });

    test('relateToMulti: plot outside', () {
      final m = Wgs84MultiPolygon.fromSingle(box(0, 0, 1, 1));
      final relation = service.relateToMulti(box(5, 5, 1, 1), m);
      expect(relation, Wgs84SpatialRelation.disjoint);
    });
  });
}
