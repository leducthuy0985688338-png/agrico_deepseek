import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';
import '../../../core/spatial/support/scripted_spatial_identity_generator.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';

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
  late SqliteLandParcelSpatialLinkRepository links;
  late SpatialPersistenceComposition spatial;
  late LandParcelSpatialSyncWorkflow workflow;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await SqliteLandParcelRepository.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);
    await SqliteLandParcelSpatialLinkRepository.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    links = SqliteLandParcelSpatialLinkRepository(database);
    spatial = SpatialPersistenceComposition(database);

    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: SequentialSpatialIdentityGenerator(),
    );
  });

  tearDown(() => database.close());

  test('creates LandParcel and projected polygon atomically', () async {
    final parcel = createParcel();

    await workflow.create(
      parcel: parcel,
      temporalState: SpatialTemporalState.operational,
    );

    final storedParcel = await parcels.getById(
      farmId: parcel.farmId,
      id: parcel.id,
    );
    final feature = await spatial.featureRepository.findById(
      'spatial-feature-2',
    );
    final revisions = await spatial.revisionRepository.findByFeatureId(
      'spatial-feature-2',
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
      workflow = LandParcelSpatialSyncWorkflow(
        transaction: LandParcelSpatialTransaction(database),
        projection: const DefaultLandParcelSpatialProjection(),
        identityGenerator: ScriptedSpatialIdentityGenerator([
          const ScriptedSpatialIdentity(
            prefix: 'spatial-link',
            id: 'link-first',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-feature',
            id: 'feature-shared',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-revision',
            id: 'revision-first',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-link',
            id: 'link-second',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-feature',
            id: 'feature-shared',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-revision',
            id: 'revision-second',
          ),
        ]),
      );

      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final conflictingParcel = createParcel(id: 'parcel-2', code: 'P-002');

      await expectLater(
        () => workflow.create(
          parcel: conflictingParcel,
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
      expect(
        await spatial.featureRepository.findById('feature-shared'),
        isNotNull,
      );
    },
  );

  test('LandParcel create failure rolls back projected Spatial data', () async {
    final existing = createParcel(id: 'existing', code: 'P-001');
    await parcels.create(existing);

    final conflictingParcel = createParcel(id: 'parcel-2', code: 'P-001');

    await expectLater(
      () => workflow.create(
        parcel: conflictingParcel,
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
        temporalState: SpatialTemporalState.operational,
      );

      final updated = parcel.updateMetadata(
        name: 'Updated parcel',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await workflow.update(
        parcel: updated,
        temporalState: SpatialTemporalState.operational,
      );

      final storedParcel = await parcels.getById(
        farmId: updated.farmId,
        id: updated.id,
      );
      final feature = await spatial.featureRepository.findById(
        'spatial-feature-2',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-feature-2',
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
        temporalState: SpatialTemporalState.operational,
      );

      final updated = parcel.updateMetadata(
        name: 'Revision two',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await workflow.update(
        parcel: updated,
        temporalState: SpatialTemporalState.operational,
      );

      final updatedAgain = updated.updateMetadata(
        name: 'Revision three',
        actorMembershipId: 'member-3',
        occurredAt: DateTime.utc(2026, 9, 11, 10),
      );

      await workflow.update(
        parcel: updatedAgain,
        temporalState: SpatialTemporalState.operational,
      );

      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-feature-2',
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
    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: ScriptedSpatialIdentityGenerator([
        const ScriptedSpatialIdentity(prefix: 'spatial-link', id: 'link-1'),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-feature',
          id: 'feature-1',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-revision',
          id: 'revision-shared',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-revision',
          id: 'revision-shared',
        ),
      ]),
    );

    final parcel = createParcel();

    await workflow.create(
      parcel: parcel,
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
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(anything),
    );

    final storedParcel = await parcels.getById(
      farmId: parcel.farmId,
      id: parcel.id,
    );
    final feature = await spatial.featureRepository.findById('feature-1');
    final revisions = await spatial.revisionRepository.findByFeatureId(
      'feature-1',
    );

    expect(storedParcel!.name, parcel.name);
    expect(feature!.name, parcel.name);
    expect(revisions, hasLength(1));
    expect(revisions.single.id, 'revision-shared');
    expect(revisions.single.revision, 1);
  });

  test(
    'create persists stable LandParcel SpatialFeature link atomically',
    () async {
      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final storedLink = await links.findByLandParcelId(parcel.id);

      expect(storedLink, isNotNull);
      expect(storedLink!.id, 'spatial-link-1');
      expect(storedLink.landParcelId, parcel.id);
      expect(storedLink.spatialFeatureId, 'spatial-feature-2');
    },
  );

  test('failed create leaves no persistent Spatial link', () async {
    final existing = createParcel(id: 'existing', code: 'P-001');
    await parcels.create(existing);

    final conflictingParcel = createParcel(id: 'parcel-2', code: 'P-001');

    await expectLater(
      () => workflow.create(
        parcel: conflictingParcel,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(anything),
    );

    expect(await links.findByLandParcelId(conflictingParcel.id), isNull);
    expect(await links.findBySpatialFeatureId('spatial-parcel-2'), isNull);
  });

  test('link insertion failure rolls back parcel and Spatial data', () async {
    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: ScriptedSpatialIdentityGenerator([
        const ScriptedSpatialIdentity(
          prefix: 'spatial-link',
          id: 'link-shared',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-feature',
          id: 'feature-1',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-revision',
          id: 'revision-1',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-link',
          id: 'link-shared',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-feature',
          id: 'feature-2',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-revision',
          id: 'revision-2',
        ),
      ]),
    );

    final firstParcel = createParcel(id: 'parcel-1', code: 'P-001');

    await workflow.create(
      parcel: firstParcel,
      temporalState: SpatialTemporalState.operational,
    );

    final secondParcel = createParcel(id: 'parcel-2', code: 'P-002');

    await expectLater(
      () => workflow.create(
        parcel: secondParcel,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(anything),
    );

    final storedSecondParcel = await parcels.getById(
      farmId: secondParcel.farmId,
      id: secondParcel.id,
    );
    final secondFeature = await spatial.featureRepository.findById('feature-2');
    final secondRevisions = await spatial.revisionRepository.findByFeatureId(
      'feature-2',
    );
    final firstLink = await links.findByLandParcelId(firstParcel.id);
    final secondLink = await links.findByLandParcelId(secondParcel.id);

    expect(storedSecondParcel, isNull);
    expect(secondFeature, isNull);
    expect(secondRevisions, isEmpty);
    expect(firstLink, isNotNull);
    expect(firstLink!.id, 'link-shared');
    expect(firstLink.spatialFeatureId, 'feature-1');
    expect(secondLink, isNull);
    expect(
      (await links.findBySpatialFeatureId('feature-1'))!.id,
      'link-shared',
    );
    expect(await links.findBySpatialFeatureId('feature-2'), isNull);
  });

  test('update without persistent Spatial link is rejected', () async {
    final parcel = createParcel();
    await parcels.create(parcel);

    final updated = parcel.updateMetadata(
      name: 'Must not persist',
      actorMembershipId: 'member-2',
      occurredAt: DateTime.utc(2026, 9, 11, 9),
    );

    await expectLater(
      () => workflow.update(
        parcel: updated,
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no persisted SpatialFeature link'),
        ),
      ),
    );

    final stored = await parcels.getById(farmId: parcel.farmId, id: parcel.id);

    expect(stored!.name, parcel.name);
  });

  test(
    'LandParcel update failure leaves Spatial feature and revisions unchanged',
    () async {
      final parcel = createParcel(id: 'parcel-1', code: 'P-001');

      await workflow.create(
        parcel: parcel,
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
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(anything),
      );

      final storedParcel = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final feature = await spatial.featureRepository.findById(
        'spatial-feature-2',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-feature-2',
      );

      expect(storedParcel!.parcelCode, 'P-001');
      expect(storedParcel.name, parcel.name);
      expect(feature!.code, 'P-001');
      expect(feature.name, parcel.name);
      expect(revisions, hasLength(1));
      expect(revisions.single.revision, 1);
    },
  );

  test(
    'update rejects a persisted link to a non-LandParcel SpatialFeature',
    () async {
      final parcel = createParcel();
      await parcels.create(parcel);

      final roadFeature = SpatialFeature(
        id: 'spatial-road-1',
        featureType: SpatialFeatureTypes.road,
        geometryType: SpatialGeometryType.polygon,
        lifecycleStatus: SpatialFeatureLifecycleStatus.active,
        createdAt: createdAt,
        createdBy: 'member-1',
        updatedAt: createdAt,
        updatedBy: 'member-1',
      );

      await spatial.featureRepository.create(roadFeature);

      await links.create(
        LandParcelSpatialLink(
          id: 'link-parcel-to-road',
          landParcelId: parcel.id,
          spatialFeatureId: roadFeature.id,
          createdAt: createdAt,
          createdBy: 'member-1',
        ),
      );

      final updated = parcel.updateMetadata(
        name: 'Must not persist',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 11, 9),
      );

      await expectLater(
        () => workflow.update(
          parcel: updated,
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('must be a LandParcel feature'),
          ),
        ),
      );

      final storedParcel = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final storedRoad = await spatial.featureRepository.findById(
        roadFeature.id,
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        roadFeature.id,
      );

      expect(storedParcel, isNotNull);
      expect(storedParcel!.name, parcel.name);
      expect(storedRoad, isNotNull);
      expect(storedRoad!.featureType, SpatialFeatureTypes.road);
      expect(storedRoad.updatedAt, createdAt);
      expect(revisions, isEmpty);
    },
  );

  test(
    'bootstrapExisting adopts a persisted legacy LandParcel without mutating it',
    () async {
      final parcel = createParcel();
      await parcels.create(parcel);

      await workflow.bootstrapExisting(
        farmId: parcel.farmId,
        landParcelId: parcel.id,
        temporalState: SpatialTemporalState.operational,
      );

      final storedParcel = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final link = await links.findByLandParcelId(parcel.id);
      final feature = await spatial.featureRepository.findById(
        'spatial-feature-2',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-feature-2',
      );

      expect(storedParcel, isNotNull);
      expect(storedParcel!.id, parcel.id);
      expect(storedParcel.parcelCode, parcel.parcelCode);
      expect(storedParcel.name, parcel.name);
      expect(storedParcel.updatedAt, parcel.updatedAt);
      expect(storedParcel.updatedBy, parcel.updatedBy);
      expect(
        storedParcel.boundaryHistory.length,
        parcel.boundaryHistory.length,
      );

      expect(link, isNotNull);
      expect(link!.id, 'spatial-link-1');
      expect(link.landParcelId, parcel.id);
      expect(link.spatialFeatureId, 'spatial-feature-2');

      expect(feature, isNotNull);
      expect(feature!.id, 'spatial-feature-2');
      expect(feature.featureType, SpatialFeatureTypes.landParcel);
      expect(feature.code, parcel.parcelCode);
      expect(feature.name, parcel.name);

      expect(revisions, hasLength(1));
      expect(revisions.single.id, 'spatial-revision-3');
      expect(revisions.single.revision, 1);
      expect(revisions.single.featureId, 'spatial-feature-2');
    },
  );

  test('bootstrapExisting rejects a missing LandParcel', () async {
    await expectLater(
      () => workflow.bootstrapExisting(
        farmId: 'farm-1',
        landParcelId: 'missing-parcel',
        temporalState: SpatialTemporalState.operational,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('does not exist'),
        ),
      ),
    );

    expect(await links.findByLandParcelId('missing-parcel'), isNull);
    expect(await spatial.featureRepository.findById('missing-feature'), isNull);
    expect(
      await spatial.revisionRepository.findByFeatureId('missing-feature'),
      isEmpty,
    );
  });

  test(
    'bootstrapExisting rejects a LandParcel that already has a link',
    () async {
      final generator = SequentialSpatialIdentityGenerator();

      workflow = LandParcelSpatialSyncWorkflow(
        transaction: LandParcelSpatialTransaction(database),
        projection: const DefaultLandParcelSpatialProjection(),
        identityGenerator: generator,
      );

      final parcel = createParcel();
      await parcels.create(parcel);

      await workflow.bootstrapExisting(
        farmId: parcel.farmId,
        landParcelId: parcel.id,
        temporalState: SpatialTemporalState.operational,
      );

      await expectLater(
        () => workflow.bootstrapExisting(
          farmId: parcel.farmId,
          landParcelId: parcel.id,
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already has a persisted SpatialFeature link'),
          ),
        ),
      );

      final link = await links.findByLandParcelId(parcel.id);

      expect(link, isNotNull);
      expect(link!.id, 'spatial-link-1');
      expect(link.spatialFeatureId, 'spatial-feature-2');

      // If the rejected bootstrap consumed identities, this would not be 4.
      expect(generator.newId('probe'), 'probe-4');
    },
  );

  test(
    'bootstrapExisting link failure rolls back Spatial feature and revision',
    () async {
      workflow = LandParcelSpatialSyncWorkflow(
        transaction: LandParcelSpatialTransaction(database),
        projection: const DefaultLandParcelSpatialProjection(),
        identityGenerator: ScriptedSpatialIdentityGenerator([
          const ScriptedSpatialIdentity(
            prefix: 'spatial-link',
            id: 'shared-bootstrap-link',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-feature',
            id: 'bootstrap-feature-1',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-revision',
            id: 'bootstrap-revision-1',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-link',
            id: 'shared-bootstrap-link',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-feature',
            id: 'bootstrap-feature-2',
          ),
          const ScriptedSpatialIdentity(
            prefix: 'spatial-revision',
            id: 'bootstrap-revision-2',
          ),
        ]),
      );

      final firstParcel = createParcel(id: 'parcel-1', code: 'P-001');
      final legacyParcel = createParcel(id: 'parcel-2', code: 'P-002');

      await parcels.create(firstParcel);
      await parcels.create(legacyParcel);

      await workflow.bootstrapExisting(
        farmId: firstParcel.farmId,
        landParcelId: firstParcel.id,
        temporalState: SpatialTemporalState.operational,
      );

      await expectLater(
        () => workflow.bootstrapExisting(
          farmId: legacyParcel.farmId,
          landParcelId: legacyParcel.id,
          temporalState: SpatialTemporalState.operational,
        ),
        throwsA(anything),
      );

      final storedLegacy = await parcels.getById(
        farmId: legacyParcel.farmId,
        id: legacyParcel.id,
      );

      expect(storedLegacy, isNotNull);
      expect(storedLegacy!.parcelCode, legacyParcel.parcelCode);
      expect(storedLegacy.name, legacyParcel.name);

      expect(await links.findByLandParcelId(legacyParcel.id), isNull);
      expect(
        await spatial.featureRepository.findById('bootstrap-feature-2'),
        isNull,
      );
      expect(
        await spatial.revisionRepository.findByFeatureId('bootstrap-feature-2'),
        isEmpty,
      );

      final firstLink = await links.findByLandParcelId(firstParcel.id);
      expect(firstLink, isNotNull);
      expect(firstLink!.id, 'shared-bootstrap-link');
      expect(
        await spatial.featureRepository.findById('bootstrap-feature-1'),
        isNotNull,
      );
    },
  );

  test(
    'createScoped joins caller transaction and rolls back atomically',
    () async {
      final parcel = createParcel(
        id: 'scoped-create-rollback',
        code: 'SCOPED-CREATE',
      );

      await expectLater(
        () => LandParcelSpatialTransaction(database).run<void>((
          scopedParcels,
          scopedLinks,
          scopedSpatial,
        ) async {
          await workflow.createScoped(
            parcels: scopedParcels,
            links: scopedLinks,
            spatial: scopedSpatial,
            parcel: parcel,
            temporalState: SpatialTemporalState.operational,
            spatialLinkId: 'scoped-link-create',
            spatialFeatureId: 'scoped-feature-create',
            spatialRevisionId: 'scoped-revision-create',
          );

          throw StateError('force outer rollback');
        }),
        throwsA(isA<StateError>()),
      );

      expect(
        await parcels.getById(farmId: parcel.farmId, id: parcel.id),
        isNull,
      );
      expect(await links.findByLandParcelId(parcel.id), isNull);
      expect(
        await spatial.featureRepository.findById('scoped-feature-create'),
        isNull,
      );
      expect(
        await spatial.revisionRepository.findByFeatureId(
          'scoped-feature-create',
        ),
        isEmpty,
      );
    },
  );

  test(
    'updateScoped joins caller transaction and rolls back atomically',
    () async {
      final parcel = createParcel(
        id: 'scoped-update-rollback',
        code: 'SCOPED-UPDATE',
      );

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final linkBefore = await links.findByLandParcelId(parcel.id);
      expect(linkBefore, isNotNull);

      final featureId = linkBefore!.spatialFeatureId;
      final featureBefore = await spatial.featureRepository.findById(featureId);
      final revisionsBefore = await spatial.revisionRepository.findByFeatureId(
        featureId,
      );

      expect(featureBefore, isNotNull);
      expect(revisionsBefore, hasLength(1));

      final updated = parcel.updateMetadata(
        name: 'Scoped update must roll back',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 12, 8),
      );

      await expectLater(
        () => LandParcelSpatialTransaction(database).run<void>((
          scopedParcels,
          scopedLinks,
          scopedSpatial,
        ) async {
          await workflow.updateScoped(
            parcels: scopedParcels,
            links: scopedLinks,
            spatial: scopedSpatial,
            parcel: updated,
            temporalState: SpatialTemporalState.operational,
          );

          throw StateError('force outer rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final storedAfter = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final featureAfter = await spatial.featureRepository.findById(featureId);
      final revisionsAfter = await spatial.revisionRepository.findByFeatureId(
        featureId,
      );

      expect(storedAfter, isNotNull);
      expect(storedAfter!.name, parcel.name);
      expect(featureAfter, isNotNull);
      expect(featureAfter!.name, featureBefore!.name);
      expect(featureAfter.updatedAt, featureBefore.updatedAt);
      expect(revisionsAfter, hasLength(1));
      expect(revisionsAfter.single.id, revisionsBefore.single.id);
      expect(revisionsAfter.single.revision, 1);
    },
  );
  test(
    'createSpatialForParcelScoped creates Spatial state without persisting LandParcel',
    () async {
      final parcel = createParcel(
        id: 'spatial-only-create',
        code: 'SPATIAL-ONLY-CREATE',
      );

      // The Spatial link has a foreign key to LandParcel, so the business
      // record must already exist before the Spatial-only operation.
      await parcels.create(parcel);

      final storedBefore = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );

      expect(storedBefore, isNotNull);
      expect(storedBefore!.name, parcel.name);
      expect(storedBefore.updatedAt, parcel.updatedAt);

      await LandParcelSpatialTransaction(database).run<void>((
        scopedParcels,
        scopedLinks,
        scopedSpatial,
      ) async {
        await workflow.createSpatialForParcelScoped(
          links: scopedLinks,
          spatial: scopedSpatial,
          parcel: parcel,
          temporalState: SpatialTemporalState.operational,
          spatialLinkId: 'spatial-only-link',
          spatialFeatureId: 'spatial-only-feature',
          spatialRevisionId: 'spatial-only-revision-1',
          changeReason: 'landParcel.created',
        );
      });

      final storedAfter = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final link = await links.findByLandParcelId(parcel.id);
      final feature = await spatial.featureRepository.findById(
        'spatial-only-feature',
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'spatial-only-feature',
      );

      // The Spatial-only primitive must not mutate the LandParcel.
      expect(storedAfter, isNotNull);
      expect(storedAfter!.name, storedBefore.name);
      expect(storedAfter.updatedAt, storedBefore.updatedAt);

      expect(link, isNotNull);
      expect(link!.spatialFeatureId, 'spatial-only-feature');

      expect(feature, isNotNull);
      expect(feature!.name, parcel.name);

      expect(revisions, hasLength(1));
      expect(revisions.single.id, 'spatial-only-revision-1');
      expect(revisions.single.revision, 1);
      expect(revisions.single.changeReason, 'landParcel.created');
    },
  );

  test(
    'updateSpatialForParcelScoped appends Spatial revision without mutating LandParcel',
    () async {
      final parcel = createParcel(
        id: 'spatial-only-update',
        code: 'SPATIAL-ONLY-UPDATE',
      );

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final storedBefore = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final link = await links.findByLandParcelId(parcel.id);

      expect(storedBefore, isNotNull);
      expect(link, isNotNull);

      final featureId = link!.spatialFeatureId;
      final revisionsBefore = await spatial.revisionRepository.findByFeatureId(
        featureId,
      );

      expect(revisionsBefore, hasLength(1));

      final updatedSnapshot = parcel.updateMetadata(
        name: 'Spatial-only updated name',
        actorMembershipId: 'member-2',
        occurredAt: DateTime.utc(2026, 9, 12, 9),
      );

      await LandParcelSpatialTransaction(database).run<void>((
        scopedParcels,
        scopedLinks,
        scopedSpatial,
      ) async {
        await workflow.updateSpatialForParcelScoped(
          links: scopedLinks,
          spatial: scopedSpatial,
          parcel: updatedSnapshot,
          temporalState: SpatialTemporalState.operational,
          changeReason: 'landParcel.metadataUpdated',
        );
      });

      final storedAfter = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      final featureAfter = await spatial.featureRepository.findById(featureId);
      final revisionsAfter = await spatial.revisionRepository.findByFeatureId(
        featureId,
      );

      expect(storedAfter, isNotNull);
      expect(storedAfter!.name, parcel.name);
      expect(storedAfter.updatedAt, parcel.updatedAt);

      expect(featureAfter, isNotNull);
      expect(featureAfter!.name, updatedSnapshot.name);
      expect(featureAfter.updatedAt, updatedSnapshot.updatedAt);

      expect(revisionsAfter, hasLength(2));
      expect(revisionsAfter[0].revision, 1);
      expect(revisionsAfter[1].revision, 2);
      expect(revisionsAfter[1].changeReason, 'landParcel.metadataUpdated');
    },
  );
}
