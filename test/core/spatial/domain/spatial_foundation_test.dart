import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/relationships/spatial_relationship.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10);

  group('SpatialSource', () {
    test('accepts valid survey provenance', () {
      final source = SpatialSource(
        type: SpatialSourceType.gps,
        surveyedAt: createdAt,
        surveyedBy: 'membership-1',
        horizontalAccuracyM: 0.5,
        sourceReference: 'survey-001',
      );

      expect(source.validate, returnsNormally);
    });

    test('rejects negative horizontal accuracy', () {
      const source = SpatialSource(
        type: SpatialSourceType.gps,
        horizontalAccuracyM: -1,
      );

      expect(source.validate, throwsFormatException);
    });
  });

  group('SpatialEffectivePeriod', () {
    test('accepts an open-ended period', () {
      final period = SpatialEffectivePeriod(validFrom: createdAt);

      expect(period.validate, returnsNormally);
      expect(period.isOpenEnded, isTrue);
      expect(period.contains(createdAt), isTrue);
    });

    test('rejects an end before the start', () {
      final period = SpatialEffectivePeriod(
        validFrom: createdAt,
        validTo: createdAt.subtract(const Duration(days: 1)),
      );

      expect(period.validate, throwsFormatException);
    });
  });

  group('SpatialFeature', () {
    test('accepts stable extensible feature identity', () {
      final feature = SpatialFeature(
        id: 'road-1',
        featureType: SpatialFeatureTypes.road,
        geometryType: SpatialGeometryType.lineString,
        lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
        createdAt: createdAt,
        createdBy: 'membership-1',
        updatedAt: createdAt,
        updatedBy: 'membership-1',
      );

      expect(feature.validate, returnsNormally);
    });

    test('rejects an update timestamp before creation', () {
      final feature = SpatialFeature(
        id: 'road-1',
        featureType: SpatialFeatureTypes.road,
        geometryType: SpatialGeometryType.lineString,
        lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
        createdAt: createdAt,
        createdBy: 'membership-1',
        updatedAt: createdAt.subtract(const Duration(seconds: 1)),
        updatedBy: 'membership-1',
      );

      expect(feature.validate, throwsFormatException);
    });
  });

  group('SpatialFeatureRevision', () {
    test('accepts baseline revision with provenance', () {
      final revision = SpatialFeatureRevision(
        id: 'road-1-revision-1',
        featureId: 'road-1',
        revision: 1,
        geometryType: SpatialGeometryType.lineString,
        temporalState: SpatialTemporalState.baseline,
        effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
        source: SpatialSource(
          type: SpatialSourceType.survey,
          surveyedAt: createdAt,
          surveyedBy: 'membership-1',
        ),
        createdAt: createdAt,
        createdBy: 'membership-1',
      );

      expect(revision.validate, returnsNormally);
    });

    test('rejects revision zero', () {
      final revision = SpatialFeatureRevision(
        id: 'road-1-revision-0',
        featureId: 'road-1',
        revision: 0,
        geometryType: SpatialGeometryType.lineString,
        temporalState: SpatialTemporalState.baseline,
        effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
        source: const SpatialSource(type: SpatialSourceType.manual),
        createdAt: createdAt,
        createdBy: 'membership-1',
      );

      expect(revision.validate, throwsFormatException);
    });
  });

  group('SpatialRelationship', () {
    test('accepts relationship between different features', () {
      final relationship = SpatialRelationship(
        id: 'relationship-1',
        fromFeatureId: 'reservoir-1',
        toFeatureId: 'parcel-1',
        relationshipType: SpatialRelationshipTypes.supplies,
        effectiveFrom: createdAt,
        createdAt: createdAt,
        createdBy: 'membership-1',
      );

      expect(relationship.validate, returnsNormally);
      expect(relationship.isCurrent, isTrue);
    });

    test('rejects self relationship', () {
      final relationship = SpatialRelationship(
        id: 'relationship-1',
        fromFeatureId: 'road-1',
        toFeatureId: 'road-1',
        relationshipType: SpatialRelationshipTypes.connectedTo,
        effectiveFrom: createdAt,
        createdAt: createdAt,
        createdBy: 'membership-1',
      );

      expect(relationship.validate, throwsFormatException);
    });
  });

  group('SpatialGeometryType', () {
    test('supports multipart cultivation geometry', () {
      const type = SpatialGeometryType.multiPolygon;

      expect(type.isAreal, isTrue);
      expect(type.isMultipart, isTrue);
      expect(type.isLinear, isFalse);
    });
  });
}
