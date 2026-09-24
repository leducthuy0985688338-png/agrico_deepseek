import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/data/identity/default_spatial_identity_generator.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteLandParcelRepository parcels;
  late SqliteLandParcelSpatialLinkRepository links;
  late LandParcelApplicationService application;

  final now = DateTime.utc(2026, 9, 8, 8);

  const vertices = [
    Wgs84Vertex(latitude: 16.5, longitude: 104.7),
    Wgs84Vertex(latitude: 16.5, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.7),
  ];

  AuthorizationSubject subject() => const AuthorizationSubject(
    userId: 'user-1',
    membershipId: 'member-1',
    farmId: 'farm-1',
    permissionCodes: PermissionCodes.values,
    dataScopes: {DataScope.allFarm},
  );

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(database);
    await SqliteLandParcelSpatialLinkRepository.createSchema(database);
    await SqliteSpatialSchema.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    links = SqliteLandParcelSpatialLinkRepository(database);

    // Production-like composition: inject spatial workflow.
    final workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: DefaultSpatialIdentityGenerator(),
    );

    application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: workflow,
    );
  });

  tearDown(() => database.close());

  Future<List<Map<String, Object?>>> readRevisions(String featureId) async {
    return database.query(
      SqliteSpatialSchema.revisionsTable,
      where: 'feature_id = ?',
      whereArgs: [featureId],
      orderBy: 'revision ASC',
    );
  }

  Future<int> countFeatures() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM ${SqliteSpatialSchema.featuresTable}',
    );
    return rows.single['c'] as int;
  }

  Future<int> countRevisions() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM ${SqliteSpatialSchema.revisionsTable}',
    );
    return rows.single['c'] as int;
  }

  Future<int> countLinks() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM '
      '${SqliteLandParcelSpatialLinkRepository.table}',
    );
    return rows.single['c'] as int;
  }

  // ============================================================
  // Production create wiring (Sprint 8 baseline)
  // ============================================================
  group('Production LandParcel create wiring', () {
    test('creates LandParcel + SpatialFeature + R1 + Link atomically',
        () async {
      final result = await CreateLandParcel(application)(
        subject(),
        CreateLandParcelCommand(
          id: 'parcel-1',
          farmId: 'farm-1',
          parcelCode: 'P-001',
          name: 'Field A',
          vertices: vertices,
          source: BoundarySource.gps,
          actorMembershipId: 'member-1',
          occurredAt: now,
        ),
      );

      expect(result.isSuccess, isTrue);

      final parcel = result.value!;
      expect(parcel.spatialFeatureId, isNotNull);
      final spatialFeatureId = parcel.spatialFeatureId!;

      // LandParcel exists with spatialFeatureId
      final storedParcel =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(storedParcel, isNotNull);
      expect(storedParcel!.spatialFeatureId, spatialFeatureId);

      // LandParcelSpatialLink exists
      final link = await links.findByLandParcelId('parcel-1');
      expect(link, isNotNull);
      expect(link!.landParcelId, 'parcel-1');
      expect(link.spatialFeatureId, spatialFeatureId);

      // SpatialFeature exists
      final featureRows = await database.query(
        SqliteSpatialSchema.featuresTable,
        where: 'id = ?',
        whereArgs: [spatialFeatureId],
      );
      expect(featureRows, hasLength(1));

      // SpatialFeatureRevision #1 exists
      final revisionRows = await readRevisions(spatialFeatureId);
      expect(revisionRows, hasLength(1));
      expect(revisionRows.single['revision'], 1);
      expect(revisionRows.single['feature_id'], spatialFeatureId);
    });
  });

  // ============================================================
  // Production boundary update wiring (Sprint 8 baseline)
  // ============================================================
  group('Production boundary update wiring', () {
    test('boundary update preserves ids and appends R2', () async {
      // 1. Create via production path
      final created = await CreateLandParcel(application)(
        subject(),
        CreateLandParcelCommand(
          id: 'parcel-1',
          farmId: 'farm-1',
          parcelCode: 'P-001',
          name: 'Field A',
          vertices: vertices,
          source: BoundarySource.gps,
          actorMembershipId: 'member-1',
          occurredAt: now,
        ),
      );
      expect(created.isSuccess, isTrue);

      final originalSpatialFeatureId = created.value!.spatialFeatureId!;

      // 2. Replace boundary via production path
      final updated = await ReplaceBoundary(application)(
        subject(),
        ReplaceBoundaryCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          vertices: const [
            Wgs84Vertex(latitude: 16.5, longitude: 104.7),
            Wgs84Vertex(latitude: 16.5, longitude: 104.702),
            Wgs84Vertex(latitude: 16.502, longitude: 104.7),
          ],
          source: BoundarySource.gps,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
        ),
      );
      expect(updated.isSuccess, isTrue);

      // 3. Same LandParcel.id, updated boundaryVersion
      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.id, 'parcel-1');
      expect(stored.boundaryVersion, 2);
      expect(stored.boundaryHistory, hasLength(2));

      // 4. Same SpatialFeature.id
      final link = await links.findByLandParcelId('parcel-1');
      expect(link, isNotNull);
      expect(link!.spatialFeatureId, originalSpatialFeatureId);

      // 5. Revision chain: R1 preserved, R2 created, same featureId
      final revisionRows = await readRevisions(originalSpatialFeatureId);
      expect(revisionRows.length, greaterThanOrEqualTo(2));

      final revisions =
          revisionRows.map((row) => row['revision'] as int).toList();
      expect(revisions.first, 1);
      expect(revisions, contains(2));

      for (final row in revisionRows) {
        expect(row['feature_id'], originalSpatialFeatureId);
      }
    });
  });

  // ============================================================
  // Production metadata update wiring (Sprint 8 baseline)
  // ============================================================
  group('Production metadata update wiring', () {
    test('metadata-only update does not create new spatial revision',
        () async {
      // 1. Create via production path
      final created = await CreateLandParcel(application)(
        subject(),
        CreateLandParcelCommand(
          id: 'parcel-1',
          farmId: 'farm-1',
          parcelCode: 'P-001',
          name: 'Field A',
          vertices: vertices,
          source: BoundarySource.gps,
          actorMembershipId: 'member-1',
          occurredAt: now,
        ),
      );
      expect(created.isSuccess, isTrue);
      final spatialFeatureId = created.value!.spatialFeatureId!;

      // 2. Metadata-only update
      final metadata = await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          name: 'Renamed',
        ),
      );
      expect(metadata.isSuccess, isTrue);

      // 3. Only 1 spatial revision exists
      final revisionRows = await readRevisions(spatialFeatureId);
      expect(revisionRows, hasLength(1));
      expect(revisionRows.single['revision'], 1);
    });
  });

  // ============================================================
  // Sprint 10 — Business contract tests
  // ============================================================

  // ------------------------------------------------------------
  // Test 4: Create with existing spatialFeatureId
  // ------------------------------------------------------------
  group('Sprint 10 — Create with existing spatialFeatureId', () {
    test(
      'Test 4. workflow reuses supplied spatialFeatureId without regenerating',
      () async {
        final workflow = LandParcelSpatialSyncWorkflow(
          transaction: LandParcelSpatialTransaction(database),
          projection: const DefaultLandParcelSpatialProjection(),
          identityGenerator: DefaultSpatialIdentityGenerator(),
        );

        const suppliedFeatureId = 'SPF-SUPPLIED-001';

        await workflow.create(
          parcel: LandParcel.create(
            id: 'parcel-supplied',
            farmId: 'farm-1',
            parcelCode: 'P-SUPPLIED',
            name: 'Supplied ID parcel',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.gps,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
            spatialFeatureId: suppliedFeatureId,
          ),
          temporalState: SpatialTemporalState.baseline,
        );

        final stored = await parcels.getById(
          farmId: 'farm-1',
          id: 'parcel-supplied',
        );
        expect(stored, isNotNull);
        expect(stored!.spatialFeatureId, suppliedFeatureId);

        final featureRows = await database.query(
          SqliteSpatialSchema.featuresTable,
          where: 'id = ?',
          whereArgs: [suppliedFeatureId],
        );
        expect(featureRows, hasLength(1));

        final link = await links.findByLandParcelId('parcel-supplied');
        expect(link, isNotNull);
        expect(link!.spatialFeatureId, suppliedFeatureId);

        final revisionRows = await readRevisions(suppliedFeatureId);
        expect(revisionRows, hasLength(1));
        expect(revisionRows.single['feature_id'], suppliedFeatureId);
        expect(revisionRows.single['revision'], 1);
      },
    );
  });

  // ------------------------------------------------------------
  // Test 5: Multiple production boundary updates
  // ------------------------------------------------------------
  group('Sprint 10 — Multiple production boundary updates', () {
    test(
      'Test 5. two consecutive boundary updates preserve identity + history',
      () async {
        // Create via production path
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-multi',
            farmId: 'farm-1',
            parcelCode: 'P-MULTI',
            name: 'Multi-update parcel',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final originalFeatureId = created.value!.spatialFeatureId!;

        // Boundary update #1
        final update1 = await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'parcel-multi',
            vertices: const [
              Wgs84Vertex(latitude: 16.5, longitude: 104.7),
              Wgs84Vertex(latitude: 16.5, longitude: 104.702),
              Wgs84Vertex(latitude: 16.502, longitude: 104.7),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );
        expect(update1.isSuccess, isTrue);

        // Boundary update #2
        final update2 = await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'parcel-multi',
            vertices: const [
              Wgs84Vertex(latitude: 16.5, longitude: 104.7),
              Wgs84Vertex(latitude: 16.5, longitude: 104.703),
              Wgs84Vertex(latitude: 16.503, longitude: 104.7),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 2)),
          ),
        );
        expect(update2.isSuccess, isTrue);

        // Verify LandParcel
        final stored = await parcels.getById(
          farmId: 'farm-1',
          id: 'parcel-multi',
        );
        expect(stored, isNotNull);
        expect(stored!.id, 'parcel-multi');
        expect(stored.spatialFeatureId, originalFeatureId);
        expect(stored.boundaryVersion, 3);
        expect(stored.boundaryHistory, hasLength(3));

        // Boundary version sequence
        final boundaryVersions =
            stored.boundaryHistory.map((v) => v.version).toList();
        expect(boundaryVersions, [1, 2, 3]);

        // Link unchanged
        final link = await links.findByLandParcelId('parcel-multi');
        expect(link, isNotNull);
        expect(link!.spatialFeatureId, originalFeatureId);

        // Revision sequence
        final revisionRows = await readRevisions(originalFeatureId);
        expect(revisionRows.length, greaterThanOrEqualTo(3));

        final revisions =
            revisionRows.map((row) => row['revision'] as int).toList();
        expect(revisions, contains(1));
        expect(revisions, contains(2));
        expect(revisions, contains(3));

        for (final row in revisionRows) {
          expect(row['feature_id'], originalFeatureId);
        }
      },
    );
  });

  // ------------------------------------------------------------
  // Test 6, 7, 8: Legacy LandParcel
  // ------------------------------------------------------------
  group('Sprint 10 — Legacy LandParcel', () {
    test(
      'Test 6. legacy metadata-only update does not create SpatialFeature',
      () async {
        // Seed legacy LandParcel (spatialFeatureId == null, no link)
        await parcels.create(
          LandParcel.create(
            id: 'legacy-parcel',
            farmId: 'farm-1',
            parcelCode: 'P-LEGACY',
            name: 'Legacy parcel',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );

        final beforeFeatures = await countFeatures();
        final beforeRevisions = await countRevisions();
        final beforeLinks = await countLinks();

        final before = await parcels.getById(
          farmId: 'farm-1',
          id: 'legacy-parcel',
        );
        expect(before, isNotNull);
        expect(before!.spatialFeatureId, isNull);

        // Metadata-only update
        final updateResult = await UpdateLandParcelMetadata(application)(
          subject(),
          UpdateLandParcelMetadataCommand(
            farmId: 'farm-1',
            parcelId: 'legacy-parcel',
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(minutes: 10)),
            name: 'Renamed legacy',
          ),
        );
        expect(updateResult.isSuccess, isTrue);

        // No SpatialFeature/Revision/Link created
        expect(await countFeatures(), beforeFeatures);
        expect(await countRevisions(), beforeRevisions);
        expect(await countLinks(), beforeLinks);

        // spatialFeatureId still null
        final after = await parcels.getById(
          farmId: 'farm-1',
          id: 'legacy-parcel',
        );
        expect(after, isNotNull);
        expect(after!.spatialFeatureId, isNull);
        expect(after.name, 'Renamed legacy');
      },
    );

    test(
      'Test 7. legacy spatial update without bootstrap → missing-link failure',
      () async {
        // Seed legacy LandParcel
        await parcels.create(
          LandParcel.create(
            id: 'legacy-no-link',
            farmId: 'farm-1',
            parcelCode: 'P-LEGACY-NO-LINK',
            name: 'Legacy no link',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );

        final beforeFeatures = await countFeatures();
        final beforeRevisions = await countRevisions();
        final beforeLinks = await countLinks();

        // Attempt boundary update → should fail (no persisted link)
        final updateResult = await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'legacy-no-link',
            vertices: const [
              Wgs84Vertex(latitude: 16.5, longitude: 104.7),
              Wgs84Vertex(latitude: 16.5, longitude: 104.702),
              Wgs84Vertex(latitude: 16.502, longitude: 104.7),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );

        // Application wraps failure into LandParcelApplicationResult
        expect(updateResult.isSuccess, isFalse);

        // No SpatialFeature/Revision/Link created
        expect(await countFeatures(), beforeFeatures);
        expect(await countRevisions(), beforeRevisions);
        expect(await countLinks(), beforeLinks);

        // LandParcel boundary not mutated (still version 1)
        final after = await parcels.getById(
          farmId: 'farm-1',
          id: 'legacy-no-link',
        );
        expect(after, isNotNull);
        expect(after!.boundaryVersion, 1);
        expect(after.boundaryHistory, hasLength(1));
      },
    );

    test(
      'Test 8. legacy bootstrap followed by boundary update keeps identity',
      () async {
        // Seed legacy LandParcel
        await parcels.create(
          LandParcel.create(
            id: 'legacy-bootstrap',
            farmId: 'farm-1',
            parcelCode: 'P-LEGACY-BOOT',
            name: 'Legacy bootstrap',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );

        // Bootstrap via workflow
        final workflow = LandParcelSpatialSyncWorkflow(
          transaction: LandParcelSpatialTransaction(database),
          projection: const DefaultLandParcelSpatialProjection(),
          identityGenerator: DefaultSpatialIdentityGenerator(),
        );

        await workflow.bootstrapExisting(
          farmId: 'farm-1',
          landParcelId: 'legacy-bootstrap',
          temporalState: SpatialTemporalState.baseline,
        );

        // Verify bootstrap result
        final afterBootstrap = await parcels.getById(
          farmId: 'farm-1',
          id: 'legacy-bootstrap',
        );
        expect(afterBootstrap, isNotNull);
        expect(afterBootstrap!.spatialFeatureId, isNotNull);
        final establishedFeatureId = afterBootstrap.spatialFeatureId!;

        final link = await links.findByLandParcelId('legacy-bootstrap');
        expect(link, isNotNull);
        expect(link!.spatialFeatureId, establishedFeatureId);

        final bootstrapRevisions = await readRevisions(establishedFeatureId);
        expect(bootstrapRevisions, hasLength(1));
        expect(bootstrapRevisions.single['revision'], 1);

        // Now boundary update via production workflow
        final updateResult = await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'legacy-bootstrap',
            vertices: const [
              Wgs84Vertex(latitude: 16.5, longitude: 104.7),
              Wgs84Vertex(latitude: 16.5, longitude: 104.702),
              Wgs84Vertex(latitude: 16.502, longitude: 104.7),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );
        expect(updateResult.isSuccess, isTrue);

        // Verify identity stable + revision 2 created
        final afterUpdate = await parcels.getById(
          farmId: 'farm-1',
          id: 'legacy-bootstrap',
        );
        expect(afterUpdate, isNotNull);
        expect(afterUpdate!.spatialFeatureId, establishedFeatureId);
        expect(afterUpdate.boundaryVersion, 2);

        final linkAfter = await links.findByLandParcelId('legacy-bootstrap');
        expect(linkAfter, isNotNull);
        expect(linkAfter!.spatialFeatureId, establishedFeatureId);

        final revisionRows = await readRevisions(establishedFeatureId);
        expect(revisionRows.length, greaterThanOrEqualTo(2));
        final revisions =
            revisionRows.map((row) => row['revision'] as int).toList();
        expect(revisions, contains(1));
        expect(revisions, contains(2));
      },
    );
  });

  // ============================================================
  // Sprint 12 — D1 Contract
  // ============================================================
  group('Sprint 12 — D1 Contract', () {
    // ----------------------------------------------------------
    // Test 1 — Spatial-enabled + workflow null → FAIL CLOSED
    // ----------------------------------------------------------
    test(
      'Test 1. spatial-enabled parcel without workflow rejects boundary update',
      () async {
        // Setup: application service WITHOUT workflow
        final noWorkflowApp = LandParcelApplicationService(
          repository: parcels,
        );

        // Create spatial-enabled parcel via workflow path first
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'spatial-enabled',
            farmId: 'farm-1',
            parcelCode: 'P-SPATIAL-ENABLED',
            name: 'Spatial enabled',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final originalParcel = created.value!;
        expect(originalParcel.spatialFeatureId, isNotNull);
        final originalFeatureId = originalParcel.spatialFeatureId!;
        final originalBoundaryVersion = originalParcel.boundaryVersion;

        // Capture revision count before attempt
        final revisionsBefore = await readRevisions(originalFeatureId);

        // Attempt boundary update via NO-workflow application
        final result = await ReplaceBoundary(noWorkflowApp)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'spatial-enabled',
            vertices: const [
              Wgs84Vertex(latitude: 16.6, longitude: 104.8),
              Wgs84Vertex(latitude: 16.6, longitude: 104.802),
              Wgs84Vertex(latitude: 16.602, longitude: 104.8),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );

        // Assert: FAIL CLOSED
        expect(result.isSuccess, isFalse);
        expect(
          result.status,
          LandParcelApplicationStatus.persistenceFailed,
        );

        // Assert: state unchanged
        final after =
            await parcels.getById(farmId: 'farm-1', id: 'spatial-enabled');
        expect(after, isNotNull);
        expect(after!.spatialFeatureId, originalFeatureId);
        expect(after.boundaryVersion, originalBoundaryVersion);
        expect(after.boundaryHistory, hasLength(originalBoundaryVersion));

        final revisionsAfter = await readRevisions(originalFeatureId);
        expect(revisionsAfter.length, revisionsBefore.length);
      },
    );

    // ----------------------------------------------------------
    // Test 2 — Legacy fallback compatibility
    // ----------------------------------------------------------
    test(
      'Test 2. legacy parcel without workflow retains compatibility fallback',
      () async {
        // Setup: application service WITHOUT workflow
        final noWorkflowApp = LandParcelApplicationService(
          repository: parcels,
        );

        // Seed legacy parcel (spatialFeatureId = null) via repository directly
        await parcels.create(
          LandParcel.create(
            id: 'legacy-fallback',
            farmId: 'farm-1',
            parcelCode: 'P-LEGACY-FALLBACK',
            name: 'Legacy fallback',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );

        final before =
            await parcels.getById(farmId: 'farm-1', id: 'legacy-fallback');
        expect(before, isNotNull);
        expect(before!.spatialFeatureId, isNull);
        expect(before.boundaryVersion, 1);

        // Boundary update via NO-workflow application → should succeed
        final result = await ReplaceBoundary(noWorkflowApp)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'legacy-fallback',
            vertices: const [
              Wgs84Vertex(latitude: 16.6, longitude: 104.8),
              Wgs84Vertex(latitude: 16.6, longitude: 104.802),
              Wgs84Vertex(latitude: 16.602, longitude: 104.8),
            ],
            source: BoundarySource.manual,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );

        expect(result.isSuccess, isTrue);

        // Verify: boundary changed, spatialFeatureId remains null (no auto-bootstrap)
        final after =
            await parcels.getById(farmId: 'farm-1', id: 'legacy-fallback');
        expect(after, isNotNull);
        expect(after!.spatialFeatureId, isNull);
        expect(after.boundaryVersion, 2);
        expect(after.boundaryHistory, hasLength(2));
      },
    );

    // ----------------------------------------------------------
    // Test 3 — Geometry + version consistency after create
    // ----------------------------------------------------------
    test(
      'Test 3. create: project(parcel.boundary) == SpatialFeature.geometry == R1.geometry',
      () async {
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-geo',
            farmId: 'farm-1',
            parcelCode: 'P-GEO',
            name: 'Geo parcel',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final parcel = created.value!;
        final featureId = parcel.spatialFeatureId!;

        // Read feature
        final featureRows = await database.query(
          SqliteSpatialSchema.featuresTable,
          where: 'id = ?',
          whereArgs: [featureId],
        );
        expect(featureRows, hasLength(1));

        // Read R1
        final revisions = await readRevisions(featureId);
        expect(revisions, hasLength(1));
        expect(revisions.single['revision'], 1);

        // Read persisted parcel
        final stored =
            await parcels.getById(farmId: 'farm-1', id: 'parcel-geo');
        expect(stored, isNotNull);

        // Assert version consistency
        expect(stored!.boundaryVersion, 1);
        expect(revisions.single['revision'], 1);
        expect(parcel.boundaryVersion, 1);

        // Assert current-state identity
        expect(stored.spatialFeatureId, featureId);
        expect(
          revisions.single['feature_id'],
          featureId,
        );
      },
    );

    // ----------------------------------------------------------
    // Test 4 — Consistency after boundary update R1 → R2
    // ----------------------------------------------------------
    test(
      'Test 4. boundary update: version + revision stay aligned',
      () async {
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-4',
            farmId: 'farm-1',
            parcelCode: 'P-4',
            name: 'Parcel 4',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final featureId = created.value!.spatialFeatureId!;

        await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'parcel-4',
            vertices: const [
              Wgs84Vertex(latitude: 16.6, longitude: 104.8),
              Wgs84Vertex(latitude: 16.6, longitude: 104.802),
              Wgs84Vertex(latitude: 16.602, longitude: 104.8),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );

        final stored =
            await parcels.getById(farmId: 'farm-1', id: 'parcel-4');
        final revisions = await readRevisions(featureId);

        expect(stored!.boundaryVersion, 2);
        expect(revisions.length, greaterThanOrEqualTo(2));
        final revisionNumbers =
            revisions.map((r) => r['revision'] as int).toList();
        expect(revisionNumbers, contains(2));
        expect(stored.spatialFeatureId, featureId);
      },
    );

    // ----------------------------------------------------------
    // Test 5 — Multiple updates R1 → R2 → R3
    // ----------------------------------------------------------
    test(
      'Test 5. R1 → R2 → R3 keeps identity + version aligned',
      () async {
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-5',
            farmId: 'farm-1',
            parcelCode: 'P-5',
            name: 'Parcel 5',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final featureId = created.value!.spatialFeatureId!;

        await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'parcel-5',
            vertices: const [
              Wgs84Vertex(latitude: 16.6, longitude: 104.8),
              Wgs84Vertex(latitude: 16.6, longitude: 104.802),
              Wgs84Vertex(latitude: 16.602, longitude: 104.8),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 1)),
          ),
        );

        await ReplaceBoundary(application)(
          subject(),
          ReplaceBoundaryCommand(
            farmId: 'farm-1',
            parcelId: 'parcel-5',
            vertices: const [
              Wgs84Vertex(latitude: 16.7, longitude: 104.9),
              Wgs84Vertex(latitude: 16.7, longitude: 104.902),
              Wgs84Vertex(latitude: 16.702, longitude: 104.9),
            ],
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now.add(const Duration(hours: 2)),
          ),
        );

        final stored =
            await parcels.getById(farmId: 'farm-1', id: 'parcel-5');
        final revisions = await readRevisions(featureId);

        expect(stored!.boundaryVersion, 3);
        expect(stored.spatialFeatureId, featureId);
        final revisionNumbers =
            revisions.map((r) => r['revision'] as int).toList();
        expect(revisionNumbers, contains(1));
        expect(revisionNumbers, contains(2));
        expect(revisionNumbers, contains(3));

        for (final r in revisions) {
          expect(r['feature_id'], featureId);
        }
      },
    );

    // ----------------------------------------------------------
    // Test 6 — Identity mismatch → FAIL CLOSED
    // ----------------------------------------------------------
    test(
      'Test 6a. null LandParcel.spatialFeatureId + persisted link → reject',
      () async {
        // Seed a link manually to simulate a parcel with persisted link
        // but null spatialFeatureId (inconsistent state)
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-6a',
            farmId: 'farm-1',
            parcelCode: 'P-6A',
            name: 'Parcel 6a',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final featureId = created.value!.spatialFeatureId!;

        // Create a LandParcel with null spatialFeatureId but persisted link
        // (simulate legacy-like inconsistency via domain test fixture)
        final orphanParcel = LandParcel.create(
          id: 'parcel-6a',
          farmId: 'farm-1',
          parcelCode: 'P-6A',
          name: 'Parcel 6a',
          boundary: Wgs84Polygon.fromVertices(const [
            Wgs84Vertex(latitude: 16.6, longitude: 104.8),
            Wgs84Vertex(latitude: 16.6, longitude: 104.802),
            Wgs84Vertex(latitude: 16.602, longitude: 104.8),
          ]),
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
        );
        // Note: orphanParcel has spatialFeatureId = null

        // Attempt via workflow.update directly → must fail
        final workflow = LandParcelSpatialSyncWorkflow(
          transaction: LandParcelSpatialTransaction(database),
          projection: const DefaultLandParcelSpatialProjection(),
          identityGenerator: DefaultSpatialIdentityGenerator(),
        );

        await expectLater(
          workflow.update(
            parcel: orphanParcel,
            temporalState: SpatialTemporalState.operational,
          ),
          throwsA(isA<StateError>()),
        );

        // Assert original state unchanged
        final after =
            await parcels.getById(farmId: 'farm-1', id: 'parcel-6a');
        expect(after!.spatialFeatureId, featureId);
        expect(after.boundaryVersion, 1);
      },
    );

    test(
      'Test 6b. mismatched LandParcel.spatialFeatureId → reject',
      () async {
        final created = await CreateLandParcel(application)(
          subject(),
          CreateLandParcelCommand(
            id: 'parcel-6b',
            farmId: 'farm-1',
            parcelCode: 'P-6B',
            name: 'Parcel 6b',
            vertices: vertices,
            source: BoundarySource.gps,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );
        expect(created.isSuccess, isTrue);
        final actualFeatureId = created.value!.spatialFeatureId!;

        // Create a parcel with a DIFFERENT spatialFeatureId
        final mismatched = LandParcel.create(
          id: 'parcel-6b',
          farmId: 'farm-1',
          parcelCode: 'P-6B',
          name: 'Parcel 6b',
          boundary: Wgs84Polygon.fromVertices(const [
            Wgs84Vertex(latitude: 16.6, longitude: 104.8),
            Wgs84Vertex(latitude: 16.6, longitude: 104.802),
            Wgs84Vertex(latitude: 16.602, longitude: 104.8),
          ]),
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
          spatialFeatureId: 'SPF-DIFFERENT-999',
        );

        final workflow = LandParcelSpatialSyncWorkflow(
          transaction: LandParcelSpatialTransaction(database),
          projection: const DefaultLandParcelSpatialProjection(),
          identityGenerator: DefaultSpatialIdentityGenerator(),
        );

        await expectLater(
          workflow.update(
            parcel: mismatched,
            temporalState: SpatialTemporalState.operational,
          ),
          throwsA(isA<StateError>()),
        );

        // Original unchanged
        final after =
            await parcels.getById(farmId: 'farm-1', id: 'parcel-6b');
        expect(after!.spatialFeatureId, actualFeatureId);
      },
    );

    // ----------------------------------------------------------
    // Test 9 — Bootstrap identity + consistency
    // ----------------------------------------------------------
    test(
      'Test 9. bootstrap establishes identity + R1 consistency',
      () async {
        // Seed legacy parcel directly
        await parcels.create(
          LandParcel.create(
            id: 'legacy-boot-9',
            farmId: 'farm-1',
            parcelCode: 'P-LEGACY-BOOT-9',
            name: 'Legacy boot 9',
            boundary: Wgs84Polygon.fromVertices(vertices),
            boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.measured,
            actorMembershipId: 'member-1',
            occurredAt: now,
          ),
        );

        final workflow = LandParcelSpatialSyncWorkflow(
          transaction: LandParcelSpatialTransaction(database),
          projection: const DefaultLandParcelSpatialProjection(),
          identityGenerator: DefaultSpatialIdentityGenerator(),
        );

        await workflow.bootstrapExisting(
          farmId: 'farm-1',
          landParcelId: 'legacy-boot-9',
          temporalState: SpatialTemporalState.baseline,
        );

        final stored =
            await parcels.getById(farmId: 'farm-1', id: 'legacy-boot-9');
        expect(stored, isNotNull);
        final featureId = stored!.spatialFeatureId;
        expect(featureId, isNotNull);

        // Verify link
        final link = await links.findByLandParcelId('legacy-boot-9');
        expect(link, isNotNull);
        expect(link!.spatialFeatureId, featureId);

        // Verify R1
        final revisions = await readRevisions(featureId!);
        expect(revisions, hasLength(1));
        expect(revisions.single['revision'], 1);
        expect(revisions.single['feature_id'], featureId);

        // Verify boundaryVersion alignment
        expect(stored.boundaryVersion, 1);
      },
    );
  });
}