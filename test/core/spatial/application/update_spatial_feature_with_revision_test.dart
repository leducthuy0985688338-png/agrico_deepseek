import 'package:agrico_deepseek/core/spatial/application/spatial_feature_revision_update_transaction.dart';
import 'package:agrico_deepseek/core/spatial/application/update_spatial_feature_with_revision.dart';
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
      geometry: geometryType == SpatialGeometryType.polygon
          ? SpatialPolygon.fromOuterRing(const [
              SpatialCoordinate(latitude: 16.5, longitude: 104.7),
              SpatialCoordinate(latitude: 16.5, longitude: 104.8),
              SpatialCoordinate(latitude: 16.6, longitude: 104.8),
              SpatialCoordinate(latitude: 16.6, longitude: 104.7),
            ])
          : null,
      lifecycleStatus: SpatialFeatureLifecycleStatus.existing,
      createdAt: createdAt,
      createdBy: 'user-1',
      updatedAt: createdAt,
      updatedBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildPolygonRevision({
    String featureId = 'parcel-1',
    int revision = 2,
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
      temporalState: SpatialTemporalState.operational,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  SpatialFeatureRevision buildLineRevision() {
    return SpatialFeatureRevision(
      id: 'parcel-1-revision-2',
      featureId: 'parcel-1',
      revision: 2,
      geometryType: SpatialGeometryType.lineString,
      geometry: SpatialLineString.fromCoordinates(const [
        SpatialCoordinate(latitude: 16.5, longitude: 104.7),
        SpatialCoordinate(latitude: 16.6, longitude: 104.8),
      ]),
      temporalState: SpatialTemporalState.operational,
      effectivePeriod: SpatialEffectivePeriod(validFrom: createdAt),
      source: const SpatialSource(type: SpatialSourceType.survey),
      createdAt: createdAt,
      createdBy: 'user-1',
    );
  }

  group('UpdateSpatialFeatureWithRevision', () {
    test('updates feature and revision through one transaction', () async {
      final transaction = _RecordingRevisionUpdateTransaction();
      final useCase = UpdateSpatialFeatureWithRevision(transaction);

      final feature = buildFeature();
      final revision = buildPolygonRevision();

      await useCase.execute(feature: feature, revision: revision);

      expect(transaction.callCount, 1);
      expect(transaction.feature, same(feature));
      expect(transaction.revision, same(revision));
    });

    test('rejects revision 1 before transaction', () async {
      final transaction = _RecordingRevisionUpdateTransaction();
      final useCase = UpdateSpatialFeatureWithRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(),
          revision: buildPolygonRevision(revision: 1),
        ),
        throwsStateError,
      );

      expect(transaction.callCount, 0);
    });

    test('rejects revision for another feature before transaction', () async {
      final transaction = _RecordingRevisionUpdateTransaction();
      final useCase = UpdateSpatialFeatureWithRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(),
          revision: buildPolygonRevision(featureId: 'parcel-2'),
        ),
        throwsFormatException,
      );

      expect(transaction.callCount, 0);
    });

    test('rejects geometry type mismatch before transaction', () async {
      final transaction = _RecordingRevisionUpdateTransaction();
      final useCase = UpdateSpatialFeatureWithRevision(transaction);

      await expectLater(
        useCase.execute(feature: buildFeature(), revision: buildLineRevision()),
        throwsFormatException,
      );

      expect(transaction.callCount, 0);
    });

    test('rejects invalid feature before transaction', () async {
      final transaction = _RecordingRevisionUpdateTransaction();
      final useCase = UpdateSpatialFeatureWithRevision(transaction);

      await expectLater(
        useCase.execute(
          feature: buildFeature(id: ''),
          revision: buildPolygonRevision(featureId: ''),
        ),
        throwsA(anything),
      );

      expect(transaction.callCount, 0);
    });
  });
}

class _RecordingRevisionUpdateTransaction
    implements SpatialFeatureRevisionUpdateTransaction {
  int callCount = 0;
  SpatialFeature? feature;
  SpatialFeatureRevision? revision;

  @override
  Future<void> update({
    required SpatialFeature feature,
    required SpatialFeatureRevision revision,
  }) async {
    callCount += 1;
    this.feature = feature;
    this.revision = revision;
  }
}
