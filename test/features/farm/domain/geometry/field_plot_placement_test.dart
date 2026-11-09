import 'package:agrico_deepseek/features/farm/domain/geometry/field_plot_placement.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

Wgs84Polygon polygon(List<(double, double)> points) =>
    Wgs84Polygon.fromVertices(
      points.map(
        (p) => Wgs84Vertex(
          latitude: 16 + p.$2 * .001,
          longitude: 106 + p.$1 * .001,
        ),
      ),
    );
Wgs84Polygon box(double x, double y, double w, double h) =>
    polygon([(x, y), (x + w, y), (x + w, y + h), (x, y + h)]);

void main() {
  const placement = FieldPlotPlacement();
  final block = box(0, 0, 10, 10);
  test(
    'partial coverage leaves room for roads irrigation and unallocated land',
    () {
      placement.validate(
        block: block,
        plot: box(1, 1, 2, 2),
        existingPlots: [box(6, 6, 2, 2)],
      );
    },
  );
  test('shared boundaries and vertices are allowed', () {
    placement.validate(
      block: block,
      plot: box(0, 0, 5, 5),
      existingPlots: [box(5, 0, 5, 5)],
    );
    placement.validate(
      block: block,
      plot: box(0, 0, 5, 5),
      existingPlots: [box(5, 5, 5, 5)],
    );
  });
  test('crossing nested and identical plots are rejected', () {
    for (final other in [box(2, 2, 5, 5), box(1, 1, 1, 1), box(0, 0, 5, 5)]) {
      expect(
        () => placement.validate(
          block: block,
          plot: box(0, 0, 5, 5),
          existingPlots: [other],
        ),
        throwsFormatException,
      );
    }
    expect(
      () => placement.validate(
        block: block,
        plot: box(2, 2, 5, 5),
        existingPlots: [box(0, 0, 5, 5)],
      ),
      throwsFormatException,
    );
  });
  test(
    'outside edge is rejected even when all vertices are inside a concave block',
    () {
      final concave = polygon([
        (0, 0),
        (10, 0),
        (10, 10),
        (7, 10),
        (7, 3),
        (3, 3),
        (3, 10),
        (0, 10),
      ]);
      expect(
        () => placement.validate(
          block: concave,
          plot: polygon([(1, 2), (9, 2), (9, 8), (1, 8)]),
        ),
        throwsFormatException,
      );
      expect(
        () => placement.validate(block: block, plot: box(9, 9, 2, 2)),
        throwsFormatException,
      );
    },
  );
  test(
    'parent exclusions cannot be covered and plot exclusions remain usable',
    () {
      final outer = box(0, 0, 10, 10);
      final hole = box(4, 4, 2, 2);
      final excludedBlock = Wgs84Polygon.fromVertices(
        outer.vertices,
        holes: [hole.vertices],
      );
      expect(
        () => placement.validate(block: excludedBlock, plot: box(3, 3, 4, 4)),
        throwsFormatException,
      );
      final donut = Wgs84Polygon.fromVertices(
        box(2, 2, 6, 6).vertices,
        holes: [hole.vertices],
      );
      placement.validate(
        block: block,
        plot: box(4.2, 4.2, 1, 1),
        existingPlots: [donut],
      );
    },
  );
}
