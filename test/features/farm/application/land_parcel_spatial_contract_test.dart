import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';

void main() {
  sqfliteFfiInit();

  final createdAt = DateTime.utc(2026, 9, 13, 8);

  Wgs84Polygon boundary({double east = 104.7010}) {
    return Wgs84Polygon.fromVertices([
      const Wgs84Vertex(latitude: 16.5000, longitude: 104.7000),
      Wgs84Vertex(latitude: 16.5000, longitude: east),
      Wgs84Vertex(latitude: 16.5010, longitude: east),
      const Wgs84Vertex(latitude: 16.5010, longitude: 104.7000),
    ]);
  }

  /// Sprint 12 fixture rule: caller-supplied spatialFeatureId must be
  /// established at LandParcel creation time so workflow.create() persists
  /// a consistent identity across LandParcel, Link, SpatialFeature, R1.
  LandParcel createParcel({String? spatialFeatureId}) {
    return LandParcel.create(
      id: 'parcel-contract-1',
      farmId: 'farm-contract-1',
      parcelCode: 'P-CONTRACT-001',
      name: 'Contract Parcel',
      boundary: boundary(),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-contract-1',
      occurredAt: createdAt,
      horizontalAccuracyM: 1.5,
      spatialFeatureId: spatialFeatureId,
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

  tearDown(() async {
    await database.close();
  });

  test('direct spatial creation is rejected without a parcel row', () async {
    final source = createParcel(spatialFeatureId: 'SPF-DIRECT');
    await expectLater(parcels.create(source), throwsStateError);
    expect(await parcels.getById(farmId: source.farmId, id: source.id), isNull);
  });

  test('direct boundary write and history append cannot bypass Spatial Core', () async {
    const id = 'SPF-BOUNDARY-GUARD';
    final source = createParcel(spatialFeatureId: id);
    await workflow.create(parcel: source, temporalState: SpatialTemporalState.baseline);
    final changed = source.replaceBoundary(
      boundary: boundary(east: 104.702),
      source: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-2',
      occurredAt: createdAt.add(const Duration(hours: 1)),
    );
    await expectLater(parcels.update(changed), throwsStateError);
    await expectLater(parcels.saveBoundaryVersion(changed.boundaryHistory.last), throwsStateError);
    expect((await parcels.getById(farmId: source.farmId, id: source.id))!.boundaryVersion, 1);
    expect(await spatial.revisionRepository.findByFeatureId(id), hasLength(1));

    final metadata = source.updateMetadata(
      name: 'Metadata only',
      actorMembershipId: 'member-2',
      occurredAt: createdAt.add(const Duration(hours: 1)),
    );
    await parcels.update(metadata);
    expect((await parcels.getById(farmId: source.farmId, id: source.id))!.name, 'Metadata only');
    expect(await spatial.revisionRepository.findByFeatureId(id), hasLength(1));
  });

  test('shared transaction rolls back an unpaired spatial boundary write', () async {
    const id = 'SPF-SCOPED-GUARD';
    final source = createParcel(spatialFeatureId: id);
    await workflow.create(parcel: source, temporalState: SpatialTemporalState.baseline);
    final changed = source.replaceBoundary(
      boundary: boundary(east: 104.702),
      source: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-2',
      occurredAt: createdAt.add(const Duration(hours: 1)),
    );
    await expectLater(
      LandParcelSpatialTransaction(database).run<void>((scoped, _, __) async {
        await scoped.update(changed);
      }),
      throwsStateError,
    );
    expect((await parcels.getById(farmId: source.farmId, id: source.id))!.boundaryVersion, 1);
    expect(await spatial.revisionRepository.findByFeatureId(id), hasLength(1));
  });

  test('persisted link also blocks direct writes when parcel identity is null', () async {
    final source = createParcel();
    await workflow.create(parcel: source, temporalState: SpatialTemporalState.baseline);
    final changed = source.replaceBoundary(
      boundary: boundary(east: 104.702),
      source: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-2',
      occurredAt: createdAt.add(const Duration(hours: 1)),
    );
    await expectLater(parcels.update(changed), throwsStateError);
    expect((await parcels.getById(farmId: source.farmId, id: source.id))!.boundaryVersion, 1);
  });

  test('legacy identity establishment requires atomic spatial bootstrap', () async {
    final legacy = createParcel();
    await parcels.create(legacy);
    await expectLater(
      parcels.update(legacy.assignSpatialFeatureId('SPF-ORPHAN')),
      throwsStateError,
    );
    expect((await parcels.getById(farmId: legacy.farmId, id: legacy.id))!.spatialFeatureId, isNull);
    await workflow.bootstrapExisting(
      farmId: legacy.farmId,
      landParcelId: legacy.id,
      temporalState: SpatialTemporalState.baseline,
    );
    final stored = (await parcels.getById(farmId: legacy.farmId, id: legacy.id))!;
    expect(stored.spatialFeatureId, isNotNull);
    expect((await links.findByLandParcelId(legacy.id))!.spatialFeatureId, stored.spatialFeatureId);
  });

  test(
    'stable LandParcel, link and SpatialFeature identities survive boundary revisions',
    () async {
      const X = 'SPF-CONTRACT-001';
      final version1 = createParcel(spatialFeatureId: X);

      await workflow.create(
        parcel: version1,
        temporalState: SpatialTemporalState.operational,
      );

      // Sprint 12: caller-established identity survives create.
      final persistedAfterCreate = await parcels.getById(
        farmId: version1.farmId,
        id: version1.id,
      );
      expect(persistedAfterCreate!.spatialFeatureId, X);

      final linkAfterCreate = await links.findByLandParcelId(version1.id);
      expect(linkAfterCreate, isNotNull);

      final featureAfterCreate = await spatial.featureRepository.findById(
        linkAfterCreate!.spatialFeatureId,
      );
      expect(featureAfterCreate, isNotNull);

      final version2 = version1.replaceBoundary(
        boundary: boundary(east: 104.7020),
        source: BoundarySource.googleEarth,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-contract-2',
        occurredAt: DateTime.utc(2026, 9, 13, 9),
        horizontalAccuracyM: 2.0,
        note: 'Boundary refined from Google Earth.',
      );

      await workflow.update(
        parcel: version2,
        temporalState: SpatialTemporalState.operational,
      );

      final version3 = version2.replaceBoundary(
        boundary: boundary(east: 104.7030),
        source: BoundarySource.cad,
        verificationStatus: BoundaryVerificationStatus.verified,
        actorMembershipId: 'member-contract-3',
        occurredAt: DateTime.utc(2026, 9, 13, 10),
        horizontalAccuracyM: 0.5,
        note: 'Boundary verified from CAD survey data.',
      );

      await workflow.update(
        parcel: version3,
        temporalState: SpatialTemporalState.operational,
      );

      final storedParcel = await parcels.getById(
        farmId: version3.farmId,
        id: version3.id,
      );
      final finalLink = await links.findByLandParcelId(version3.id);
      final feature = await spatial.featureRepository.findById(
        linkAfterCreate.spatialFeatureId,
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        linkAfterCreate.spatialFeatureId,
      );

      expect(storedParcel, isNotNull);
      expect(storedParcel!.id, version1.id);
      expect(storedParcel.farmId, version1.farmId);
      expect(storedParcel.boundaryVersion, 3);
      expect(storedParcel.boundaryHistory.map((item) => item.version), [
        1,
        2,
        3,
      ]);

      expect(finalLink, isA<LandParcelSpatialLink>());
      expect(finalLink!.id, linkAfterCreate.id);
      expect(finalLink.landParcelId, version1.id);
      expect(finalLink.spatialFeatureId, linkAfterCreate.spatialFeatureId);

      expect(feature, isNotNull);
      expect(feature!.id, linkAfterCreate.spatialFeatureId);
      expect(feature.featureType, featureAfterCreate!.featureType);
      expect(feature.geometryType, featureAfterCreate.geometryType);

      expect(revisions, hasLength(3));
      expect(revisions.map((item) => item.revision), [1, 2, 3]);
      expect(revisions.map((item) => item.featureId).toSet(), {
        linkAfterCreate.spatialFeatureId,
      });
      expect(revisions.map((item) => item.id).toSet(), hasLength(3));

      expect(revisions[0].geometryReference, version1.boundaryHistory[0].id);
      expect(revisions[1].geometryReference, version2.boundaryHistory[1].id);
      expect(revisions[2].geometryReference, version3.boundaryHistory[2].id);

      expect(
        revisions[0].source.sourceReference,
        version1.boundaryHistory[0].id,
      );
      expect(
        revisions[1].source.sourceReference,
        version2.boundaryHistory[1].id,
      );
      expect(
        revisions[2].source.sourceReference,
        version3.boundaryHistory[2].id,
      );

      final latestRevision = revisions.last;
      final latestGeometry = latestRevision.geometry! as SpatialPolygon;
      final latestBoundary = version3.boundary;

      expect(latestGeometry.outerRing.length, latestBoundary.vertices.length);
      expect(
        latestGeometry.outerRing.first.latitude,
        latestBoundary.vertices.first.latitude,
      );
      expect(
        latestGeometry.outerRing.first.longitude,
        latestBoundary.vertices.first.longitude,
      );
    },
  );

  test(
    'workflow update keeps spatial identity and appends one revision',
    () async {
      const X = 'SPF-CONTRACT-002';
      final parcel = createParcel(spatialFeatureId: X);

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final initialLink = await links.findByLandParcelId(parcel.id);
      expect(initialLink, isNotNull);

      final updated = parcel.updateMetadata(
        name: 'Metadata update',
        actorMembershipId: 'member-contract-2',
        occurredAt: DateTime.utc(2026, 9, 13, 9),
      );

      await workflow.update(
        parcel: updated,
        temporalState: SpatialTemporalState.operational,
      );

      final linkAfterUpdate = await links.findByLandParcelId(parcel.id);
      final feature = await spatial.featureRepository.findById(
        initialLink!.spatialFeatureId,
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        initialLink.spatialFeatureId,
      );

      expect(linkAfterUpdate, isNotNull);
      expect(linkAfterUpdate!.id, initialLink.id);
      expect(linkAfterUpdate.spatialFeatureId, initialLink.spatialFeatureId);

      expect(feature, isNotNull);
      expect(feature!.id, initialLink.spatialFeatureId);
      expect(feature.name, 'Metadata update');

      expect(revisions, hasLength(2));
      expect(revisions.map((item) => item.revision), [1, 2]);
      expect(revisions.map((item) => item.featureId).toSet(), {
        initialLink.spatialFeatureId,
      });
    },
  );

  test('LandParcelSpatialLink is the official stable bridge', () async {
    const X = 'SPF-CONTRACT-003';
    final parcel = createParcel(spatialFeatureId: X);

    await workflow.create(
      parcel: parcel,
      temporalState: SpatialTemporalState.operational,
    );

    final link = await links.findByLandParcelId(parcel.id);
    expect(link, isA<LandParcelSpatialLink>());
    expect(link!.landParcelId, parcel.id);
    expect(link.spatialFeatureId, isNot(parcel.id));

    final spatialFeature = await spatial.featureRepository.findById(
      link.spatialFeatureId,
    );
    expect(spatialFeature, isNotNull);
    expect(spatialFeature!.id, link.spatialFeatureId);

    final revisions = await spatial.revisionRepository.findByFeatureId(
      link.spatialFeatureId,
    );
    expect(revisions, hasLength(1));
    expect(revisions.single.featureId, link.spatialFeatureId);
    expect(revisions.single.revision, 1);
  });
}
