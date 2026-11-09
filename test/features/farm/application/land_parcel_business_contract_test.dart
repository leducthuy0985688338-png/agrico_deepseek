import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/data/identity/default_spatial_identity_generator.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteLandParcelRepository parcels;
  late SqliteLandSurveyRepository surveys;
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
    await SqliteLandSurveyRepository.createSchema(database);

    parcels = SqliteLandParcelRepository(database);
    surveys = SqliteLandSurveyRepository(database);

    // Production-like composition with spatial workflow + survey repository.
    final workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: DefaultSpatialIdentityGenerator(),
    );

    application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: workflow,
      landSurveyRepository: surveys,
    );
  });

  tearDown(() => database.close());

  Future<int> countRevisions() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM ${SqliteSpatialSchema.revisionsTable}',
    );
    return rows.single['c'] as int;
  }

  Future<LandParcel> createParcel({
    String id = 'parcel-1',
    String? ownerHouseholdId,
    String? ownerDisplayName,
    String? ownerContact,
  }) async {
    final result = await CreateLandParcel(application)(
      subject(),
      CreateLandParcelCommand(
        id: id,
        farmId: 'farm-1',
        parcelCode: 'CODE-$id',
        name: 'Parcel $id',
        vertices: vertices,
        source: BoundarySource.gps,
        actorMembershipId: 'member-1',
        occurredAt: now,
        ownerHouseholdId: ownerHouseholdId,
        ownerDisplayName: ownerDisplayName,
        ownerContact: ownerContact,
      ),
    );
    expect(result.isSuccess, isTrue, reason: 'Create must succeed');
    return result.value!;
  }

  // ============================================================
  // D2 — Owner contract
  // ============================================================
  group('Sprint 11 — D2 Owner contract', () {
    test('1. create with ownerContact persists it', () async {
      final parcel = await createParcel(ownerContact: '+856 20 12345678');
      expect(parcel.ownerContact, '+856 20 12345678');

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.ownerContact, '+856 20 12345678');
    });

    test('2. read ownerContact after create', () async {
      await createParcel(ownerContact: '+856 20 999');
      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.ownerContact, '+856 20 999');
    });

    test('3. update ownerContact via application service', () async {
      await createParcel(ownerContact: '+856 20 111');

      final updateResult = await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          ownerContact: '+856 20 222',
        ),
      );
      expect(updateResult.isSuccess, isTrue);

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.ownerContact, '+856 20 222');
    });

    test('4. blank ownerContact rejected at create', () async {
      expect(
        () => LandParcel.create(
          id: 'p-blank',
          farmId: 'farm-1',
          parcelCode: 'P-BLANK',
          name: 'Blank contact',
          boundary: Wgs84Polygon.fromVertices(vertices),
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now,
          ownerContact: '   ',
        ),
        throwsFormatException,
      );
    });

    test('5. blank ownerHouseholdId rejected at create', () async {
      expect(
        () => LandParcel.create(
          id: 'p-blank',
          farmId: 'farm-1',
          parcelCode: 'P-BLANK',
          name: 'Blank household',
          boundary: Wgs84Polygon.fromVertices(vertices),
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now,
          ownerHouseholdId: '   ',
        ),
        throwsFormatException,
      );
    });

    test('6. blank ownerDisplayName rejected at create', () async {
      expect(
        () => LandParcel.create(
          id: 'p-blank',
          farmId: 'farm-1',
          parcelCode: 'P-BLANK',
          name: 'Blank display',
          boundary: Wgs84Polygon.fromVertices(vertices),
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now,
          ownerDisplayName: '   ',
        ),
        throwsFormatException,
      );
    });

    test('7. ownerDisplayName remains snapshot (no auto-sync)', () async {
      // LandParcel ownerDisplayName is a snapshot, not a reference.
      // Household.headOfHouseholdName is NOT consulted.
      final parcel = await createParcel(
        ownerDisplayName: 'Nguyễn Văn Thùy',
        ownerHouseholdId: 'HH-001',
      );
      expect(parcel.ownerDisplayName, 'Nguyễn Văn Thùy');
      expect(parcel.ownerHouseholdId, 'HH-001');

      // Even if a Household entity existed with a different name,
      // LandParcel ownerDisplayName stays as supplied.
      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored!.ownerDisplayName, 'Nguyễn Văn Thùy');
    });
  });

  // ============================================================
  // D3 — LandUseProfile contract
  // ============================================================
  group('Sprint 11 — D3 LandUseProfile contract', () {
    test('8. valid LandUseProfile validate passes', () {
      final profile = LandUseProfile(
        parcelId: 'parcel-1',
        landUseType: LandUseType.agricultural,
        currentCondition: LandCondition.cultivated,
        clearingStatus: ClearingStatus.notRequired,
        readinessStatus: ReadinessStatus.ready,
        notes: 'Sample',
        updatedAt: now,
        updatedBy: 'member-1',
      );
      expect(profile.validate, returnsNormally);
    });

    test('9. LandUseProfile rejects blank parcelId', () {
      final profile = LandUseProfile(
        parcelId: '   ',
        landUseType: LandUseType.agricultural,
        currentCondition: LandCondition.cultivated,
        clearingStatus: ClearingStatus.notRequired,
        readinessStatus: ReadinessStatus.ready,
        updatedAt: now,
        updatedBy: 'member-1',
      );
      expect(profile.validate, throwsFormatException);
    });

    test('10. LandUseProfile rejects blank updatedBy', () {
      final profile = LandUseProfile(
        parcelId: 'parcel-1',
        landUseType: LandUseType.agricultural,
        currentCondition: LandCondition.cultivated,
        clearingStatus: ClearingStatus.notRequired,
        readinessStatus: ReadinessStatus.ready,
        updatedAt: now,
        updatedBy: '   ',
      );
      expect(profile.validate, throwsFormatException);
    });

    test('11. LandUseProfile rejects blank notes when provided', () {
      final profile = LandUseProfile(
        parcelId: 'parcel-1',
        landUseType: LandUseType.agricultural,
        currentCondition: LandCondition.cultivated,
        clearingStatus: ClearingStatus.notRequired,
        readinessStatus: ReadinessStatus.ready,
        notes: '   ',
        updatedAt: now,
        updatedBy: 'member-1',
      );
      expect(profile.validate, throwsFormatException);
    });

    test('12. LandUseProfile rejects invalid schemaVersion', () {
      final profile = LandUseProfile(
        parcelId: 'parcel-1',
        landUseType: LandUseType.agricultural,
        currentCondition: LandCondition.cultivated,
        clearingStatus: ClearingStatus.notRequired,
        readinessStatus: ReadinessStatus.ready,
        updatedAt: now,
        updatedBy: 'member-1',
        schemaVersion: 0,
      );
      expect(profile.validate, throwsFormatException);
    });

    test('13. update LandUseProfile via application service', () async {
      await createParcel();

      final result = await UpdateLandUseProfile(application)(
        subject(),
        UpdateLandUseProfileCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 5)),
          landUseType: LandUseType.agricultural,
          currentCondition: LandCondition.cultivated,
          clearingStatus: ClearingStatus.notRequired,
          readinessStatus: ReadinessStatus.ready,
          notes: 'Cassava plot',
        ),
      );
      expect(result.isSuccess, isTrue);

      final stored = await surveys.getLandUseProfile('parcel-1');
      expect(stored, isNotNull);
      expect(stored!.landUseType, LandUseType.agricultural);
      expect(stored.currentCondition, LandCondition.cultivated);
      expect(stored.notes, 'Cassava plot');
    });

    test('14. LandUseProfile update does NOT create SpatialRevision',
        () async {
      await createParcel();
      final beforeCount = await countRevisions();

      final result = await UpdateLandUseProfile(application)(
        subject(),
        UpdateLandUseProfileCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 5)),
          landUseType: LandUseType.agricultural,
        ),
      );
      expect(result.isSuccess, isTrue);

      final afterCount = await countRevisions();
      expect(afterCount, beforeCount);
    });
  });

  // ============================================================
  // D4 — Metadata contract
  // ============================================================
  group('Sprint 11 — D4 Metadata contract', () {
    test('15. update all five new fields via application', () async {
      await createParcel();

      final result = await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          ownerContact: '+856 20 333',
          countryCode: 'LA',
          provinceCode: 'SVK',
          districtCode: 'NONG',
          villageCode: 'TAKO',
        ),
      );
      expect(result.isSuccess, isTrue);

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.ownerContact, '+856 20 333');
      expect(stored.countryCode, 'LA');
      expect(stored.provinceCode, 'SVK');
      expect(stored.districtCode, 'NONG');
      expect(stored.villageCode, 'TAKO');
    });

    test('16. persistence round-trip preserves all five fields', () async {
      await createParcel();

      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          ownerContact: '+856 20 444',
          countryCode: 'LA',
          provinceCode: 'SVK',
          districtCode: 'NONG',
          villageCode: 'TAKO',
        ),
      );

      final reloaded =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(reloaded!.ownerContact, '+856 20 444');
      expect(reloaded.countryCode, 'LA');
      expect(reloaded.provinceCode, 'SVK');
      expect(reloaded.districtCode, 'NONG');
      expect(reloaded.villageCode, 'TAKO');
    });

    test('17. null semantics — omitted fields not touched', () async {
      await createParcel(
        ownerContact: '+856 20 555',
      );
      // Manually set admin codes via first update
      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 5)),
          countryCode: 'LA',
          provinceCode: 'SVK',
        ),
      );

      // Second update omitting all fields — must NOT clear existing ones
      final result = await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          name: 'Renamed',
        ),
      );
      expect(result.isSuccess, isTrue);

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored!.name, 'Renamed');
      expect(stored.ownerContact, '+856 20 555'); // preserved
      expect(stored.countryCode, 'LA'); // preserved
      expect(stored.provinceCode, 'SVK'); // preserved
    });

    test('18. metadata update does not create SpatialRevision', () async {
      await createParcel();
      final beforeCount = await countRevisions();

      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          name: 'Renamed',
          ownerContact: '+856 20 666',
          countryCode: 'LA',
        ),
      );

      final afterCount = await countRevisions();
      expect(afterCount, beforeCount);
    });
  });

  // ============================================================
  // Identity — CRITICAL
  // ============================================================
  group('Sprint 11 — Identity safety', () {
    test('19. updateMetadata preserves existing spatialFeatureId',
        () async {
      final parcel = await createParcel();
      final originalFeatureId = parcel.spatialFeatureId!;
      expect(originalFeatureId, isNotEmpty);

      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          name: 'Renamed',
          ownerContact: '+856 20 777',
        ),
      );

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored, isNotNull);
      expect(stored!.spatialFeatureId, originalFeatureId);
    });

    test('20. bootstrap + metadata update preserves identity', () async {
      // Seed legacy parcel (no workflow) to simulate bootstrap scenario.
      final legacyParcel = LandParcel.create(
        id: 'legacy-parcel',
        farmId: 'farm-1',
        parcelCode: 'P-LEGACY',
        name: 'Legacy',
        boundary: Wgs84Polygon.fromVertices(vertices),
        boundarySource: BoundarySource.manual,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: now,
      );
      await parcels.create(legacyParcel);

      // Bootstrap via workflow
      final workflow = LandParcelSpatialSyncWorkflow(
        transaction: LandParcelSpatialTransaction(database),
        projection: const DefaultLandParcelSpatialProjection(),
        identityGenerator: DefaultSpatialIdentityGenerator(),
      );
      await workflow.bootstrapExisting(
        farmId: 'farm-1',
        landParcelId: 'legacy-parcel',
        temporalState: SpatialTemporalState.baseline,
      );

      final afterBootstrap =
          await parcels.getById(farmId: 'farm-1', id: 'legacy-parcel');
      final X = afterBootstrap!.spatialFeatureId!;
      expect(X, isNotEmpty);

      // Metadata update
      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'legacy-parcel',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          name: 'Renamed after bootstrap',
        ),
      );

      final afterUpdate =
          await parcels.getById(farmId: 'farm-1', id: 'legacy-parcel');
      expect(afterUpdate!.spatialFeatureId, X);
    });

    test('21. rehydrate + metadata update + reload preserves X', () async {
      final parcel = await createParcel();
      final X = parcel.spatialFeatureId!;

      await UpdateLandParcelMetadata(application)(
        subject(),
        UpdateLandParcelMetadataCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
          ownerContact: '+856 20 888',
        ),
      );

      final reloaded =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(reloaded!.spatialFeatureId, X);
    });

    test('22. verifyBoundary preserves spatialFeatureId', () async {
      final parcel = await createParcel();
      final X = parcel.spatialFeatureId!;

      await VerifyBoundary(application)(
        subject(),
        VerifyBoundaryCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          status: BoundaryVerificationStatus.verified,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 10)),
        ),
      );

      final stored =
          await parcels.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored!.spatialFeatureId, X);
    });

    test('23. assignSpatialFeatureId remains identity-specific', () {
      final parcel = LandParcel.create(
        id: 'p-assign',
        farmId: 'farm-1',
        parcelCode: 'P-ASSIGN',
        name: 'Assign test',
        boundary: Wgs84Polygon.fromVertices(vertices),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: now,
      );
      expect(parcel.spatialFeatureId, isNull);

      final assigned = parcel.assignSpatialFeatureId('SPF-X');
      expect(assigned.spatialFeatureId, 'SPF-X');

      // Idempotent
      final again = assigned.assignSpatialFeatureId('SPF-X');
      expect(again.spatialFeatureId, 'SPF-X');

      // Different → reject
      expect(
        () => assigned.assignSpatialFeatureId('SPF-Y'),
        throwsStateError,
      );

      // Blank → reject
      expect(
        () => assigned.assignSpatialFeatureId('   '),
        throwsFormatException,
      );
    });
  });
}