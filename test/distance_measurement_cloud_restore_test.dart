import 'package:agrico_deepseek/models/distance_measurement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('distance measurement cloud round trip keeps every segment', () {
    final source = DistanceMeasurement(
      id: 'DIST-CURRENT',
      points: const [
        LatLng(16.5500, 104.7500),
        LatLng(16.5505, 104.7505),
        LatLng(16.5510, 104.7510),
      ],
      segmentDistances: const [75.2, 74.8],
      totalDistance: 150,
      measuredAt: DateTime.utc(2026, 8, 11, 3, 30),
    );

    final restored = DistanceMeasurement.fromCloudMap(source.toJson());

    expect(restored.id, source.id);
    expect(restored.points, source.points);
    expect(restored.segmentDistances, source.segmentDistances);
    expect(restored.totalDistance, source.totalDistance);
    expect(restored.measuredAt, source.measuredAt);
  });

  test('legacy A to B document is normalized to the current format', () {
    final restored = DistanceMeasurement.fromCloudMap({
      'id': 'DIST-LEGACY',
      'start': {'lat': '16.55', 'lng': 104.75},
      'end': {'lat': 16.551, 'lng': '104.751'},
      'distanceMeters': 154,
      'measuredAt': DateTime.utc(2026, 8, 10),
      'method': 'manual',
    });

    expect(restored.points, const [
      LatLng(16.55, 104.75),
      LatLng(16.551, 104.751),
    ]);
    expect(restored.segmentDistances, [154]);
    expect(restored.totalDistance, 154);
    expect(restored.measuredAt, DateTime.utc(2026, 8, 10));
  });

  test('missing segment values are recalculated from valid coordinates', () {
    final restored = DistanceMeasurement.fromCloudMap({
      'id': 'DIST-RECALCULATED',
      'points': [
        {'lat': 16.55, 'lng': 104.75},
        {'lat': 16.551, 'lng': 104.751},
      ],
      'measuredAt': '2026-08-11T00:00:00.000Z',
    });

    expect(restored.segmentDistances, hasLength(1));
    expect(restored.segmentDistances.single, greaterThan(0));
    expect(restored.totalDistance, restored.segmentDistances.single);
  });

  test('documents are deduplicated, sorted, and invalid records are skipped', () {
    final restored = parseDistanceMeasurementDocuments([
      {
        'id': 'DIST-DUPLICATE',
        'points': [
          {'lat': 16.55, 'lng': 104.75},
          {'lat': 16.551, 'lng': 104.751},
        ],
        'segmentDistances': [100],
        'totalDistance': 100,
        'measuredAt': '2026-08-10T00:00:00.000Z',
      },
      {
        'id': 'DIST-NEWEST',
        'start': {'lat': 16.55, 'lng': 104.75},
        'end': {'lat': 16.552, 'lng': 104.752},
        'distanceMeters': 250,
        'measuredAt': '2026-08-12T00:00:00.000Z',
      },
      {
        'id': 'DIST-DUPLICATE',
        'start': {'lat': 16.55, 'lng': 104.75},
        'end': {'lat': 16.551, 'lng': 104.751},
        'distanceMeters': 175,
        'measuredAt': '2026-08-11T00:00:00.000Z',
      },
      {
        'id': 'DIST-BROKEN',
        'points': [
          {'lat': 999, 'lng': 104.75},
        ],
        'measuredAt': 'not-a-date',
      },
    ]);

    expect(restored.map((item) => item.id), [
      'DIST-NEWEST',
      'DIST-DUPLICATE',
    ]);
    expect(restored.last.totalDistance, 175);
  });

  test('empty or wholly invalid Cloud payload normalizes to an empty list', () {
    expect(parseDistanceMeasurementDocuments(const []), isEmpty);
    expect(
      parseDistanceMeasurementDocuments([
        {
          'id': ' ',
          'points': const [],
          'measuredAt': '2026-08-11T00:00:00.000Z',
        },
      ]),
      isEmpty,
    );
  });
}
