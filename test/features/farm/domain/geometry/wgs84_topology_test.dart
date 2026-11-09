import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_topology.dart';
import 'package:flutter_test/flutter_test.dart';

Wgs84Polygon box(double x, double y, double w, double h) =>
    Wgs84Polygon.fromVertices([
      Wgs84Vertex(latitude: y, longitude: x),
      Wgs84Vertex(latitude: y, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x),
    ]);

Wgs84Polygon withHole(Wgs84Polygon outer, Wgs84Polygon hole) =>
    Wgs84Polygon.fromVertices(outer.vertices, holes: [hole.vertices]);

void main() {
  const topology = Wgs84Topology();

  group('locate', () {
    final square = box(0, 0, 1, 1);

    test('inside, boundary, outside', () {
      expect(
        topology.locate(
          square,
          const Wgs84Vertex(latitude: 0.5, longitude: 0.5),
        ),
        1,
      );
      expect(
        topology.locate(square, const Wgs84Vertex(latitude: 0, longitude: 0.5)),
        0,
      );
      expect(
        topology.locate(square, const Wgs84Vertex(latitude: 2, longitude: 2)),
        -1,
      );
    });

    test('point inside a hole is outside the polygon', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      expect(
        topology.locate(donut, const Wgs84Vertex(latitude: 5, longitude: 5)),
        -1,
      );
    });
  });

  group('relate', () {
    test('equal polygons', () {
      expect(
        topology.relate(box(0, 0, 1, 1), box(0, 0, 1, 1)),
        Wgs84SpatialRelation.equal,
      );
    });

    test('shared edge is boundaryOnly', () {
      expect(
        topology.relate(box(0, 0, 1, 1), box(1, 0, 1, 1)),
        Wgs84SpatialRelation.boundaryOnly,
      );
    });

    test('shared vertex is boundaryOnly', () {
      expect(
        topology.relate(box(0, 0, 1, 1), box(1, 1, 1, 1)),
        Wgs84SpatialRelation.boundaryOnly,
      );
    });

    test('disjoint', () {
      expect(
        topology.relate(box(0, 0, 1, 1), box(5, 5, 1, 1)),
        Wgs84SpatialRelation.disjoint,
      );
    });

    test('partial overlap', () {
      expect(
        topology.relate(box(0, 0, 2, 2), box(1, 1, 2, 2)),
        Wgs84SpatialRelation.partiallyOverlap,
      );
    });

    test('cross without vertices inside', () {
      final a = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 3),
        Wgs84Vertex(latitude: 1, longitude: 3),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      final b = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: -1, longitude: 1),
        Wgs84Vertex(latitude: -1, longitude: 2),
        Wgs84Vertex(latitude: 2, longitude: 2),
        Wgs84Vertex(latitude: 2, longitude: 1),
      ]);
      expect(topology.relate(a, b), Wgs84SpatialRelation.partiallyOverlap);
    });

    test('contains / containedBy', () {
      expect(
        topology.relate(box(0, 0, 10, 10), box(1, 1, 1, 1)),
        Wgs84SpatialRelation.contains,
      );
      expect(
        topology.relate(box(1, 1, 1, 1), box(0, 0, 10, 10)),
        Wgs84SpatialRelation.containedBy,
      );
    });

    test('closed edge from last vertex to first is detected', () {
      final a = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      final b = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 0, longitude: 2),
        Wgs84Vertex(latitude: 1, longitude: 1),
      ]);
      expect(topology.relate(a, b), Wgs84SpatialRelation.boundaryOnly);
    });
  });

  group('relateToMulti', () {
    test('plot spanning two adjacent regions is containedBy', () {
      final left = box(0, 0, 5, 10);
      final right = box(5, 0, 5, 10);
      final plot = box(2, 2, 6, 6);
      expect(
        topology.relateToMulti(plot, [left, right]),
        Wgs84SpatialRelation.containedBy,
      );
    });

    test('plot spanning gap between two regions is contains', () {
      final left = box(0, 0, 1, 1);
      final right = box(3, 0, 1, 1);
      final plot = box(0, 0, 4, 1);
      final relation = topology.relateToMulti(plot, [left, right]);
      expect(relation, isNot(Wgs84SpatialRelation.containedBy));
      expect(relation, Wgs84SpatialRelation.contains);
    });

    test('plot contains one region but misses another is partial', () {
      final left = box(0, 0, 1, 1);
      final right = box(5, 5, 1, 1);
      final plot = box(-1, -1, 3, 3);
      expect(
        topology.relateToMulti(plot, [left, right]),
        Wgs84SpatialRelation.partiallyOverlap,
      );
    });

    test('plot touching union at mid-edge is boundaryOnly', () {
      final left = box(0, 0, 5, 10);
      final right = box(5, 0, 5, 10);
      final plot = box(10, 4, 1, 2);
      expect(
        topology.relateToMulti(plot, [left, right]),
        Wgs84SpatialRelation.boundaryOnly,
      );
    });

    test('plot clipped by a hole is partial', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      final plot = box(3, 3, 4, 4);
      expect(
        topology.relateToMulti(plot, [donut]),
        Wgs84SpatialRelation.partiallyOverlap,
      );
    });
  });

  group('coversMulti', () {
    test('multi covers plot crossing shared edge', () {
      final left = box(0, 0, 5, 10);
      final right = box(5, 0, 5, 10);
      final plot = box(2, 2, 6, 6);
      expect(topology.coversMulti([left, right], plot), isTrue);
    });

    test('multi does not cover plot crossing a gap', () {
      final left = box(0, 0, 1, 1);
      final right = box(3, 0, 1, 1);
      final plot = box(0, 0, 4, 1);
      expect(topology.coversMulti([left, right], plot), isFalse);
    });

    test('multi does not cover plot crossing a hole', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      final plot = box(3, 3, 4, 4);
      expect(topology.coversMulti([donut], plot), isFalse);
    });
  });

  group('coversMulti — sweep partition (ChatGPT review)', () {
    test(
      'small hole inside large box is NOT covered (below grid resolution)',
      () {
        final donut = withHole(box(0, 0, 10, 10), box(4.9, 4.9, 0.2, 0.2));
        expect(topology.coversMulti([donut], box(0, 0, 10, 10)), isFalse);
      },
    );

    test(
      'four regions with tiny gap at (3, 3)-(3.2, 3.2) are not covering',
      () {
        final regions = [
          box(0, 0, 10, 3),
          box(0, 3.2, 10, 6.8),
          box(0, 3, 3, 0.2),
          box(3.2, 3, 6.8, 0.2),
        ];
        expect(topology.coversMulti(regions, box(0, 0, 10, 10)), isFalse);
        expect(
          topology.relateToMulti(box(0, 0, 10, 10), regions),
          Wgs84SpatialRelation.contains,
        );
      },
    );

    test('four regions forming a frame do NOT cover a plot in the gap', () {
      final top = box(0, 4, 5, 1);
      final bottom = box(0, 0, 5, 1);
      final left = box(0, 1, 1, 3);
      final right = box(4, 1, 1, 3);
      final plot = box(1.5, 1.5, 2, 2);
      expect(topology.coversMulti([top, bottom, left, right], plot), isFalse);
    });

    test('donut hole filled by another region covers a plot over the hole', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      final plug = box(4, 4, 2, 2);
      final plot = box(4.5, 4.5, 1, 1);
      expect(topology.coversMulti([donut, plug], plot), isTrue);
    });

    test('triangular hole is NOT covered (edge crosses cell center)', () {
      final triangularHole = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 4, longitude: 4),
        Wgs84Vertex(latitude: 4, longitude: 6),
        Wgs84Vertex(latitude: 6, longitude: 4),
      ]);
      final donut = withHole(box(0, 0, 10, 10), triangularHole);
      expect(topology.coversMulti([donut], box(0, 0, 10, 10)), isFalse);
    });

    test('diagonal hole edge is NOT covered', () {
      final slantedHole = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 4, longitude: 4),
        Wgs84Vertex(latitude: 5, longitude: 5),
        Wgs84Vertex(latitude: 4, longitude: 6),
        Wgs84Vertex(latitude: 3, longitude: 5),
      ]);
      final donut = withHole(box(0, 0, 10, 10), slantedHole);
      expect(topology.coversMulti([donut], box(0, 0, 10, 10)), isFalse);
    });

    test('concave region with notch is NOT covering', () {
      final lShape = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 10),
        Wgs84Vertex(latitude: 4, longitude: 10),
        Wgs84Vertex(latitude: 4, longitude: 4),
        Wgs84Vertex(latitude: 10, longitude: 4),
        Wgs84Vertex(latitude: 10, longitude: 0),
      ]);
      expect(topology.coversMulti([lShape], box(0, 0, 10, 10)), isFalse);
    });
  });

  group('covers — inner with holes (ChatGPT review #2)', () {
    test('covers(donut, same donut) is true', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      expect(topology.covers(donut, donut), isTrue);
    });

    test('covers(bigDonut, smallDonut with same hole) is true', () {
      final bigDonut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      final smallDonut = withHole(box(1, 1, 8, 8), box(4, 4, 2, 2));
      expect(topology.covers(bigDonut, smallDonut), isTrue);
    });

    test('covers rejects inner surrounding a small hole of outer', () {
      final donut = withHole(box(0, 0, 10, 10), box(4, 4, 2, 2));
      final inner = box(3, 3, 4, 4);
      expect(topology.covers(donut, inner), isFalse);
    });
  });

  group('geometric equality (ChatGPT review #3)', () {
    test('same shape with different starting vertex is equal', () {
      final a = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      final b = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 1),
      ]);
      expect(topology.relate(a, b), Wgs84SpatialRelation.equal);
    });

    test('same shape reversed winding is equal', () {
      final a = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      final b = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 1, longitude: 0),
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 0, longitude: 1),
      ]);
      expect(topology.relate(a, b), Wgs84SpatialRelation.equal);
    });

    test('same shape with extra collinear vertex is equal', () {
      final a = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 0.5),
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      final b = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 0, longitude: 0),
        Wgs84Vertex(latitude: 0, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 1),
        Wgs84Vertex(latitude: 1, longitude: 0),
      ]);
      expect(topology.relate(a, b), Wgs84SpatialRelation.equal);
    });

    test('two adjacent regions together equal one plot -> equal', () {
      final left = box(0, 0, 5, 10);
      final right = box(5, 0, 5, 10);
      final plot = box(0, 0, 10, 10);
      expect(
        topology.relateToMulti(plot, [left, right]),
        Wgs84SpatialRelation.equal,
      );
    });
  });
}
