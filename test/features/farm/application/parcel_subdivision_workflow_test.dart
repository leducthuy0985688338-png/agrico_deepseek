import 'dart:convert';

import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_subdivision_service.dart';
import 'package:agrico_deepseek/features/farm/application/production_parcel_creation_service.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/production_parcel_creation_repository.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_land_history_repository.dart';
import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/parcel_subdivision_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteLandParcelRepository parcels;
  late SqliteParcelLandHistoryRepository history;
  late LandParcelSpatialSyncWorkflow workflow;
  late ParcelSubdivisionService service;
  const subject = AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: {
      PermissionCodes.fieldView,
      PermissionCodes.fieldEdit,
      PermissionCodes.fieldCreate,
    },
    dataScopes: {DataScope.allFarm},
  );
  const cutA = Wgs84Vertex(latitude: 16, longitude: 106.001);
  const cutB = Wgs84Vertex(latitude: 16.001, longitude: 106.001);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(db);
    await SqliteLandSurveyRepository.createSchema(db);
    await SqliteSpatialSchema.createSchema(db);
    await SqliteLandParcelSpatialLinkRepository.createSchema(db);
    await SqliteParcelNumberSequence.createSchema(db);
    await SqliteParcelLandHistoryRepository.createSchema(db);
    await SqliteAdministrativeCatalog.createSchema(db);
    await SqliteAdministrativeCatalog(db).seedInitialLocation();
    parcels = SqliteLandParcelRepository(db);
    history = SqliteParcelLandHistoryRepository(db);
    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(db),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: SequentialSpatialIdentityGenerator(),
    );
    service = ParcelSubdivisionService(parcels: parcels, workflow: workflow);
    await workflow.create(
      parcel: LandParcel.create(
        id: 'source',
        farmId: 'farm',
        parcelCode: 'SOURCE',
        name: 'Nguồn',
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16, longitude: 106),
          Wgs84Vertex(latitude: 16, longitude: 106.002),
          Wgs84Vertex(latitude: 16.001, longitude: 106.002),
          Wgs84Vertex(latitude: 16.001, longitude: 106),
        ]),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member',
        occurredAt: DateTime.utc(2026, 9, 28),
        countryCode: 'LA',
        provinceCode: 'SVK',
        districtCode: 'NONG',
        villageCode: 'TAKO',
      ),
      temporalState: SpatialTemporalState.baseline,
    );
  });

  tearDown(() => db.close());

  Future<List<LandParcel>> save() => service.save(
    subject: subject,
    sourceParcelId: 'source',
    villageId: 'agrico-la-svk-nong-tako',
    expectedBoundaryVersion: 1,
    cutStart: cutA,
    cutEnd: cutB,
    firstName: 'Lô trái',
    secondName: 'Lô phải',
  );

  /// Replaces the source's project id through the shared transaction so
  /// the spatial-enabled update stays consistent with the persisted link.
  Future<void> assignSourceProject(String projectId) async {
    final current = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final updated = LandParcel.rehydrate(
      id: current.id,
      farmId: current.farmId,
      parcelCode: current.parcelCode,
      name: current.name,
      active: current.active,
      createdAt: current.createdAt,
      createdBy: current.createdBy,
      updatedAt: DateTime.utc(2026, 9, 29),
      updatedBy: 'member',
      schemaVersion: current.schemaVersion,
      boundary: current.boundary,
      centroid: current.centroid,
      areaM2: current.areaM2,
      perimeterM: current.perimeterM,
      boundarySource: current.boundarySource,
      verificationStatus: current.verificationStatus,
      boundaryVersion: current.boundaryVersion,
      boundaryHistory: current.boundaryHistory,
      legacyMetadata: current.legacyMetadata,
      spatialFeatureId: current.spatialFeatureId,
      countryCode: current.countryCode,
      provinceCode: current.provinceCode,
      districtCode: current.districtCode,
      villageCode: current.villageCode,
      projectId: projectId,
      kind: current.kind,
      parentBlockId: current.parentBlockId,
    );
    await workflow.update(
      parcel: updated,
      temporalState: SpatialTemporalState.baseline,
    );
  }

  /// Builds a complete fixture payload for a raw land_parcels insert.
  ///
  /// The mapper requires the full field set; a bare boundary would fail
  /// hydration during guard re-reads.
  Map<String, Object?> fixturePayload({
    required String id,
    required String code,
  }) => {
    'id': id,
    'farmId': 'farm',
    'parcelCode': code,
    'name': 'Fixture block',
    'active': true,
    'createdAt': '2026-09-30T00:00:00.000Z',
    'createdBy': 'member',
    'updatedAt': '2026-09-30T00:00:00.000Z',
    'updatedBy': 'member',
    'schemaVersion': 3,
    'boundary': [
      {'latitude': 16.0100, 'longitude': 106.0100, 'altitudeM': null},
      {'latitude': 16.0100, 'longitude': 106.0108, 'altitudeM': null},
      {'latitude': 16.0104, 'longitude': 106.0108, 'altitudeM': null},
      {'latitude': 16.0104, 'longitude': 106.0100, 'altitudeM': null},
    ],
    'centroid': {'latitude': 16.0102, 'longitude': 106.0104, 'altitudeM': null},
    'areaM2': 100.0,
    'areaHa': 0.01,
    'perimeterM': 40.0,
    'boundarySource': 'gps',
    'verificationStatus': 'measured',
    'boundaryVersion': 1,
    'legacyMetadata': <String, Object?>{},
  };

  /// Inserts a fixture block outside the source parcel, used only to
  /// exercise the candidate-vs-existing overlap guard.
  /// Inserts a fixture block outside the source parcel, used only to
  /// exercise the candidate-vs-existing overlap guard.
  ///
  /// The parcel row needs a matching boundary version row so the mapper
  /// can rehydrate it during the guard re-read.
  Future<void> insertFixtureBlock({
    required String id,
    required String code,
    required String? projectId,
  }) async {
    await db.insert(SqliteLandParcelRepository.parcelTable, {
      'id': id,
      'farm_id': 'farm',
      'parcel_code': code,
      'active': 1,
      'boundary_version': 1,
      'schema_version': 3,
      'payload_json': jsonEncode(fixturePayload(id: id, code: code)),
      'project_id': projectId,
      'kind': 'landBlock',
      'parent_block_id': null,
    });
    await db.insert(SqliteLandParcelRepository.boundaryVersionTable, {
      'id': '$id-boundary-1',
      'parcel_id': id,
      'version': 1,
      'schema_version': 3,
      'payload_json': jsonEncode({
        'id': '$id-boundary-1',
        'parcelId': id,
        'version': 1,
        'boundary': [
          {'latitude': 16.0100, 'longitude': 106.0100, 'altitudeM': null},
          {'latitude': 16.0100, 'longitude': 106.0108, 'altitudeM': null},
          {'latitude': 16.0104, 'longitude': 106.0108, 'altitudeM': null},
          {'latitude': 16.0104, 'longitude': 106.0100, 'altitudeM': null},
        ],
        'centroid': {
          'latitude': 16.0102,
          'longitude': 106.0104,
          'altitudeM': null,
        },
        'areaM2': 100.0,
        'areaHa': 0.01,
        'perimeterM': 40.0,
        'source': 'gps',
        'verificationStatus': 'measured',
        'horizontalAccuracyM': null,
        'boundaryConfidence': null,
        'occurredAt': '2026-09-30T00:00:00.000Z',
        'actorMembershipId': 'member',
        'note': null,
        'sourceFileName': null,
        'sourceFileHash': null,
      }),
    });
  }

  /// Shared rollback assertion for the four project rejection tests.
  ///
  /// After a rejected save the source is unchanged, only the source and
  /// the fixture block exist, no derivation was written and no counter
  /// was advanced.
  Future<void> expectRollbackAfterProjectRejection({
    required int expectedParcelCount,
  }) async {
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(source.active, isTrue);
    expect(
      await parcels.listByFarm('farm', includeInactive: true),
      hasLength(expectedParcelCount),
    );
    expect(await history.derivations('farm', 'source'), isEmpty);
    expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
  }

  Wgs84Polygon overlappingFixture() => Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16.0101, longitude: 106.0101),
    Wgs84Vertex(latitude: 16.0101, longitude: 106.0107),
    Wgs84Vertex(latitude: 16.0103, longitude: 106.0107),
    Wgs84Vertex(latitude: 16.0103, longitude: 106.0101),
  ]);

  test('creates both spatially linked children and retains source', () async {
    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    final preview = await service.preview(
      subject: subject,
      sourceParcelId: source.id,
      cutStart: cutA,
      cutEnd: cutB,
    );
    expect(
      preview.areasM2[0] + preview.areasM2[1],
      closeTo(source.areaM2, 0.01),
    );
    final children = await save();
    expect(children.map((p) => p.parcelCode), [
      'LA-SVK-NONG-TAKO-L00001',
      'LA-SVK-NONG-TAKO-L00002',
    ]);
    expect(children.every((p) => p.spatialFeatureId != null), isTrue);
    expect((await history.derivations('farm', 'source')), hasLength(2));
    final retained = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(retained.spatialFeatureId, source.spatialFeatureId);
    expect(retained.boundaryVersion, source.boundaryVersion);
    expect(retained.boundary, source.boundary);
    expect(retained.active, isFalse);
    expect(await parcels.listByFarm('farm'), hasLength(2));
    await expectLater(save(), throwsStateError);
    expect(await history.derivations('farm', 'source'), hasLength(2));
  });

  final threeCuts = [
    const ParcelSubdivisionCut(fragmentIndex: 0, path: [cutA, cutB]),
    const ParcelSubdivisionCut(
      fragmentIndex: 0,
      path: [
        Wgs84Vertex(latitude: 16.0005, longitude: 106.001),
        Wgs84Vertex(latitude: 16.0005, longitude: 106.002),
      ],
    ),
  ];

  Future<List<LandParcel>> saveThree() => service.savePlan(
    subject: subject,
    sourceParcelId: 'source',
    villageId: 'agrico-la-svk-nong-tako',
    expectedBoundaryVersion: 1,
    cuts: threeCuts,
    names: ['A', 'B', 'C'],
  );

  test('two cuts save three direct children in one operation', () async {
    final preview = await service.previewPlan(
      subject: subject,
      sourceParcelId: 'source',
      cuts: threeCuts,
    );
    expect(preview.boundaries, hasLength(3));
    final children = await saveThree();
    expect(children.map((p) => p.name), ['A', 'B', 'C']);
    expect(children.map((p) => p.parcelCode), [
      'LA-SVK-NONG-TAKO-L00001',
      'LA-SVK-NONG-TAKO-L00002',
      'LA-SVK-NONG-TAKO-L00003',
    ]);
    expect(children.every((p) => p.spatialFeatureId != null), isTrue);
    final derivations = await history.derivations('farm', 'source');
    expect(
      derivations.where((d) => d.sourceParcelId == 'source'),
      hasLength(3),
    );
    expect(await parcels.listByFarm('farm'), hasLength(3));
  });

  test(
    'independent sketches keep source active and measure overlaps separately',
    () async {
      Wgs84Polygon box(double west, double east) => Wgs84Polygon.fromVertices([
        Wgs84Vertex(latitude: 16.0002, longitude: west),
        Wgs84Vertex(latitude: 16.0002, longitude: east),
        Wgs84Vertex(latitude: 16.0007, longitude: east),
        Wgs84Vertex(latitude: 16.0007, longitude: west),
      ]);
      final first = box(106.0002, 106.0009);
      final second = box(106.0008, 106.00205);
      final cuts = [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: first),
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: second),
      ];
      final preview = await service.previewPlan(
        subject: subject,
        sourceParcelId: 'source',
        cuts: cuts,
        independentSketches: true,
      );
      expect(preview.boundaries, [first, second]);
      expect(preview.areasM2, everyElement(greaterThan(0)));
      expect(preview.perimetersM, everyElement(greaterThan(0)));
      final saved = await service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: cuts,
        names: ['A', 'B'],
        independentSketches: true,
      );
      expect(saved.map((parcel) => parcel.boundary), [first, second]);
      expect(
        saved.every((parcel) => parcel.layer == ParcelLayer.fieldPlot),
        isTrue,
      );
      expect(saved.map((parcel) => parcel.parentLandBlockId), [
        'source',
        'source',
      ]);
      expect(
        (await parcels.getById(farmId: 'farm', id: 'source'))!.active,
        isTrue,
      );
      expect(
        (await parcels.getById(farmId: 'farm', id: 'source'))!.layer,
        ParcelLayer.landBlock,
      );
      final more = await service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: first)],
        names: ['C'],
        independentSketches: true,
      );
      expect(more.single.parcelCode, 'LA-SVK-NONG-TAKO-L00003');
      expect((await history.derivations('farm', 'source')), hasLength(3));
    },
  );

  test('independent land block overlapping the active source is rejected and '
      'rolls back everything', () async {
    Wgs84Polygon box(double west, double east, double north) =>
        Wgs84Polygon.fromVertices([
          Wgs84Vertex(latitude: 16.0001, longitude: west),
          Wgs84Vertex(latitude: 16.0001, longitude: east),
          Wgs84Vertex(latitude: north, longitude: east),
          Wgs84Vertex(latitude: north, longitude: west),
        ]);
    final block = box(106.0001, 106.003, 16.0012);
    final plot = box(106.0003, 106.0008, 16.0008);
    final sourceBefore = (await parcels.getById(farmId: 'farm', id: 'source'))!;

    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: block),
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: plot),
        ],
        names: ['Lô A', 'Thửa A1'],
        independentSketches: true,
        details: const [
          ParcelSketchDetails(layer: ParcelLayer.landBlock),
          ParcelSketchDetails(
            layer: ParcelLayer.fieldPlot,
            parentSketchIndex: 0,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    final sourceAfter = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(sourceAfter.active, isTrue);
    expect(sourceAfter.boundaryVersion, sourceBefore.boundaryVersion);
    expect(sourceAfter.boundary, sourceBefore.boundary);
    expect(
      await parcels.listByFarm('farm', includeInactive: true),
      hasLength(1),
    );
    expect(await history.derivations('farm', 'source'), isEmpty);
    expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
    expect(await db.query('land_use_profiles'), isEmpty);
    expect(await db.query('land_parcel_crops'), isEmpty);
    final links = await db.query('land_parcel_spatial_links');
    expect(links, hasLength(1));
    expect(links.single['land_parcel_id'], 'source');
  });

  test('independent land block outside source with inner plot saves '
      'successfully', () async {
    Wgs84Polygon box(double west, double east, double north) =>
        Wgs84Polygon.fromVertices([
          Wgs84Vertex(latitude: 16.0001, longitude: west),
          Wgs84Vertex(latitude: 16.0001, longitude: east),
          Wgs84Vertex(latitude: north, longitude: east),
          Wgs84Vertex(latitude: north, longitude: west),
        ]);
    final block = box(106.0100, 106.0120, 16.0012);
    final plot = box(106.0103, 106.0108, 16.0008);
    final saved = await service.savePlan(
      subject: subject,
      sourceParcelId: 'source',
      villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: 1,
      cuts: [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: block),
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: plot),
      ],
      names: ['Lô B', 'Thửa B1'],
      independentSketches: true,
      details: const [
        ParcelSketchDetails(
          layer: ParcelLayer.landBlock,
          landCondition: LandCondition.unused,
          clearingStatus: ClearingStatus.inProgress,
          cropType: 'Đậu',
          cropQuantity: 5,
          cropUnit: 'cây',
          cropGrowthStage: CropGrowthStage.seedling,
        ),
        ParcelSketchDetails(
          layer: ParcelLayer.fieldPlot,
          parentSketchIndex: 0,
          landCondition: LandCondition.cultivated,
          cropType: 'Lạc',
          cropQuantity: 12,
          cropUnit: 'cây',
          cropGrowthStage: CropGrowthStage.seedling,
        ),
      ],
    );

    expect(saved, hasLength(2));
    final blockResult = saved.first;
    final plotResult = saved.last;
    expect(blockResult.layer, ParcelLayer.landBlock);
    expect(blockResult.parentLandBlockId, isNull);
    expect(plotResult.layer, ParcelLayer.fieldPlot);
    expect(plotResult.parentLandBlockId, blockResult.id);

    expect(blockResult.id, isNot(plotResult.id));
    expect(blockResult.parcelCode, isNot(plotResult.parcelCode));
    expect(blockResult.spatialFeatureId, isNotNull);
    expect(plotResult.spatialFeatureId, isNotNull);
    expect(blockResult.spatialFeatureId, isNot(plotResult.spatialFeatureId));

    final lineage = await history.derivations('farm', 'source');
    expect(lineage, hasLength(2));
    expect(lineage.map((d) => d.targetParcelId).toSet(), {
      blockResult.id,
      plotResult.id,
    });

    final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
    expect(source.active, isTrue);

    final surveys = SqliteLandSurveyRepository(db);
    final plotProfile = await surveys.getLandUseProfile(plotResult.id);
    expect(plotProfile, isNotNull);
    expect(plotProfile!.currentCondition, LandCondition.cultivated);
    final blockProfile = await surveys.getLandUseProfile(blockResult.id);
    expect(blockProfile, isNull);
    final crops = await surveys.listCrops(plotResult.id);
    expect(crops.single.cropType, 'Lạc');
    expect(crops.single.growthStage, CropGrowthStage.seedling);
    expect(await surveys.listCrops(blockResult.id), isEmpty);
  });

  test('two new blocks in the same batch cannot overlap each other', () async {
    Wgs84Polygon box(double west, double east, double north) =>
        Wgs84Polygon.fromVertices([
          Wgs84Vertex(latitude: 16.0001, longitude: west),
          Wgs84Vertex(latitude: 16.0001, longitude: east),
          Wgs84Vertex(latitude: north, longitude: east),
          Wgs84Vertex(latitude: north, longitude: west),
        ]);
    final blockA = box(106.0100, 106.0120, 16.0012);
    final blockB = box(106.0110, 106.0130, 16.0012);
    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: blockA),
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: blockB),
        ],
        names: ['A', 'B'],
        independentSketches: true,
        details: const [
          ParcelSketchDetails(layer: ParcelLayer.landBlock),
          ParcelSketchDetails(layer: ParcelLayer.landBlock),
        ],
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await parcels.listByFarm('farm', includeInactive: true),
      hasLength(1),
    );
    expect(await history.derivations('farm', 'source'), isEmpty);
    expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
  });

  test('two adjacent new blocks sharing only an edge are allowed', () async {
    Wgs84Polygon box(double west, double east, double north) =>
        Wgs84Polygon.fromVertices([
          Wgs84Vertex(latitude: 16.0001, longitude: west),
          Wgs84Vertex(latitude: 16.0001, longitude: east),
          Wgs84Vertex(latitude: north, longitude: east),
          Wgs84Vertex(latitude: north, longitude: west),
        ]);
    final blockA = box(106.0100, 106.0110, 16.0012);
    final blockB = box(106.0110, 106.0120, 16.0012);
    final saved = await service.savePlan(
      subject: subject,
      sourceParcelId: 'source',
      villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: 1,
      cuts: [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: blockA),
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: blockB),
      ],
      names: ['A', 'B'],
      independentSketches: true,
      details: const [
        ParcelSketchDetails(layer: ParcelLayer.landBlock),
        ParcelSketchDetails(layer: ParcelLayer.landBlock),
      ],
    );
    expect(saved, hasLength(2));
    expect(saved.every((p) => p.layer == ParcelLayer.landBlock), isTrue);
    expect(saved.every((p) => p.parentLandBlockId == null), isTrue);
    expect(saved.first.id, isNot(saved.last.id));
    expect(saved.first.spatialFeatureId, isNot(saved.last.spatialFeatureId));
  });

  test(
    'enclosed polygon saves a child and a remainder with a persisted hole',
    () async {
      final interior = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.0002, longitude: 106.0004),
        Wgs84Vertex(latitude: 16.0002, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0006, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0006, longitude: 106.0004),
      ]);
      final operations = [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: interior),
      ];
      final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      final preview = await service.previewPlan(
        subject: subject,
        sourceParcelId: source.id,
        cuts: operations,
      );
      expect(preview.boundaries.first.holes, hasLength(1));
      expect(
        preview.areasM2.reduce((a, b) => a + b),
        closeTo(source.areaM2, 0.01),
      );
      final created = await service.savePlan(
        subject: subject,
        sourceParcelId: source.id,
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: source.boundaryVersion,
        cuts: operations,
        names: ['Còn lại', 'Lô giữa'],
      );
      final remainder = (await parcels.getById(
        farmId: 'farm',
        id: created.first.id,
      ))!;
      expect(remainder.boundary.holes.single, interior.vertices);
      expect(
        remainder.areaM2 + created.last.areaM2,
        closeTo(source.areaM2, 0.01),
      );
      expect((await history.derivations('farm', 'source')), hasLength(2));
    },
  );

  test(
    'adjacent enclosed parcels retain their shared edge and three identities',
    () async {
      Wgs84Polygon box(double west, double east) => Wgs84Polygon.fromVertices([
        Wgs84Vertex(latitude: 16.0002, longitude: west),
        Wgs84Vertex(latitude: 16.0002, longitude: east),
        Wgs84Vertex(latitude: 16.0006, longitude: east),
        Wgs84Vertex(latitude: 16.0006, longitude: west),
      ]);
      final first = box(106.0004, 106.0008);
      final second = box(106.0008, 106.0012);
      final operations = [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: first),
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: second),
      ];
      final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      final preview = await service.previewPlan(
        subject: subject,
        sourceParcelId: source.id,
        cuts: operations,
      );
      expect(preview.boundaries, hasLength(3));
      expect(preview.boundaries.first.holes, hasLength(1));
      final children = await service.savePlan(
        subject: subject,
        sourceParcelId: source.id,
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: source.boundaryVersion,
        cuts: operations,
        names: ['Còn lại', 'A', 'B'],
      );
      expect(children, hasLength(3));
      expect(
        (await parcels.getById(
          farmId: 'farm',
          id: children.first.id,
        ))!.boundary.holes,
        hasLength(1),
      );
      final remainder = (await parcels.getById(
        farmId: 'farm',
        id: children.first.id,
      ))!;
      const codec = KmlInterchangeCodec();
      expect(
        codec.importKml(codec.exportKml(remainder)).previews.single.boundary,
        remainder.boundary,
      );
      expect(
        children.map((child) => child.areaM2).reduce((a, b) => a + b),
        closeTo(source.areaM2, 0.01),
      );
      expect((await history.derivations('farm', 'source')), hasLength(3));
    },
  );

  test(
    'all split parcels round trip through Google Earth KML and KMZ',
    () async {
      final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      final children = await saveThree();
      const codec = KmlInterchangeCodec();
      for (final child in children) {
        expect(child.boundary.crs, Wgs84Polygon.crsCode);
        expect(child.boundary.isClosed, isTrue);
        expect(child.boundarySource, BoundarySource.manual);
        final kml = codec.exportKml(child);
        expect(kml, contains('http://www.opengis.net/kml/2.2'));
        final fromKml = codec.importKml(kml).previews.single;
        expect(fromKml.boundary, child.boundary);
        expect(fromKml.metadata.parcelCode, child.parcelCode);
        expect(fromKml.metadata.parcelName, child.name);
        final fromKmz = codec.importKmz(codec.exportKmz(child)).previews.single;
        expect(fromKmz.boundary, child.boundary);
        expect(fromKmz.metadata.parcelCode, child.parcelCode);
      }
      final original = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      expect(original.boundary, source.boundary);
      expect(original.boundarySource, source.boundarySource);
      expect(original.boundaryVersion, source.boundaryVersion);
    },
  );

  test(
    'third lineage failure rolls back all three children and numbers',
    () async {
      await db.execute('''CREATE TRIGGER reject_third_split
      BEFORE INSERT ON parcel_derivations
      WHEN (SELECT COUNT(*) FROM parcel_derivations) = 2
      BEGIN SELECT RAISE(ABORT, 'third lineage rejected'); END''');
      await expectLater(saveThree(), throwsA(isA<Exception>()));
      expect(await parcels.listByFarm('farm'), hasLength(1));
      expect(await history.derivations('farm', 'source'), isEmpty);
      expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
    },
  );

  test(
    'failed second lineage rolls back both children and both numbers',
    () async {
      await db.execute('''CREATE TRIGGER reject_second_split
      BEFORE INSERT ON parcel_derivations
      WHEN (SELECT COUNT(*) FROM parcel_derivations) = 1
      BEGIN SELECT RAISE(ABORT, 'second lineage rejected'); END''');
      await expectLater(save(), throwsA(isA<Exception>()));
      expect(await parcels.listByFarm('farm'), hasLength(1));
      expect(await history.derivations('farm', 'source'), isEmpty);
      expect(await db.query(SqliteParcelNumberSequence.locationTable), isEmpty);
      expect(
        (await parcels.getById(farmId: 'farm', id: 'source'))!.boundaryVersion,
        1,
      );
    },
  );

  test('repeatedly splits a child into three active fragments', () async {
    final children = await save();
    final grandchildren = await service.save(
      subject: subject,
      sourceParcelId: children.first.id,
      villageId: 'agrico-la-svk-nong-tako',
      expectedBoundaryVersion: 1,
      cutStart: const Wgs84Vertex(latitude: 16.0005, longitude: 106.001),
      cutEnd: const Wgs84Vertex(latitude: 16.0005, longitude: 106.002),
      firstName: 'Mảnh thứ ba',
      secondName: 'Mảnh thứ tư',
    );
    expect(grandchildren, hasLength(2));
    expect(await parcels.listByFarm('farm'), hasLength(3));
    expect(
      (await history.derivations('farm', children.first.id)),
      hasLength(3),
    );
  });

  test('stale source revision prevents both children', () async {
    await expectLater(
      service.save(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 2,
        cutStart: cutA,
        cutEnd: cutB,
        firstName: 'A',
        secondName: 'B',
      ),
      throwsStateError,
    );
    expect(await parcels.listByFarm('farm'), hasLength(1));
  });

  test(
    'independent sketches overlapping the active source are rejected',
    () async {
      final overlapping = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 15.9999, longitude: 105.9999),
        Wgs84Vertex(latitude: 15.9999, longitude: 106.0001),
        Wgs84Vertex(latitude: 16.0001, longitude: 106.0001),
        Wgs84Vertex(latitude: 16.0001, longitude: 105.9999),
      ]);
      final cuts = [
        ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: overlapping),
      ];

      await expectLater(
        service.previewPlan(
          subject: subject,
          sourceParcelId: 'source',
          cuts: cuts,
          independentSketches: true,
          productionPlots: true,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('independent sketches with NULL source reject a candidate overlapping '
      'a NULL project block', () async {
    await insertFixtureBlock(
      id: 'existing-null',
      code: 'P-NULL',
      projectId: null,
    );
    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(
            fragmentIndex: 0,
            polygon: overlappingFixture(),
          ),
        ],
        names: ['New block'],
        independentSketches: true,
        details: const [ParcelSketchDetails(layer: ParcelLayer.landBlock)],
      ),
      throwsA(isA<StateError>()),
    );
    await expectRollbackAfterProjectRejection(expectedParcelCount: 2);
  });

  test('independent sketches with NULL source reject a candidate overlapping '
      'an X project block', () async {
    await insertFixtureBlock(
      id: 'existing-x',
      code: 'P-X',
      projectId: 'PROJ-A',
    );
    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(
            fragmentIndex: 0,
            polygon: overlappingFixture(),
          ),
        ],
        names: ['New block'],
        independentSketches: true,
        details: const [ParcelSketchDetails(layer: ParcelLayer.landBlock)],
      ),
      throwsA(isA<StateError>()),
    );
    await expectRollbackAfterProjectRejection(expectedParcelCount: 2);
  });

  test('independent sketches with X source reject a candidate overlapping '
      'a NULL project block', () async {
    await assignSourceProject('PROJ-X');
    await insertFixtureBlock(
      id: 'existing-null',
      code: 'P-NULL',
      projectId: null,
    );
    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(
            fragmentIndex: 0,
            polygon: overlappingFixture(),
          ),
        ],
        names: ['New block'],
        independentSketches: true,
        details: const [ParcelSketchDetails(layer: ParcelLayer.landBlock)],
      ),
      throwsA(isA<StateError>()),
    );
    await expectRollbackAfterProjectRejection(expectedParcelCount: 2);
  });

  test('independent sketches with X source reject a candidate overlapping '
      'an X project block', () async {
    await assignSourceProject('PROJ-X');
    await insertFixtureBlock(
      id: 'existing-x',
      code: 'P-X',
      projectId: 'PROJ-X',
    );
    await expectLater(
      service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(
            fragmentIndex: 0,
            polygon: overlappingFixture(),
          ),
        ],
        names: ['New block'],
        independentSketches: true,
        details: const [ParcelSketchDetails(layer: ParcelLayer.landBlock)],
      ),
      throwsA(isA<StateError>()),
    );
    await expectRollbackAfterProjectRejection(expectedParcelCount: 2);
  });

  test(
    'independent sketches inherit project X and allow overlap with project Y',
    () async {
      await assignSourceProject('PROJ-X');
      await insertFixtureBlock(
        id: 'existing-y',
        code: 'P-Y',
        projectId: 'PROJ-Y',
      );
      final saved = await service.savePlan(
        subject: subject,
        sourceParcelId: 'source',
        villageId: 'agrico-la-svk-nong-tako',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(
            fragmentIndex: 0,
            polygon: overlappingFixture(),
          ),
        ],
        names: ['New block'],
        independentSketches: true,
        details: const [ParcelSketchDetails(layer: ParcelLayer.landBlock)],
      );
      expect(saved, hasLength(1));
      final block = saved.single;
      expect(block.layer, ParcelLayer.landBlock);
      expect(block.parentLandBlockId, isNull);
      expect(block.projectId, 'PROJ-X');
      final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      expect(source.active, isTrue);
    },
  );
  test(
    'saveProductionPlots forwards production drafts with canonical parcel ids',
    () async {
      await assignSourceProject('PROJ-X');

      final repository = _CapturingProductionCreationRepository();
      final production = ProductionParcelCreationService(repository);
      final productionSubdivision = ParcelSubdivisionService(
        parcels: parcels,
        workflow: workflow,
        productionCreation: production,
      );

      final first = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.0001, longitude: 106.0001),
        Wgs84Vertex(latitude: 16.0001, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0004, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0004, longitude: 106.0001),
      ]);
      final second = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.0005, longitude: 106.0001),
        Wgs84Vertex(latitude: 16.0005, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0008, longitude: 106.0008),
        Wgs84Vertex(latitude: 16.0008, longitude: 106.0001),
      ]);

      const details = [
        ParcelSketchDetails(layer: ParcelLayer.fieldPlot),
        ParcelSketchDetails(
          layer: ParcelLayer.fieldPlot,
          landCondition: LandCondition.cultivated,
          cropType: 'Lạc',
          cropQuantity: 12,
          cropUnit: 'cây',
          cropGrowthStage: CropGrowthStage.seedling,
        ),
      ];

      final saved = await productionSubdivision.saveProductionPlots(
        subject: subject,
        sourceParcelId: 'source',
        expectedBoundaryVersion: 1,
        cuts: [
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: first),
          ParcelSubdivisionCut.enclosed(fragmentIndex: 0, polygon: second),
        ],
        names: const ['Thửa A', 'Thửa B'],
        details: details,
      );

      expect(repository.calls, 1);
      expect(repository.parentLandBlockId, 'source');
      expect(repository.expectedParentBoundaryVersion, 1);
      expect(repository.temporalState, SpatialTemporalState.underConstruction);
      expect(repository.details, details);

      expect(repository.drafts, hasLength(2));
      expect(
        repository.drafts.every((draft) => draft.id.startsWith('land-parcel-')),
        isTrue,
      );
      expect(
        repository.drafts.every(
          (draft) =>
              draft.layer == ParcelLayer.fieldPlot &&
              draft.parentLandBlockId == 'source',
        ),
        isTrue,
      );
      expect(repository.drafts.map((draft) => draft.boundary), [first, second]);
      expect(saved, repository.drafts);

      final source = (await parcels.getById(farmId: 'farm', id: 'source'))!;
      expect(source.active, isTrue);
      expect(source.layer, ParcelLayer.landBlock);
      expect(source.projectId, 'PROJ-X');
    },
  );
}

class _CapturingProductionCreationRepository
    implements ProductionParcelCreationRepository {
  int calls = 0;
  List<LandParcel> drafts = const [];
  List<ParcelSketchDetails> details = const [];
  String? parentLandBlockId;
  int? expectedParentBoundaryVersion;
  SpatialTemporalState? temporalState;

  @override
  Future<LandParcel> createLandBlock({
    required LandParcel draft,
    required String projectCode,
    List<CropRecord> crops = const [],
    required SpatialTemporalState temporalState,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LandParcel> createStandaloneFieldPlot({
    required LandParcel draft,
    required String projectCode,
    required SpatialTemporalState temporalState,
  }) {
    throw StateError('Subdivision must not create standalone plots.');
  }

  @override
  Future<LandParcel> createFieldPlot({
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<LandParcel>> createFieldPlots({
    required List<LandParcel> drafts,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
    required List<ParcelSketchDetails> details,
  }) async {
    calls++;
    this.drafts = List.unmodifiable(drafts);
    this.details = List.unmodifiable(details);
    this.parentLandBlockId = parentLandBlockId;
    this.expectedParentBoundaryVersion = expectedParentBoundaryVersion;
    this.temporalState = temporalState;
    return drafts;
  }
}
