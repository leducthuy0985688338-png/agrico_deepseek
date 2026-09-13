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
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  LandParcel createParcel() {
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

  test(
    'LandParcel and Spatial Core keep stable identities while boundary evolves',
    () async {
      final initial = createParcel();

      await workflow.create(
        parcel: initial,
        temporalState: SpatialTemporalState.operational,
      );

      final firstLink = await links.findByLandParcelId(initial.id);
      expect(firstLink, isNotNull);

      final changedBoundary = initial.replaceBoundary(
        boundary: boundary(east: 104.7020),
        source: BoundarySource.googleEarth,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-contract-2',
        occurredAt: DateTime.utc(2026, 9, 13, 9),
        horizontalAccuracyM: 2.0,
        note: 'Boundary refined from Google Earth.',
      );

      await workflow.update(
        parcel: changedBoundary,
        temporalState: SpatialTemporalState.operational,
      );

      final storedParcel = await parcels.getById(
        farmId: changedBoundary.farmId,
        id: changedBoundary.id,
      );
      final storedLink = await links.findByLandParcelId(changedBoundary.id);
      final revisions = await spatial.revisionRepository.findByFeatureId(
        firstLink!.spatialFeatureId,
      );

      expect(storedParcel, isNotNull);
      expect(storedParcel!.id, initial.id);
      expect(storedParcel.boundaryVersion, 2);
      expect(storedParcel.boundaryHistory.map((item) => item.version), [1, 2]);

      expect(storedLink, isNotNull);
      expect(storedLink!.landParcelId, initial.id);
      expect(storedLink.spatialFeatureId, firstLink.spatialFeatureId);

      expect(revisions.map((item) => item.revision), [1, 2]);
      expect(revisions.every((item) => item.featureId == firstLink.spatialFeatureId), isTrue);
      expect(revisions[1].geometryReference, changedBoundary.boundaryHistory.last.id);
      expect(revisions[1].source.sourceReference, changedBoundary.boundaryHistory.last.id);
    },
  );

  test(
    'three boundary versions produce exactly three Spatial revisions',
    () async {
      final version1 = createParcel();
      await workflow.create(
        parcel: version1,
        temporalState: SpatialTemporalState.operational,
      );

      final version2 = version1.replaceBoundary(
        boundary: boundary(east: 104.7020),
        source: BoundarySource.googleEarth,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-contract-2',
        occurredAt: DateTime.utc(2026, 9, 13, 9),
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
      );
      await workflow.update(
        parcel: version3,
        temporalState: SpatialTemporalState.operational,
      );

      final link = await links.findByLandParcelId(version3.id);
      final storedParcel = await parcels.getById(
        farmId: version3.farmId,
        id: version3.id,
      );
      final revisions = await spatial.revisionRepository.findByFeatureId(
        link!.spatialFeatureId,
      );

      expect(storedParcel!.id, version1.id);
      expect(storedParcel.boundaryVersion, 3);
      expect(storedParcel.boundaryHistory, hasLength(3));
      expect(storedParcel.boundaryHistory.map((item) => item.version), [1, 2, 3]);

      expect(revisions, hasLength(3));
      expect(revisions.map((item) => item.revision), [1, 2, 3]);
      expect(revisions.map((item) => item.featureId).toSet(), {
        link.spatialFeatureId,
      });

      final latestRevision = revisions.last;
      final latestGeometry = latestRevision.geometry! as SpatialPolygon;
      final latestBoundary = version3.boundary;

      expect(latestGeometry.outerRing.length, latestBoundary.vertices.length + 1);
      expect(latestGeometry.outerRing.first.latitude, latestBoundary.vertices.first.latitude);
      expect(latestGeometry.outerRing.first.longitude, latestBoundary.vertices.first.longitude);
    },
  );

  test(
    'LandParcelSpatialLink is the only stable bridge and never changes spatial identity',
    () async {
      final parcel = createParcel();

      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );

      final link = await links.findByLandParcelId(parcel.id);
      expect(link, isA<LandParcelSpatialLink>());
      expect(link!.landParcelId, parcel.id);
      expect(link.spatialFeatureId, isNot(parcel.id));

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
      expect(linkAfterUpdate, isNotNull);
      expect(linkAfterUpdate!.id, link.id);
      expect(linkAfterUpdate.spatialFeatureId, link.spatialFeatureId);

      final feature = await spatial.featureRepository.findById(
        link.spatialFeatureId,
      );
      expect(feature, isNotNull);
      expect(feature!.id, link.spatialFeatureId);
      expect(feature.name, 'Metadata update');
    },
  );
}
