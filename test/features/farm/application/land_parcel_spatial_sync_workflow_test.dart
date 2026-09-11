import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  final createdAt = DateTime.utc(2026, 9, 11, 8);

  LandParcel createParcel({String id = 'parcel-1', String code = 'P-001'}) {
    return LandParcel.create(
      id: id,
      farmId: 'farm-1',
      parcelCode: code,
      name: 'Parcel $id',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
      occurredAt: createdAt,
      horizontalAccuracyM: 1.5,
    );
  }

  late Database database;
  late SqliteLandParcelRepository parcels;
  late SpatialPersistenceComposition spatial;
  late LandParcelSpatialSyncWorkflow workflow;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await SqliteLandParcelRepository.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    spatial = SpatialPersistenceComposition(database);

    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
    );
  });

  tearDown(() => database.close());

  test('creates LandParcel and projected polygon atomically', () async {
    final parcel = createParcel();

    await workflow.create(
      parcel: parcel,
      spatialFeatureId: 'spatial-parcel-1',
      spatialRevisionId: 'spatial-parcel-1-revision-1',
      temporalState: SpatialTemporalState.operational,
    );

    final storedParcel = await parcels.getById(
      farmId: parcel.farmId,
      id: parcel.id,
    );
    final feature = await spatial.featureRepository.findById(
      'spatial-parcel-1',
    );
    final revisions = await spatial.revisionRepository.findByFeatureId(
      'spatial-parcel-1',
    );

    expect(storedParcel, isNotNull);
    expect(feature, isNotNull);
    expect(feature!.id, isNot(parcel.id));
    expect(feature.geometry, isA<SpatialPolygon>());
    expect(revisions, hasLength(1));
    expect(revisions.single.revision, 1);
    expect(revisions.single.geometry, isA<SpatialPolygon>());

    final polygon = feature.geometry! as SpatialPolygon;
    expect(polygon.outerRing, hasLength(5));
    expect(polygon.outerRing.first.latitude, 16.5000);
    expect(polygon.outerRing.first.longitude, 104.7000);
    expect(polygon.outerRing.last, polygon.outerRing.first);
  });

  test(
    'Spatial create failure rolls back LandParcel and boundary history',
    () async {
      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        spatialFeatureId: 'spatial-existing',
        spatialRevisionId: 'spatial-existing-revision-1',
        temporalState: SpatialTemporalState.operational,
      );

      final conflictingParcel = createParcel(id: 'parcel-2', code: 'P-002');

      await expectLater(
        () => workflow.create(
          parcel: conflictingParcel,
          spatialFeatureId: 'spatial-existing',
          spatialRevisionId: 'another-revision-1',
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(anything),
      );

      expect(
        await parcels.getById(
          farmId: conflictingParcel.farmId,
          id: conflictingParcel.id,
        ),
        isNull,
      );

      final boundaryRows = await database.query(
        SqliteLandParcelRepository.boundaryVersionTable,
        where: 'parcel_id = ?',
        whereArgs: [conflictingParcel.id],
      );
      expect(boundaryRows, isEmpty);
    },
  );

  test('LandParcel create failure rolls back projected Spatial data', () async {
    final existing = createParcel(id: 'existing', code: 'P-001');
    await parcels.create(existing);

    final conflictingParcel = createParcel(id: 'parcel-2', code: 'P-001');

    await expectLater(
      () => workflow.create(
        parcel: conflictingParcel,
        spatialFeatureId: 'spatial-parcel-2',
        spatialRevisionId: 'spatial-parcel-2-revision-1',
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(anything),
    );

    expect(
      await spatial.featureRepository.findById('spatial-parcel-2'),
      isNull,
    );
    expect(
      await spatial.revisionRepository.findByFeatureId('spatial-parcel-2'),
      isEmpty,
    );
  });

  test(
    'updates LandParcel and appends next Spatial revision atomically',
    () async {
      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-1',
        temporalState: SpatialTemporalState.operational,
      );

      final updated = parcel.updateMetadata(
        name: 'Updated parcel',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await workflow.update(
        parcel: updated,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-2',
        temporalState: SpatialTemporalState.operational,
      );

      final storedParcel = await parcels.getById(
        farmId: updated.farmId,
        id: updated.id,
      );
      final feature = await spatial.featureRepository.findById(
        'spatial-parcel-1',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-parcel-1',
      );

      expect(storedParcel!.name, 'Updated parcel');
      expect(feature!.name, 'Updated parcel');
      expect(revisions.map((revision) => revision.revision), [1, 2]);
    },
  );

  test(
    'update derives the next Spatial revision from persisted state',
    () async {
      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-1',
        temporalState: SpatialTemporalState.operational,
      );

      final updated = parcel.updateMetadata(
        name: 'Revision two',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await workflow.update(
        parcel: updated,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-2',
        temporalState: SpatialTemporalState.operational,
      );

      final updatedAgain = updated.updateMetadata(
        name: 'Revision three',
        actorMembershipId: 'member-3',
        occurredAt: DateTime.utc(2026, 9, 11, 10),
      );

      await workflow.update(
        parcel: updatedAgain,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-3',
        temporalState: SpatialTemporalState.operational,
      );

      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-parcel-1',
      );

      expect(revisions.map((revision) => revision.revision), [1, 2, 3]);
    },
  );

  test(
    'update fails when SpatialFeature does not exist and rolls back parcel',
    () async {
      final parcel = createParcel();
      await parcels.create(parcel);

      final updated = parcel.updateMetadata(
        name: 'Must roll back',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await expectLater(
        () => workflow.update(
          parcel: updated,
          spatialFeatureId: 'missing-spatial-feature',
          spatialRevisionId: 'missing-revision-2',
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(anything),
      );

      final stored = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );

      expect(stored!.name, parcel.name);
      expect(
        await spatial.featureRepository.findById('missing-spatial-feature'),
        isNull,
      );
    },
  );

  test('Spatial update failure rolls back LandParcel update', () async {
    final parcel = createParcel();

    await workflow.create(
      parcel: parcel,
      spatialFeatureId: 'spatial-parcel-1',
      spatialRevisionId: 'shared-revision-id',
      temporalState: SpatialTemporalState.operational,
    );

    final updated = parcel.updateMetadata(
      name: 'Must roll back',
      actorMembershipId: 'member-2',
      occurredAt: DateTime.utc(2026, 9, 11, 9),
    );

    await expectLater(
      () => workflow.update(
        parcel: updated,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'shared-revision-id',
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(anything),
    );

    final storedParcel = await parcels.getById(
      farmId: parcel.farmId,
      id: parcel.id,
    );
    final feature = await spatial.featureRepository.findById(
      'spatial-parcel-1',
    );
    final revisions = await spatial.revisionRepository.findByFeatureId(
      'spatial-parcel-1',
    );

    expect(storedParcel!.name, parcel.name);
    expect(feature!.name, parcel.name);
    expect(revisions, hasLength(1));
    expect(revisions.single.revision, 1);
  });

  test(
    'LandParcel update failure leaves Spatial feature and revisions unchanged',
    () async {
      final parcel = createParcel(id: 'parcel-1', code: 'P-001');

      await workflow.create(
        parcel: parcel,
        spatialFeatureId: 'spatial-parcel-1',
        spatialRevisionId: 'spatial-parcel-1-revision-1',
        temporalState: SpatialTemporalState.operational,
      );

      final otherParcel = createParcel(id: 'parcel-2', code: 'P-002');
      await parcels.create(otherParcel);

      final conflicting = parcel.updateMetadata(
        parcelCode: 'P-002',
        name: 'Must not persist',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await expectLater(
        () => workflow.update(
          parcel: conflicting,
          spatialFeatureId: 'spatial-parcel-1',
          spatialRevisionId: 'spatial-parcel-1-revision-2',
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(anything),
      );

      final storedParcel = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final feature = await spatial.featureRepository.findById(
        'spatial-parcel-1',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-parcel-1',
      );

      expect(storedParcel!.parcelCode, 'P-001');
      expect(storedParcel.name, parcel.name);
      expect(feature!.code, 'P-001');
      expect(feature.name, parcel.name);
      expect(revisions, hasLength(1));
      expect(revisions.single.revision, 1);
    },
  );
}
