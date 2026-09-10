import 'package:agrico_deepseek/core/spatial/application/create_spatial_feature_with_initial_revision.dart';
import 'package:agrico_deepseek/core/spatial/application/spatial_feature_creation_transaction.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  SpatialFeature buildFeature({
    String id = 'parcel-1',
    SpatialGeometryType geometryType = SpatialGeometryType.polygon,
  }) {
    return SpatialFeature(
      id: id,
      featureType: SpatialFeatureTypes.landParcel,
      geometryType: geometryType,
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildPolygonRevision({
    String featureId = 'parcel-1',
    int revision = 1,
  }) {
    return SpatialFeatureRevision(
      id: '$featureId-revision-$revision',
      featureId: featureId,
      revision: revision,
      geometryType: SpatialGeometryType.polygon,
      geometry: SpatialPolygon.fromOuterRing(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.5, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
        SpatialCoordinate(latitude: 16.6, longitude: 104.7),
      ]),
      temporalState: SpatialTemporalState.baseline,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildLineRevision() {
    return SpatialFeatureRevision(
      id: 'parcel-1-revision-1',
      featureId: 'parcel-1',
      revision: 1,
      geometryType: SpatialGeometryType.lineString,
      geometry: SpatialLineString.fromCoordinates(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
      ]),
      temporalState: SpatialTemporalState.baseline,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  group('CreateSpatialFeatureWithInitialRevision', () {
    test(
      'creates feature and initial revision through one transaction',
      () async {
        final transaction = _RecordingCreationTransaction();
        final useCase = CreateSpatialFeatureWithInitialRevision(transaction);

        final feature = buildFeature();
        final revision = buildPolygonRevision();

        await useCase.execute(feature: feature, initialRevision: revision);

        expect(transaction.callCount, 1);
        expect(transaction.feature, same(feature));
        expect(transaction.initialRevision, same(revision));
      },
    );

    test(
      'rejects initial revision greater than 1 before transaction',
      () async {
        final transaction = _RecordingCreationTransaction();
        final useCase = CreateSpatialFeatureWithInitialRevision(transaction);

        await expectLater(
          useCase.execute(
            feature: buildFeature(),
            initialRevision: buildPolygonRevision(revision: 2),
          ),
          throwsStateError,
        );

        expect(transaction.callCount, 0);
      },
    );

    test('rejects revision for another feature before transaction', () async {
      final transaction = _RecordingCreationTransaction();
      final useCase = CreateSpatialFeatureWithInitialRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(),
          initialRevision: buildPolygonRevision(featureId: 'parcel-2'),
        ),
        throwsFormatException,
      );

      expect(transaction.callCount, 0);
    });

    test('rejects geometry type mismatch before transaction', () async {
      final transaction = _RecordingCreationTransaction();
      final useCase = CreateSpatialFeatureWithInitialRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(),
          initialRevision: buildLineRevision(),
        ),
        throwsFormatException,
      );

      expect(transaction.callCount, 0);
    });

    test('rejects invalid feature before transaction', () async {
      final transaction = _RecordingCreationTransaction();
      final useCase = CreateSpatialFeatureWithInitialRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(id: ''),
          initialRevision: buildPolygonRevision(featureId: ''),
        ),
        throwsA(anything),
      );

      expect(transaction.callCount, 0);
    });
  });
}

class _RecordingCreationTransaction
    implements SpatialFeatureCreationTransaction {
  int callCount = 0;
  SpatialFeature? feature;
  SpatialFeatureRevision? initialRevision;

  @override
  Future<void> create({
    required SpatialFeature feature,
    required SpatialFeatureRevision initialRevision,
  }) async {
    callCount += 1;
    this.feature = feature;
    this.initialRevision = initialRevision;
  }
}
