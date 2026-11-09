import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_subdivision_plan.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_production_parcel_number_allocator.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/core/spatial/data/spatial_persistence_composition.dart';
import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';
import 'dart:convert';
import '../../../core/spatial/support/scripted_spatial_identity_generator.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_boundary_consistency_queries.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_polygon.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
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
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';

void main() {
  sqfliteFfiInit();

  final createdAt = DateTime.utc(2026, 9, 11, 8);

  LandParcel createParcel({
    String id = 'parcel-1',
    String code = 'P-001',
    String? spatialFeatureId,
    String? ownerHouseholdId,
    double offset = 0,
  }) {
    return LandParcel.create(
      id: id,
      farmId: 'farm-1',
      parcelCode: code,
      name: 'Parcel $id',
      ownerHouseholdId: ownerHouseholdId,
      projectId: 'PROJ-A',
      boundary: Wgs84Polygon.fromVertices([
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7000 + offset),
        Wgs84Vertex(latitude: 16.5000, longitude: 104.7010 + offset),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7010 + offset),
        Wgs84Vertex(latitude: 16.5010, longitude: 104.7000 + offset),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
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
    await SqliteLandSurveyRepository.createSchema(database);
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

  LandParcel plotDraft(
    String id, {
    double offset = 0,
    String farmId = 'farm-1',
    String projectId = 'PROJ-A',
    ParcelLayer kind = ParcelLayer.landBlock,
  }) => LandParcel.create(
    id: id,
    farmId: farmId,
    parcelCode: 'DRAFT',
    name: 'ThÃ¡Â»Â­a $id',
    projectId: projectId,
    kind: kind,
    boundary: Wgs84Polygon.fromVertices([
      Wgs84Vertex(latitude: 16.5001, longitude: 104.7001 + offset),
      Wgs84Vertex(latitude: 16.5001, longitude: 104.7003 + offset),
      Wgs84Vertex(latitude: 16.5003, longitude: 104.7003 + offset),
      Wgs84Vertex(latitude: 16.5003, longitude: 104.7001 + offset),
    ]),
    boundarySource: BoundarySource.manual,
    verificationStatus: BoundaryVerificationStatus.draft,
    actorMembershipId: 'member-1',
    occurredAt: createdAt,
  );

  test(
    'production batch saves shared-edge plots crops and land use without changing parent',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final parent = await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      final saved = await workflow.createProductionFieldPlots(
        drafts: [plotDraft('batch-1'), plotDraft('batch-2', offset: 0.0002)],
        parentLandBlockId: parent.id,
        expectedParentBoundaryVersion: parent.boundaryVersion,
        temporalState: SpatialTemporalState.underConstruction,
        details: const [
          ParcelSketchDetails(
            cropType: 'Peanut',
            cropQuantity: 10,
            cropUnit: 'plants',
          ),
          ParcelSketchDetails(),
        ],
      );
      expect(saved.map((p) => p.parcelCode).toList(), [
        'AGR-NONG-T001',
        'AGR-NONG-T002',
      ]);
      final surveys = SqliteLandSurveyRepository(database);
      expect((await surveys.listCrops('batch-1')).single.cropType, 'Peanut');
      expect(await surveys.getLandUseProfile('batch-2'), isNotNull);
      for (final plot in saved) {
        final persisted = (await parcels.getById(
          farmId: 'farm-1',
          id: plot.id,
        ))!;
        expect(persisted.parentLandBlockId, parent.id);
        expect(
          await LandParcelBoundaryConsistencyQueries(
            links: links,
            features: spatial.featureRepository,
            revisions: spatial.revisionRepository,
          ).check(persisted),
          LandParcelBoundaryConsistency.consistent,
        );
      }
      final unchanged = (await parcels.getById(
        farmId: 'farm-1',
        id: parent.id,
      ))!;
      expect(unchanged.active, isTrue);
      expect(unchanged.boundaryVersion, parent.boundaryVersion);
      expect(unchanged.boundary, parent.boundary);
      expect(
        saved.fold<double>(0, (sum, p) => sum + p.areaM2),
        lessThan(parent.areaM2),
      );
    },
  );

  test(
    'overlap in later batch member rolls back all plots links and numbers',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final parent = await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      await expectLater(
        workflow.createProductionFieldPlots(
          drafts: [plotDraft('batch-1'), plotDraft('batch-2', offset: 0.0001)],
          parentLandBlockId: parent.id,
          expectedParentBoundaryVersion: parent.boundaryVersion,
          temporalState: SpatialTemporalState.underConstruction,
          details: const [ParcelSketchDetails(), ParcelSketchDetails()],
        ),
        throwsFormatException,
      );
      for (final id in ['batch-1', 'batch-2']) {
        expect(await parcels.getById(farmId: 'farm-1', id: id), isNull);
        expect(await links.findByLandParcelId(id), isNull);
      }
      final saved = await workflow.createProductionFieldPlot(
        draft: plotDraft('retry'),
        parentLandBlockId: parent.id,
        expectedParentBoundaryVersion: parent.boundaryVersion,
        temporalState: SpatialTemporalState.underConstruction,
      );
      expect(saved.parcelCode, 'AGR-NONG-T001');
    },
  );

  test(
    'standalone production field plot receives project code without parent',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);

      final saved = await workflow.createProductionStandaloneFieldPlot(
        draft: plotDraft(
          'standalone-1',
          projectId: 'agrico-nong',
          kind: ParcelLayer.fieldPlot,
        ),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.underConstruction,
      );

      expect(saved.parcelCode, 'AGR-NONG-T001');
      expect(saved.layer, ParcelLayer.fieldPlot);
      expect(saved.parentLandBlockId, isNull);
      expect(saved.projectId, 'agrico-nong');

      final persisted = await parcels.getById(farmId: 'farm-1', id: saved.id);
      expect(persisted, isNotNull);
      expect(persisted!.parcelCode, 'AGR-NONG-T001');
      expect(persisted.layer, ParcelLayer.fieldPlot);
      expect(persisted.parentLandBlockId, isNull);
      expect(persisted.projectId, 'agrico-nong');

      expect(
        await LandParcelBoundaryConsistencyQueries(
          links: links,
          features: spatial.featureRepository,
          revisions: spatial.revisionRepository,
        ).check(persisted),
        LandParcelBoundaryConsistency.consistent,
      );
    },
  );

  test(
    'production field plot saves its parent and spatial link with partial coverage',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final parent = await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      final plot = await workflow.createProductionFieldPlot(
        draft: plotDraft('plot-1'),
        parentLandBlockId: parent.id,
        expectedParentBoundaryVersion: parent.boundaryVersion,
        temporalState: SpatialTemporalState.underConstruction,
      );
      expect(plot.parcelCode, 'AGR-NONG-T001');
      expect(plot.layer, ParcelLayer.fieldPlot);
      expect(plot.parentLandBlockId, parent.id);
      expect(plot.areaM2, lessThan(parent.areaM2));
      final persisted = (await parcels.getById(farmId: 'farm-1', id: plot.id))!;
      expect(persisted.parentLandBlockId, parent.id);
      expect(
        await LandParcelBoundaryConsistencyQueries(
          links: links,
          features: spatial.featureRepository,
          revisions: spatial.revisionRepository,
        ).check(persisted),
        LandParcelBoundaryConsistency.consistent,
      );
      final unchanged = (await parcels.getById(
        farmId: 'farm-1',
        id: parent.id,
      ))!;
      expect(unchanged.boundary, parent.boundary);
      expect(unchanged.boundaryVersion, parent.boundaryVersion);
      expect(unchanged.areaM2, parent.areaM2);
    },
  );

  test(
    'invalid plot placement or parent does not consume a plot number',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final parent = await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      Future<LandParcel> save(
        LandParcel draft, {
        int version = 1,
        String? parentId,
      }) => workflow.createProductionFieldPlot(
        draft: draft,
        parentLandBlockId: parentId ?? parent.id,
        expectedParentBoundaryVersion: version,
        temporalState: SpatialTemporalState.underConstruction,
      );
      await save(plotDraft('plot-1'));
      await expectLater(save(plotDraft('overlap')), throwsFormatException);
      await expectLater(
        save(plotDraft('outside', offset: .001)),
        throwsFormatException,
      );
      await expectLater(
        save(plotDraft('other-farm', farmId: 'farm-2')),
        throwsStateError,
      );
      await expectLater(save(plotDraft('stale'), version: 2), throwsStateError);
      await expectLater(
        save(plotDraft('nested'), parentId: 'plot-1'),
        throwsStateError,
      );
      await expectLater(
        save(plotDraft('plot-1', offset: .0002)),
        throwsA(isA<DatabaseException>()),
      );
      final next = await save(plotDraft('plot-2', offset: .0002));
      expect(next.parcelCode, 'AGR-NONG-T002');
      expect(await database.query('land_parcels'), hasLength(3));
      expect(await database.query('land_parcel_spatial_links'), hasLength(3));
    },
  );

  test(
    'production block code and spatial projection save without village or household',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final saved = await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      expect(saved.parcelCode, 'AGR-NONG-L001');
      expect(saved.villageCode, isNull);
      expect(saved.ownerHouseholdId, isNull);
      expect(saved.layer, ParcelLayer.landBlock);
      final persisted = await parcels.getById(farmId: 'farm-1', id: saved.id);
      final link = await links.findByLandParcelId(saved.id);
      expect(persisted!.spatialFeatureId, link!.spatialFeatureId);
      expect(
        await LandParcelBoundaryConsistencyQueries(
          links: links,
          features: spatial.featureRepository,
          revisions: spatial.revisionRepository,
        ).check(persisted),
        LandParcelBoundaryConsistency.consistent,
      );
      expect(await database.query('households'), isEmpty);
    },
  );

  test(
    'failed production block creation rolls back allocated number and spatial writes',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      await workflow.createProductionLandBlock(
        draft: createParcel(),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      // Disjoint geometry so the block-on-block guard does not fire, but
      // reuse the same parcel_code so the DB unique (farm_id, parcel_code)
      // constraint throws after numbering and spatial writes happen.
      await expectLater(
        workflow.createProductionLandBlock(
          draft: createParcel(offset: 0.01),
          projectCode: 'AGR-NONG',
          temporalState: SpatialTemporalState.baseline,
        ),
        throwsA(isA<DatabaseException>()),
      );
      final next = await workflow.createProductionLandBlock(
        draft: createParcel(id: 'parcel-2', code: 'P-002', offset: 0.02),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      expect(next.parcelCode, 'AGR-NONG-L002');
      expect(await database.query('land_parcels'), hasLength(2));
      expect(await database.query('land_parcel_spatial_links'), hasLength(2));
    },
  );

  test(
    'prepared household and numbered parcel share the spatial transaction',
    () async {
      await SqliteParcelNumberSequence.createSchema(database);
      final numbers = SqliteParcelNumberSequence();
      final saved = await workflow.createPrepared(
        temporalState: SpatialTemporalState.baseline,
        prepare: (tx, surveys) => numbers.saveHousehold(
          tx: tx,
          farmId: 'farm-1',
          save: (houseCode) async {
            await surveys.createHousehold(
              Household(
                id: 'household-1',
                farmId: 'farm-1',
                householdCode: houseCode,
                headOfHouseholdName: 'Ã ÂºÂªÃ ÂºÂ»Ã ÂºÂ¡Ã ÂºÅ¾Ã ÂºÂ­Ã Âºâ„¢',
                administrativeLocation: const AdministrativeLocation(
                  countryName: 'LÃƒÂ o',
                  countryCode: 'LA',
                  provinceName: 'Savannakhet',
                  provinceCode: 'SVK',
                  districtName: 'Nong',
                  districtCode: 'NONG',
                  villageName: 'Ta Ko',
                  villageCode: 'TAKO',
                ),
                active: true,
                createdAt: createdAt,
                createdBy: 'member-1',
                updatedAt: createdAt,
                updatedBy: 'member-1',
              ),
            );
            return numbers.saveParcel(
              tx: tx,
              farmId: 'farm-1',
              villageId: 'village-tako',
              householdNumber: int.parse(houseCode.substring(1)),
              countryCode: 'LA',
              provinceCode: 'SVK',
              districtCode: 'NONG',
              villageCode: 'TAKO',
              save: (code) async =>
                  createParcel(code: code, ownerHouseholdId: 'household-1'),
            );
          },
        ),
      );
      expect(saved.parcelCode, 'LA-SVK-NONG-TAKO-H00001-001');
      expect(saved.spatialFeatureId, isNotNull);
      expect(
        (await parcels.getById(farmId: 'farm-1', id: saved.id))!.parcelCode,
        saved.parcelCode,
      );
      expect(
        (await SqliteLandSurveyRepository(
          database,
        ).getHousehold('household-1'))!.householdCode,
        'H00001',
      );
      expect(saved.ownerHouseholdId, 'household-1');
      expect(await links.findByLandParcelId(saved.id), isNotNull);
    },
  );

  test(
    'application generates household and parcel codes and reuses the household',
    () async {
      await SqliteParcelNumberSequence.createSchema(database);
      final subject = AuthorizationSubject(
        userId: 'user-1',
        membershipId: 'member-1',
        farmId: 'farm-1',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      final application = LandParcelApplicationService(
        repository: parcels,
        spatialWorkflow: workflow,
      );
      CreateLandParcelCommand command(String id, {String? householdId}) =>
          CreateLandParcelCommand(
            id: id,
            farmId: 'farm-1',
            parcelCode: '',
            name: id,
            vertices: createParcel().boundary.vertices.toList(),
            source: BoundarySource.manual,
            actorMembershipId: 'member-1',
            occurredAt: createdAt,
            autoNumber: true,
            villageId: 'village-tako',
            ownerHouseholdId: householdId,
            ownerDisplayName: 'Somphon',
            countryCode: 'LA',
            provinceCode: 'SVK',
            districtCode: 'NONG',
            villageCode: 'TAKO',
            legacyMetadata: const {
              'country': 'LÃƒÂ o',
              'province': 'Savannakhet',
              'district': 'Nong',
              'village': 'Ta Ko',
            },
          );
      final first = await application.createLandParcel(
        subject,
        command('first'),
      );
      expect(first.isSuccess, isTrue);
      expect(first.value!.parcelCode, 'LA-SVK-NONG-TAKO-H00001-001');
      final householdId = first.value!.ownerHouseholdId!;
      expect(
        (await SqliteLandSurveyRepository(
          database,
        ).getHousehold(householdId))!.householdCode,
        'H00001',
      );

      final second = await application.createLandParcel(
        subject,
        command('second', householdId: householdId),
      );
      expect(second.isSuccess, isTrue);
      expect(second.value!.parcelCode, 'LA-SVK-NONG-TAKO-H00001-002');
      expect(second.value!.ownerHouseholdId, householdId);
      expect(
        await SqliteLandSurveyRepository(database).listHouseholds('farm-1'),
        hasLength(1),
      );

      final third = await application.createLandParcel(
        subject,
        command('third'),
      );
      expect(third.isSuccess, isTrue);
      expect(third.value!.parcelCode, 'LA-SVK-NONG-TAKO-H00002-001');
    },
  );

  test(
    'failed automatic parcel save does not consume household or parcel number',
    () async {
      await SqliteParcelNumberSequence.createSchema(database);
      final subject = AuthorizationSubject(
        userId: 'user-1',
        membershipId: 'member-1',
        farmId: 'farm-1',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      final application = LandParcelApplicationService(
        repository: parcels,
        spatialWorkflow: workflow,
      );
      CreateLandParcelCommand command(String id, {String? householdId}) =>
          CreateLandParcelCommand(
            id: id,
            farmId: 'farm-1',
            parcelCode: '',
            name: id,
            vertices: createParcel().boundary.vertices.toList(),
            source: BoundarySource.manual,
            actorMembershipId: 'member-1',
            occurredAt: createdAt,
            autoNumber: true,
            villageId: 'village-tako',
            ownerHouseholdId: householdId,
            ownerDisplayName: 'Somphon',
            countryCode: 'LA',
            provinceCode: 'SVK',
            districtCode: 'NONG',
            villageCode: 'TAKO',
            legacyMetadata: const {
              'country': 'LÃƒÂ o',
              'province': 'Savannakhet',
              'district': 'Nong',
              'village': 'Ta Ko',
            },
          );

      // A legacy row with this ID causes the parcel insert to fail after the
      // new household and both numbers have been prepared.
      await parcels.create(createParcel(id: 'collision', code: 'LEGACY-001'));
      final failedHousehold = await application.createLandParcel(
        subject,
        command('collision'),
      );
      expect(failedHousehold.isSuccess, isFalse);
      expect(
        await SqliteLandSurveyRepository(database).listHouseholds('farm-1'),
        isEmpty,
      );
      expect(
        (await parcels.getById(farmId: 'farm-1', id: 'collision'))!.parcelCode,
        'LEGACY-001',
      );

      final first = await application.createLandParcel(
        subject,
        command('first'),
      );
      expect(first.isSuccess, isTrue);
      expect(first.value!.parcelCode, 'LA-SVK-NONG-TAKO-H00001-001');
      final householdId = first.value!.ownerHouseholdId!;

      final failedParcel = await application.createLandParcel(
        subject,
        command('first', householdId: householdId),
      );
      expect(failedParcel.isSuccess, isFalse);
      expect(
        (await SqliteLandSurveyRepository(database).listHouseholds('farm-1')),
        hasLength(1),
      );

      final next = await application.createLandParcel(
        subject,
        command('second', householdId: householdId),
      );
      expect(next.isSuccess, isTrue);
      expect(next.value!.parcelCode, 'LA-SVK-NONG-TAKO-H00001-002');
      expect(next.value!.ownerHouseholdId, householdId);
    },
  );

  test('land-only parcel allocates without creating household', () async {
    await SqliteParcelNumberSequence.createSchema(database);
    final subject = AuthorizationSubject(
      userId: 'user-1',
      membershipId: 'member-1',
      farmId: 'farm-1',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.allFarm},
    );
    final application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: workflow,
    );
    Future<LandParcelApplicationResult<LandParcel>> create(String id) =>
        application.createLandParcel(
          subject,
          CreateLandParcelCommand(
            id: id,
            farmId: 'farm-1',
            parcelCode: '',
            name: id,
            vertices: createParcel().boundary.vertices.toList(),
            source: BoundarySource.manual,
            actorMembershipId: 'member-1',
            occurredAt: createdAt,
            autoNumber: true,
            villageId: 'village-tako',
            countryCode: 'LA',
            provinceCode: 'SVK',
            districtCode: 'NONG',
            villageCode: 'TAKO',
            legacyMetadata: const {'village': 'Ta Ko'},
          ),
        );
    expect(
      (await create('first')).value!.parcelCode,
      'LA-SVK-NONG-TAKO-L00001',
    );
    expect(
      (await create('second')).value!.parcelCode,
      'LA-SVK-NONG-TAKO-L00002',
    );
    expect(
      await SqliteLandSurveyRepository(database).listHouseholds('farm-1'),
      isEmpty,
    );
    expect(
      (await parcels.getById(farmId: 'farm-1', id: 'first'))!.ownerHouseholdId,
      isNull,
    );
  });

  test(
    'production block rejects crops before numbering or spatial writes',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      final first = createParcel();
      CropRecord crop(String parcelId) => CropRecord(
        id: 'fixed-crop',
        parcelId: parcelId,
        cropType: 'Peanut',
        quantity: 2,
        unit: 'plants',
        condition: CropCondition.unknown,
        active: true,
        createdAt: createdAt,
        updatedAt: createdAt,
        createdBy: 'member-1',
        updatedBy: 'member-1',
      );
      // The workflow rejects crops on a production block before numbering
      // or spatial writes happen.
      await expectLater(
        () => workflow.createProductionLandBlock(
          draft: first,
          projectCode: 'AGR-NONG',
          temporalState: SpatialTemporalState.baseline,
          crops: [crop(first.id)],
        ),
        throwsFormatException,
      );
      expect(await parcels.getById(farmId: 'farm-1', id: first.id), isNull);
      expect(await links.findByLandParcelId(first.id), isNull);
      expect(
        await database.query('agrico_production_parcel_sequences_v4'),
        isEmpty,
      );
    },
  );

  test('new parcel and crop commit together or both roll back', () async {
    final surveys = SqliteLandSurveyRepository(database);
    final subject = AuthorizationSubject(
      userId: 'user-1',
      membershipId: 'member-1',
      farmId: 'farm-1',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.allFarm},
    );
    final application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: workflow,
    );
    final draft = CropRecord(
      id: 'draft-crop',
      parcelId: 'draft',
      cropType: 'Ã ÂºÂ¡Ã ÂºÂ±Ã Âºâ„¢Ã Âºâ€¢Ã ÂºÂ»Ã Â»â€°Ã Âºâ„¢',
      ageMonths: 18,
      quantity: 12,
      unit: 'plants',
      condition: CropCondition.unknown,
      active: true,
      createdAt: createdAt,
      createdBy: 'draft',
      updatedAt: createdAt,
      updatedBy: 'draft',
    );
    CreateLandParcelCommand command(String id) => CreateLandParcelCommand(
      id: id,
      farmId: 'farm-1',
      parcelCode: id,
      name: id,
      vertices: createParcel().boundary.vertices.toList(),
      source: BoundarySource.manual,
      actorMembershipId: 'member-1',
      occurredAt: createdAt,
      crops: [draft],
    );

    final saved = await application.createLandParcel(
      subject,
      command('with-crop'),
    );
    expect(saved.isSuccess, isTrue);
    final crops = await surveys.listCrops('with-crop');
    expect(crops, hasLength(1));
    expect(
      crops.single.cropType,
      'Ã ÂºÂ¡Ã ÂºÂ±Ã Âºâ„¢Ã Âºâ€¢Ã ÂºÂ»Ã Â»â€°Ã Âºâ„¢',
    );
    expect(crops.single.ageMonths, 18);
    expect(crops.single.parcelId, 'with-crop');
    expect(crops.single.createdBy, 'member-1');
    expect(
      (await parcels.getById(
        farmId: 'farm-1',
        id: 'with-crop',
      ))!.spatialFeatureId,
      isNotNull,
    );

    await database.execute('''CREATE TRIGGER reject_crop BEFORE INSERT ON
      ${SqliteLandSurveyRepository.cropsTable} BEGIN
      SELECT RAISE(ABORT, 'crop write failed'); END''');
    final failed = await application.createLandParcel(
      subject,
      command('rollback'),
    );
    expect(failed.status, LandParcelApplicationStatus.persistenceFailed);
    expect(await parcels.getById(farmId: 'farm-1', id: 'rollback'), isNull);
    expect(await links.findByLandParcelId('rollback'), isNull);
    expect(await surveys.listCrops('rollback'), isEmpty);
  });

  test(
    'editing crop type preserves parcel boundary and spatial revisions',
    () async {
      final parcel = createParcel(spatialFeatureId: 'feature-edit-crop');
      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );
      final surveys = SqliteLandSurveyRepository(database);
      CropRecord crop(String id, String type, {int? ageMonths}) => CropRecord(
        id: id,
        parcelId: parcel.id,
        cropType: type,
        ageMonths: ageMonths,
        quantity: 12,
        unit: 'plants',
        condition: CropCondition.unknown,
        active: true,
        createdAt: createdAt,
        createdBy: 'member-1',
        updatedAt: createdAt,
        updatedBy: 'member-1',
      );
      await surveys.createCrop(
        crop('crop-existing', 'Ã ÂºÂ¡Ã ÂºÂ±Ã Âºâ„¢Ã Âºâ€¢Ã ÂºÂ»Ã Â»â€°Ã Âºâ„¢'),
      );
      final before = (await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      ))!;
      final revisions = await spatial.revisionRepository.findByFeatureId(
        'feature-edit-crop',
      );
      final application = LandParcelApplicationService(
        repository: parcels,
        spatialWorkflow: workflow,
      );
      final subject = AuthorizationSubject(
        userId: 'user-1',
        membershipId: 'member-1',
        farmId: parcel.farmId,
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      UpdateLandParcelMetadataCommand command(List<CropRecord> crops) =>
          UpdateLandParcelMetadataCommand(
            farmId: parcel.farmId,
            parcelId: parcel.id,
            actorMembershipId: 'member-1',
            occurredAt: createdAt.add(const Duration(days: 1)),
            name: 'Changed crop parcel',
            crops: crops,
          );

      final result = await application.updateLandParcelMetadata(
        subject,
        command([
          crop(
            'crop-existing',
            'Ã ÂºÂ¢Ã ÂºÂ²Ã Âºâ€¡Ã ÂºÅ¾Ã ÂºÂ²Ã ÂºÂ¥Ã ÂºÂ²',
            ageMonths: 42,
          ),
        ]),
      );
      expect(result.isSuccess, isTrue);
      expect(
        (await surveys.listCrops(parcel.id)).single.cropType,
        'Ã ÂºÂ¢Ã ÂºÂ²Ã Âºâ€¡Ã ÂºÅ¾Ã ÂºÂ²Ã ÂºÂ¥Ã ÂºÂ²',
      );
      expect((await surveys.listCrops(parcel.id)).single.ageMonths, 42);
      final after = (await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      ))!;
      expect(after.boundary, before.boundary);
      expect(after.boundaryVersion, before.boundaryVersion);
      expect(
        after.boundaryHistory.map((v) => v.id),
        before.boundaryHistory.map((v) => v.id),
      );
      expect(
        (await spatial.revisionRepository.findByFeatureId(
          'feature-edit-crop',
        )).map((v) => v.id),
        revisions.map((v) => v.id),
      );

      final rejected = await application.updateLandParcelMetadata(
        subject,
        UpdateLandParcelMetadataCommand(
          farmId: parcel.farmId,
          parcelId: parcel.id,
          actorMembershipId: 'member-1',
          occurredAt: createdAt.add(const Duration(days: 2)),
          name: 'Must roll back',
          crops: [crop('crop-from-another-parcel', 'invalid')],
        ),
      );
      expect(rejected.status, LandParcelApplicationStatus.validationFailed);
      expect(
        (await surveys.listCrops(parcel.id)).single.cropType,
        'Ã ÂºÂ¢Ã ÂºÂ²Ã Âºâ€¡Ã ÂºÅ¾Ã ÂºÂ²Ã ÂºÂ¥Ã ÂºÂ²',
      );
      expect(
        (await parcels.getById(farmId: parcel.farmId, id: parcel.id))!.name,
        'Changed crop parcel',
      );
    },
  );

  test(
    'legacy unlinked parcel may edit crops without creating a spatial link',
    () async {
      final parcel = createParcel(id: 'legacy-crops', code: 'P-LEGACY-CROP');
      await parcels.create(parcel);
      final surveys = SqliteLandSurveyRepository(database);
      await surveys.createCrop(
        CropRecord(
          id: 'legacy-crop',
          parcelId: parcel.id,
          cropType: 'Cassava',
          quantity: 10,
          unit: 'plants',
          condition: CropCondition.unknown,
          active: true,
          createdAt: createdAt,
          createdBy: 'member-1',
          updatedAt: createdAt,
          updatedBy: 'member-1',
        ),
      );
      final result =
          await LandParcelApplicationService(
            repository: parcels,
            spatialWorkflow: workflow,
          ).updateLandParcelMetadata(
            AuthorizationSubject(
              userId: 'user-1',
              membershipId: 'member-1',
              farmId: parcel.farmId,
              permissionCodes: PermissionCodes.values,
              dataScopes: const {DataScope.allFarm},
            ),
            UpdateLandParcelMetadataCommand(
              farmId: parcel.farmId,
              parcelId: parcel.id,
              actorMembershipId: 'member-1',
              occurredAt: createdAt.add(const Duration(days: 1)),
              crops: [
                CropRecord(
                  id: 'legacy-crop',
                  parcelId: parcel.id,
                  cropType: 'Rubber',
                  quantity: 10,
                  unit: 'plants',
                  condition: CropCondition.unknown,
                  active: true,
                  createdAt: createdAt,
                  createdBy: 'member-1',
                  updatedAt: createdAt,
                  updatedBy: 'member-1',
                ),
              ],
            ),
          );
      expect(result.isSuccess, isTrue);
      expect((await surveys.listCrops(parcel.id)).single.cropType, 'Rubber');
      expect(await links.findByLandParcelId(parcel.id), isNull);
      expect(
        (await parcels.getById(
          farmId: parcel.farmId,
          id: parcel.id,
        ))!.boundaryVersion,
        parcel.boundaryVersion,
      );
    },
  );

  Future<LandParcel> seedLegacyLinked() async {
    final parcel = createParcel(id: 'old-linked', code: 'P-OLD');
    await parcels.create(parcel);
    await workflow.createSpatialForParcelScoped(
      links: links,
      spatial: spatial,
      parcel: parcel,
      temporalState: SpatialTemporalState.operational,
      spatialLinkId: 'old-link',
      spatialFeatureId: 'old-feature',
      spatialRevisionId: 'old-revision',
    );
    return parcel;
  }

  test(
    'repairs only the parcel ID when persisted legacy geometry matches',
    () async {
      final parcel = await seedLegacyLinked();
      final before = await spatial.revisionRepository.findByFeatureId(
        'old-feature',
      );
      final repaired = await workflow.reconcileLegacySpatialIdentity(
        farmId: parcel.farmId,
        landParcelId: parcel.id,
      );
      final stored = (await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      ))!;
      expect(repaired.spatialFeatureId, 'old-feature');
      expect(stored.spatialFeatureId, 'old-feature');
      expect(stored.boundary, parcel.boundary);
      expect(
        stored.boundaryHistory.map((version) => version.id),
        parcel.boundaryHistory.map((version) => version.id),
      );
      final after = await spatial.revisionRepository.findByFeatureId(
        'old-feature',
      );
      expect(
        after.map((revision) => revision.id),
        before.map((revision) => revision.id),
      );
      expect(
        after.map((revision) => revision.revision),
        before.map((revision) => revision.revision),
      );
      expect(
        await LandParcelBoundaryConsistencyQueries(
          links: links,
          features: spatial.featureRepository,
          revisions: spatial.revisionRepository,
        ).check(stored),
        LandParcelBoundaryConsistency.consistent,
      );
    },
  );

  test(
    'refuses legacy repair when current revision points to another boundary',
    () async {
      final parcel = await seedLegacyLinked();
      final rows = await database.query(
        SqliteSpatialSchema.revisionsTable,
        where: 'feature_id = ?',
        whereArgs: ['old-feature'],
      );
      final payload =
          jsonDecode(rows.single['payload_json']! as String)
              as Map<String, dynamic>;
      payload['geometryReference'] = 'different-boundary';
      await database.update(
        SqliteSpatialSchema.revisionsTable,
        {
          'geometry_reference': 'different-boundary',
          'payload_json': jsonEncode(payload),
        },
        where: 'feature_id = ?',
        whereArgs: ['old-feature'],
      );
      final diagnosis = await LandParcelBoundaryConsistencyQueries(
        links: links,
        features: spatial.featureRepository,
        revisions: spatial.revisionRepository,
      ).diagnose(parcel);
      expect(
        diagnosis.consistency,
        LandParcelBoundaryConsistency.needsReconciliation,
      );
      expect(
        diagnosis.issue,
        LandParcelBoundaryIssue.boundaryReferenceMismatch,
      );
      await expectLater(
        workflow.reconcileLegacySpatialIdentity(
          farmId: parcel.farmId,
          landParcelId: parcel.id,
        ),
        throwsStateError,
      );
      final stored = await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      );
      expect(stored!.spatialFeatureId, isNull);
      expect(stored.boundary, parcel.boundary);
    },
  );

  test(
    'application gates legacy repair and restores KML export after success',
    () async {
      final parcel = await seedLegacyLinked();
      final queries = LandParcelBoundaryConsistencyQueries(
        links: links,
        features: spatial.featureRepository,
        revisions: spatial.revisionRepository,
      );
      expect(
        await queries.check(parcel),
        LandParcelBoundaryConsistency.repairableLegacyIdentity,
      );
      final application = LandParcelApplicationService(
        repository: parcels,
        spatialWorkflow: workflow,
        boundaryConsistencyQueries: queries,
      );
      AuthorizationSubject subject(Set<String> permissions) =>
          AuthorizationSubject(
            userId: 'user-1',
            membershipId: 'member-1',
            farmId: 'farm-1',
            permissionCodes: permissions,
            dataScopes: const {DataScope.allFarm},
          );
      final denied = await application.reconcileLegacySpatialIdentity(
        subject({PermissionCodes.fieldEdit}),
        farmId: parcel.farmId,
        parcelId: parcel.id,
      );
      expect(denied.status, LandParcelApplicationStatus.permissionDenied);
      expect(
        (await parcels.getById(
          farmId: parcel.farmId,
          id: parcel.id,
        ))!.spatialFeatureId,
        isNull,
      );
      final beforeExport = await application.exportKmlKmz(
        subject(PermissionCodes.values),
        farmId: parcel.farmId,
        parcelId: parcel.id,
        format: LandParcelInterchangeFormat.kml,
      );
      expect(beforeExport.status, LandParcelApplicationStatus.validationFailed);

      final success = await application.reconcileLegacySpatialIdentity(
        subject({
          PermissionCodes.fieldEdit,
          PermissionCodes.fieldBoundaryVerify,
        }),
        farmId: parcel.farmId,
        parcelId: parcel.id,
      );
      expect(success.isSuccess, isTrue);
      final after = (await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      ))!;
      expect(
        await queries.check(after),
        LandParcelBoundaryConsistency.consistent,
      );
      final afterExport = await application.exportKmlKmz(
        subject(PermissionCodes.values),
        farmId: parcel.farmId,
        parcelId: parcel.id,
        format: LandParcelInterchangeFormat.kml,
      );
      expect(afterExport.isSuccess, isTrue);
    },
  );

  test(
    'read diagnosis distinguishes unlinked, aligned and legacy missing geometry',
    () async {
      final queries = LandParcelBoundaryConsistencyQueries(
        links: links,
        features: spatial.featureRepository,
        revisions: spatial.revisionRepository,
      );
      final legacy = createParcel(id: 'legacy', code: 'P-LEGACY');
      await parcels.create(legacy);
      expect(
        await queries.check(legacy),
        LandParcelBoundaryConsistency.unlinked,
      );

      final oldLinked = await seedLegacyLinked();
      // Historical fixture: the link and feature exist, but the parcel payload
      // predates the stable ID assignment now enforced for new creations.
      final storedOld = (await parcels.getById(
        farmId: oldLinked.farmId,
        id: oldLinked.id,
      ))!;
      expect(
        await queries.check(storedOld),
        LandParcelBoundaryConsistency.repairableLegacyIdentity,
      );

      final generated = createParcel(id: 'generated', code: 'P-GEN');
      await workflow.create(
        parcel: generated,
        temporalState: SpatialTemporalState.operational,
      );
      final storedGenerated = (await parcels.getById(
        farmId: generated.farmId,
        id: generated.id,
      ))!;
      expect(storedGenerated.spatialFeatureId, isNotNull);
      expect(
        await queries.check(storedGenerated),
        LandParcelBoundaryConsistency.consistent,
      );

      final parcel = createParcel(spatialFeatureId: 'spatial-aligned');
      await workflow.create(
        parcel: parcel,
        temporalState: SpatialTemporalState.operational,
      );
      final stored = (await parcels.getById(
        farmId: parcel.farmId,
        id: parcel.id,
      ))!;
      expect(
        await queries.check(stored),
        LandParcelBoundaryConsistency.consistent,
      );

      final link = (await links.findByLandParcelId(parcel.id))!;
      final revisionRows = await database.query(
        SqliteSpatialSchema.revisionsTable,
        where: 'feature_id = ?',
        whereArgs: [link.spatialFeatureId],
      );
      final legacyPayload =
          jsonDecode(revisionRows.single['payload_json']! as String)
              as Map<String, dynamic>;
      legacyPayload['geometry'] = null;
      await database.update(
        SqliteSpatialSchema.revisionsTable,
        {'geometry_json': null, 'payload_json': jsonEncode(legacyPayload)},
        where: 'feature_id = ?',
        whereArgs: [link.spatialFeatureId],
      );
      final diagnosis = await queries.diagnose(stored);
      expect(
        diagnosis.consistency,
        LandParcelBoundaryConsistency.needsReconciliation,
      );
      expect(diagnosis.issue, LandParcelBoundaryIssue.invalidGeometry);

      final application = LandParcelApplicationService(
        repository: parcels,
        boundaryConsistencyQueries: queries,
      );
      final subject = AuthorizationSubject(
        userId: 'user-1',
        membershipId: 'member-1',
        farmId: 'farm-1',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      final denied = await application.exportKmlKmz(
        subject,
        farmId: 'farm-1',
        parcelId: parcel.id,
        format: LandParcelInterchangeFormat.kml,
      );
      expect(denied.status, LandParcelApplicationStatus.validationFailed);
      expect(denied.messageKey, 'boundary.reconciliation.required');
      final legacyExport = await application.exportKmlKmz(
        subject,
        farmId: 'farm-1',
        parcelId: legacy.id,
        format: LandParcelInterchangeFormat.kml,
      );
      expect(legacyExport.isSuccess, isTrue);
    },
  );

  Future<void> seedCorruptSpatialIdentity(LandParcel parcel) async {
    await parcels.create(createParcel(id: parcel.id, code: parcel.parcelCode));
    final rows = await database.query(
      SqliteLandParcelRepository.parcelTable,
      columns: ['payload_json'],
      where: 'id = ?',
      whereArgs: [parcel.id],
    );
    final payload =
        jsonDecode(rows.single['payload_json']! as String)
            as Map<String, dynamic>;
    payload['spatialFeatureId'] = parcel.spatialFeatureId;
    await database.update(
      SqliteLandParcelRepository.parcelTable,
      {'payload_json': jsonEncode(payload)},
      where: 'id = ?',
      whereArgs: [parcel.id],
    );
  }

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
      const X = 'SPF-WORKFLOW-003';
      final parcel = createParcel(spatialFeatureId: X);

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
      final feature = await spatial.featureRepository.findById(X);
      final revisions = await spatial.revisionRepository.findByFeatureId(X);

      expect(storedParcel!.name, 'Updated parcel');
      expect(feature!.name, 'Updated parcel');
      expect(revisions.map((revision) => revision.revision), [1, 2]);
    },
  );

  test(
    'update derives the next Spatial revision from persisted state',
    () async {
      const X = 'SPF-WORKFLOW-004';
      final parcel = createParcel(spatialFeatureId: X);

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

      final revisions = await spatial.revisionRepository.findByFeatureId(X);

      expect(revisions.map((revision) => revision.revision), [1, 2, 3]);
    },
  );

  test(
    'update fails when SpatialFeature does not exist and rolls back parcel',
    () async {
      const X = 'missing-spatial-feature';
      final parcel = createParcel(spatialFeatureId: X);
      await seedCorruptSpatialIdentity(parcel);

      // Deliberately model corrupted persisted state so the workflow reaches
      // its missing-feature guard instead of being stopped by SQLite first.
      await database.execute('PRAGMA foreign_keys = OFF');
      try {
        await links.create(
          LandParcelSpatialLink(
            id: 'link-to-missing-feature',
            landParcelId: parcel.id,
            spatialFeatureId: X,
            createdAt: createdAt,
            createdBy: 'member-1',
          ),
        );
      } finally {
        await database.execute('PRAGMA foreign_keys = ON');
      }

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
          prefix: 'spatial-revision',
          id: 'revision-shared',
        ),
        const ScriptedSpatialIdentity(
          prefix: 'spatial-revision',
          id: 'revision-shared',
        ),
      ]),
    );

    final parcel = createParcel(spatialFeatureId: 'feature-1');

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
      const X = 'spatial-road-1';
      // Sprint 12 fixture rule: identity must be internally consistent.
      // The ONLY intended invalid condition is featureType = road.
      final parcel = createParcel(spatialFeatureId: X);
      await seedCorruptSpatialIdentity(parcel);

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
      const X = 'SPF-SCOPED-ROLLBACK';
      final parcel = createParcel(
        id: 'scoped-update-rollback',
        code: 'SCOPED-UPDATE',
        spatialFeatureId: X,
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

      var updateCompleted = false;
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
          updateCompleted = true;

          throw StateError('force outer rollback');
        }),
        throwsA(isA<StateError>()),
      );
      expect(updateCompleted, isTrue);

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
      const X = 'SPF-SCOPED-UPDATE';
      final parcel = createParcel(
        id: 'spatial-only-update',
        code: 'SPATIAL-ONLY-UPDATE',
        spatialFeatureId: X,
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

  test('production block rejects a NULL project candidate', () async {
    await SqliteProductionParcelNumberAllocator.createSchema(database);
    // A draft without a project id. Built directly rather than via the
    // shared helper, which always stamps PROJ-A.
    final draft = LandParcel.create(
      id: 'no-project',
      farmId: 'farm-1',
      parcelCode: 'P-NOP',
      name: 'Parcel no-project',
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
      projectId: null,
    );
    expect(
      () => workflow.createProductionLandBlock(
        draft: draft,
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      ),
      throwsFormatException,
    );
  });

  test(
    'production block rejects a candidate overlapping a NULL project block',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      // Existing block with NULL project and the same geometry as the
      // candidate. Raw fixture insert bypasses the workflow on purpose so
      // the guard is the only thing under test.
      await database.insert(SqliteLandParcelRepository.parcelTable, {
        'id': 'existing-null',
        'farm_id': 'farm-1',
        'parcel_code': 'P-NULL',
        'active': 1,
        'boundary_version': 1,
        'schema_version': 3,
        'payload_json': jsonEncode({
          'boundary': [
            {'latitude': 16.5000, 'longitude': 104.7000, 'altitudeM': null},
            {'latitude': 16.5000, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7000, 'altitudeM': null},
          ],
        }),
        'project_id': null,
        'kind': 'landBlock',
        'parent_block_id': null,
      });

      await expectLater(
        workflow.createProductionLandBlock(
          draft: createParcel(id: 'new', code: 'P-NEW'),
          projectCode: 'AGR-NONG',
          temporalState: SpatialTemporalState.baseline,
        ),
        throwsA(isA<StateError>()),
      );

      // Rollback: only the fixture block remains, no link, no counter.
      final parcelsRows = await database.query(
        SqliteLandParcelRepository.parcelTable,
      );
      expect(parcelsRows, hasLength(1));
      expect(parcelsRows.single['id'], 'existing-null');
      expect(
        await database.query('agrico_production_parcel_sequences_v4'),
        isEmpty,
      );
      expect(await database.query('land_parcel_spatial_links'), isEmpty);
    },
  );

  test(
    'production block rejects a candidate overlapping an X project block',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      // Existing block with X project and the same geometry.
      await database.insert(SqliteLandParcelRepository.parcelTable, {
        'id': 'existing-x',
        'farm_id': 'farm-1',
        'parcel_code': 'P-X',
        'active': 1,
        'boundary_version': 1,
        'schema_version': 3,
        'payload_json': jsonEncode({
          'boundary': [
            {'latitude': 16.5000, 'longitude': 104.7000, 'altitudeM': null},
            {'latitude': 16.5000, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7000, 'altitudeM': null},
          ],
        }),
        'project_id': 'PROJ-A',
        'kind': 'landBlock',
        'parent_block_id': null,
      });

      await expectLater(
        workflow.createProductionLandBlock(
          draft: createParcel(id: 'new', code: 'P-NEW'),
          projectCode: 'AGR-NONG',
          temporalState: SpatialTemporalState.baseline,
        ),
        throwsA(isA<StateError>()),
      );

      // Rollback: only the fixture block remains, no link, no counter.
      final parcelsRows = await database.query(
        SqliteLandParcelRepository.parcelTable,
      );
      expect(parcelsRows, hasLength(1));
      expect(parcelsRows.single['id'], 'existing-x');
      expect(
        await database.query('agrico_production_parcel_sequences_v4'),
        isEmpty,
      );
      expect(await database.query('land_parcel_spatial_links'), isEmpty);
    },
  );

  test(
    'production block allows a candidate overlapping a Y project block',
    () async {
      await SqliteProductionParcelNumberAllocator.createSchema(database);
      // Existing block with a different project Y and the same geometry.
      // The same geometry is allowed because projects are independent.
      await database.insert(SqliteLandParcelRepository.parcelTable, {
        'id': 'existing-y',
        'farm_id': 'farm-1',
        'parcel_code': 'P-Y',
        'active': 1,
        'boundary_version': 1,
        'schema_version': 3,
        'payload_json': jsonEncode({
          'boundary': [
            {'latitude': 16.5000, 'longitude': 104.7000, 'altitudeM': null},
            {'latitude': 16.5000, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7010, 'altitudeM': null},
            {'latitude': 16.5010, 'longitude': 104.7000, 'altitudeM': null},
          ],
        }),
        'project_id': 'PROJ-Y',
        'kind': 'landBlock',
        'parent_block_id': null,
      });

      final saved = await workflow.createProductionLandBlock(
        draft: createParcel(id: 'new', code: 'P-NEW'),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.baseline,
      );
      expect(saved.id, 'new');
      expect(saved.projectId, 'PROJ-A');
    },
  );
}
