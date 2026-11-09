import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/features/natural/domain/entities/natural_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NaturalFeature', () {
    final createdAt = DateTime.utc(2026, 9, 10);

    test('maps river and stream to linear Spatial Core features', () {
      final river = NaturalFeature(
        id: 'river-1',
        spatialFeatureId: 'spatial-river-1',
        featureType: NaturalFeatureType.river,
        name: 'River A',
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final stream = NaturalFeature(
        id: 'stream-1',
        spatialFeatureId: 'spatial-stream-1',
        featureType: NaturalFeatureType.stream,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      river.validate();
      stream.validate();

      expect(river.spatialFeatureType, SpatialFeatureTypes.river);
      expect(river.defaultGeometryType, SpatialGeometryType.lineString);

      expect(stream.spatialFeatureType, SpatialFeatureTypes.stream);
      expect(stream.defaultGeometryType, SpatialGeometryType.lineString);
    });

    test(
      'keeps stable identity across pre-construction and as-built surveys',
      () {
        final river = NaturalFeature(
          id: 'river-history-1',
          spatialFeatureId: 'spatial-river-history-1',
          featureType: NaturalFeatureType.river,
          createdAt: createdAt,
          createdBy: 'user-1',
        );

        final baseline = SpatialFeatureRevision(
          id: 'river-revision-1',
          featureId: river.spatialFeatureId,
          revision: 1,
          geometryType: SpatialGeometryType.lineString,
          temporalState: SpatialTemporalState.preConstruction,
          effectivePeriod: SpatialEffectivePeriod(
            validFrom: DateTime.utc(2025, 1, 1),
            validTo: DateTime.utc(2026, 1, 1),
          ),
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'survey-team',
          ),
          createdAt: createdAt,
          createdBy: 'user-1',
        );

        final asBuilt = SpatialFeatureRevision(
          id: 'river-revision-2',
          featureId: river.spatialFeatureId,
          revision: 2,
          geometryType: SpatialGeometryType.lineString,
          temporalState: SpatialTemporalState.asBuilt,
          effectivePeriod: SpatialEffectivePeriod(
            validFrom: DateTime.utc(2026, 1, 1),
          ),
          source: const SpatialSource(
            type: SpatialSourceType.survey,
            surveyedBy: 'survey-team',
          ),
          createdAt: createdAt,
          createdBy: 'user-1',
        );

        river.validate();
        baseline.validate();
        asBuilt.validate();

        expect(baseline.featureId, river.spatialFeatureId);
        expect(asBuilt.featureId, river.spatialFeatureId);
        expect(baseline.revision, 1);
        expect(asBuilt.revision, 2);
        expect(baseline.temporalState, SpatialTemporalState.preConstruction);
        expect(asBuilt.temporalState, SpatialTemporalState.asBuilt);
      },
    );
    test('maps spring to point and water body to polygon', () {
      final spring = NaturalFeature(
        id: 'spring-1',
        spatialFeatureId: 'spatial-spring-1',
        featureType: NaturalFeatureType.spring,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      final waterBody = NaturalFeature(
        id: 'water-body-1',
        spatialFeatureId: 'spatial-water-body-1',
        featureType: NaturalFeatureType.waterBody,
        createdAt: createdAt,
        createdBy: 'user-1',
      );

      expect(spring.spatialFeatureType, SpatialFeatureTypes.spring);
      expect(spring.defaultGeometryType, SpatialGeometryType.point);

      expect(waterBody.spatialFeatureType, SpatialFeatureTypes.waterBody);
      expect(waterBody.defaultGeometryType, SpatialGeometryType.polygon);
    });
  });
}
