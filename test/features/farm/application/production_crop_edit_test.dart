import 'dart:convert';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';

import 'package:agrico_deepseek/core/identity/data/sqlite_production_parcel_number_allocator.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/data/sqlite_spatial_schema.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_parent_service.dart';
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
import '../../../core/spatial/support/sequential_spatial_identity_generator.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteLandParcelRepository repo;
  late LandParcelParentService service;
  late LandParcelSpatialSyncWorkflow workflow;
  final time = DateTime.utc(2026, 10, 1);
  const subject = AuthorizationSubject(
    userId: 'u',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: {PermissionCodes.fieldView, PermissionCodes.fieldEdit},
    dataScopes: {DataScope.allFarm},
  );

  Wgs84Polygon square(double left, double bottom, double width) =>
      Wgs84Polygon.fromVertices([
        Wgs84Vertex(longitude: left, latitude: bottom),
        Wgs84Vertex(longitude: left + width, latitude: bottom),
        Wgs84Vertex(longitude: left + width, latitude: bottom + width),
        Wgs84Vertex(longitude: left, latitude: bottom + width),
      ]);
  LandParcel draft(
    String id, {
    ParcelLayer kind = ParcelLayer.landBlock,
    String farm = 'farm',
    String? project = 'project',
    String? parent,
    Wgs84Polygon? boundary,
    bool active = true,
  }) => LandParcel.create(
    id: id,
    farmId: farm,
    parcelCode: id,
    name: id,
    projectId: project,
    kind: kind,
    parentBlockId: parent,
    active: active,
    boundary: boundary ?? square(106, 16, 0.01),
    boundarySource: BoundarySource.manual,
    verificationStatus: BoundaryVerificationStatus.draft,
    actorMembershipId: 'member',
    occurredAt: time,
  );
  Future<LandParcel> plot(String id, {Wgs84Polygon? boundary}) =>
      workflow.createProductionStandaloneFieldPlot(
        draft: draft(
          id,
          kind: ParcelLayer.fieldPlot,
          boundary: boundary ?? square(106.001, 16.001, 0.002),
        ),
        projectCode: 'AGR-NONG',
        temporalState: SpatialTemporalState.underConstruction,
      );
  Future<LandParcel> block(
    String id, {
    String farm = 'farm',
    String? project = 'project',
    bool active = true,
    Wgs84Polygon? boundary,
  }) async {
    final value = draft(
      id,
      farm: farm,
      project: project,
      active: active,
      boundary: boundary,
    );
    await repo.create(value);
    return value;
  }

  Future<LandParcel> reload(String id) async =>
      (await repo.getById(farmId: 'farm', id: id))!;

  Future<String> protectedSnapshot() async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final data = <String, Object?>{};
    for (final row in tables) {
      final name = row['name']! as String;
      if (name == SqliteLandParcelRepository.parcelTable ||
          name == SqliteLandSurveyRepository.cropsTable ||
          name.startsWith('sqlite_')) {
        continue;
      }
      data[name] = await db.query(name);
    }
    return jsonEncode(data);
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(db);
    await SqliteLandSurveyRepository.createSchema(db);
    await SqliteSpatialSchema.createSchema(db);
    await SqliteLandParcelSpatialLinkRepository.createSchema(db);
    await SqliteProductionParcelNumberAllocator.createSchema(db);
    repo = SqliteLandParcelRepository(db);
    service = LandParcelParentService(repo);
    workflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(db),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: SequentialSpatialIdentityGenerator(),
    );
  });
  tearDown(() => db.close());

  CropRecord crop(
    String id, {
    String type = 'Peanut',
    String parcelId = 'plot',
    double quantity = 12,
    String? variety = 'L14',
    DateTime? date,
    int? year = 2026,
    int? age = 2,
    CropCondition condition = CropCondition.healthy,
    String? notes = 'note',
  }) => CropRecord(
    id: id,
    parcelId: parcelId,
    cropType: type,
    quantity: quantity,
    unit: 'plants',
    variety: variety,
    plantingDate: date,
    plantingYear: year,
    ageMonths: age,
    notes: notes,
    condition: condition,
    growthStage: CropGrowthStage.values.first,
    active: true,
    createdAt: time,
    createdBy: 'member',
    updatedAt: time,
    updatedBy: 'member',
  );
  Future<List<CropRecord>> crops({bool includeInactive = false}) =>
      SqliteLandSurveyRepository(
        db,
      ).listCrops('plot', includeInactive: includeInactive);
  Future<LandParcelApplicationResult<LandParcel>> save(
    List<CropRecord> values, {
    AuthorizationSubject actor = subject,
    DateTime? expected,
    Map<String, DateTime>? expectedCrops,
  }) =>
      LandParcelApplicationService(
        repository: repo,
        spatialWorkflow: workflow,
      ).updateLandParcelMetadata(
        actor,
        UpdateLandParcelMetadataCommand(
          farmId: 'farm',
          parcelId: 'plot',
          crops: values,
          expectedUpdatedAt: expected,
          expectedCropUpdates: expectedCrops,
          actorMembershipId: actor.membershipId,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
  Future<String> snapshot() async => jsonEncode({
    'parcel': await db.query(SqliteLandParcelRepository.parcelTable),
    'crops': await db.query(SqliteLandSurveyRepository.cropsTable),
    'rest': await protectedSnapshot(),
  });
  test(
    'add and change crop type variety date condition and notes preserve identity and spatial data',
    () async {
      final original = await plot('plot');
      final protected = await protectedSnapshot();
      expect(
        (await save([
          crop('draft-1', date: DateTime.utc(2026, 9, 1)),
        ])).isSuccess,
        isTrue,
      );
      final saved = (await crops()).single;
      expect(
        (await save([
          crop(
            saved.id,
            type: 'Cassava',
            variety: 'KM94',
            date: DateTime.utc(2026, 9, 10),
            quantity: 24,
            condition: CropCondition.stressed,
            notes: 'changed',
          ),
        ])).isSuccess,
        isTrue,
      );
      final changed = (await crops()).single;
      expect(changed.id, saved.id);
      expect(changed.parcelId, original.id);
      expect(changed.createdAt, saved.createdAt);
      expect(changed.createdBy, saved.createdBy);
      expect(changed.cropType, 'Cassava');
      expect(changed.variety, 'KM94');
      expect(changed.plantingDate, DateTime.utc(2026, 9, 10));
      expect(changed.quantity, 24);
      expect(changed.condition, CropCondition.stressed);
      expect(changed.notes, 'changed');
      expect(await protectedSnapshot(), protected);
      final parcel = await reload('plot');
      expect(parcel.parcelCode, original.parcelCode);
      expect(parcel.boundaryVersion, original.boundaryVersion);
      expect(parcel.spatialFeatureId, original.spatialFeatureId);
    },
  );
  test('optional fields can be cleared explicitly', () async {
    await plot('plot');
    await save([crop('draft-1', date: DateTime.utc(2026, 9, 1))]);
    final saved = (await crops()).single;
    expect(
      (await save([
        crop(
          saved.id,
          variety: null,
          date: null,
          year: null,
          age: null,
          notes: null,
        ),
      ])).isSuccess,
      isTrue,
    );
    final cleared = (await crops()).single;
    expect(cleared.variety, isNull);
    expect(cleared.plantingDate, isNull);
    expect(cleared.plantingYear, isNull);
    expect(cleared.ageMonths, isNull);
    expect(cleared.notes, isNull);
  });
  test(
    'invalid numbers type and planting year reject the entire edit',
    () async {
      await plot('plot');
      await save([crop('draft-1')]);
      final saved = (await crops()).single;
      for (final invalid in [
        crop(saved.id, quantity: 0),
        crop(saved.id, quantity: double.nan),
        crop(saved.id, type: ''),
        crop(saved.id, age: -1),
        crop(saved.id, year: 0),
        crop(saved.id, year: 2025, date: DateTime.utc(2026, 9, 1)),
      ]) {
        final before = await snapshot();
        expect(
          (await save([invalid])).status,
          LandParcelApplicationStatus.validationFailed,
        );
        expect(await snapshot(), before);
      }
    },
  );
  test(
    'duplicate and foreign crop identities cannot overwrite another parcel',
    () async {
      await plot('plot');
      await save([crop('draft-1')]);
      final saved = (await crops()).single;
      final before = await snapshot();
      for (final values in [
        [crop(saved.id), crop(saved.id)],
        [crop('foreign')],
        [crop(saved.id, parcelId: 'other')],
        [crop('draft-2'), crop('draft-2')],
      ]) {
        expect(
          (await save(values)).status,
          LandParcelApplicationStatus.validationFailed,
        );
        expect(await snapshot(), before);
      }
    },
  );
  test('remove archives crop and keeps its identity and details', () async {
    await plot('plot');
    await save([crop('draft-1')]);
    final saved = (await crops()).single;
    final protected = await protectedSnapshot();
    expect((await save([])).isSuccess, isTrue);
    expect(await crops(), isEmpty);
    final archived = (await crops(includeInactive: true)).single;
    expect(archived.id, saved.id);
    expect(archived.cropType, saved.cropType);
    expect(archived.active, isFalse);
    expect(await protectedSnapshot(), protected);
  });
  test('old editor cannot restore crop list after another edit', () async {
    await plot('plot');
    await save([crop('draft-1')]);
    final original = (await crops()).single;
    final snapshotParcel = await reload('plot');
    await save([crop(original.id, type: 'Cassava')]);
    final before = await snapshot();
    expect(
      (await save(
        [crop(original.id)],
        expected: snapshotParcel.updatedAt,
        expectedCrops: {original.id: original.updatedAt},
      )).messageKey,
      'crop.changed',
    );
    expect(await snapshot(), before);
  });
  test(
    'crop snapshot guard also detects changes outside parcel metadata',
    () async {
      await plot('plot');
      await save([crop('draft-1')]);
      final original = (await crops()).single;
      await SqliteLandSurveyRepository(
        db,
      ).updateCrop(crop(original.id, type: 'Cassava'));
      final before = await snapshot();
      expect(
        (await save(
          [crop(original.id)],
          expectedCrops: {original.id: original.updatedAt},
        )).messageKey,
        'crop.changed',
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'denied permission and cross-farm subjects cannot modify crops',
    () async {
      await plot('plot');
      final before = await snapshot();
      for (final actor in [
        const AuthorizationSubject(
          userId: 'u',
          membershipId: 'member',
          farmId: 'farm',
          permissionCodes: {PermissionCodes.fieldView},
          dataScopes: {DataScope.allFarm},
        ),
        const AuthorizationSubject(
          userId: 'u',
          membershipId: 'member',
          farmId: 'other',
          permissionCodes: {PermissionCodes.fieldEdit},
          dataScopes: {DataScope.allFarm},
        ),
      ]) {
        expect(
          (await save([crop('draft-1')], actor: actor)).status,
          LandParcelApplicationStatus.permissionDenied,
        );
      }
      expect(await snapshot(), before);
    },
  );
  test(
    'SQLite crop write failure rolls back parcel crop set and other tables',
    () async {
      await plot('plot');
      await save([crop('draft-1')]);
      final original = (await crops()).single;
      await db.execute(
        "CREATE TRIGGER reject_crop BEFORE UPDATE ON land_parcel_crops BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      final before = await snapshot();
      expect(
        (await save([crop(original.id, type: 'Cassava')])).status,
        LandParcelApplicationStatus.persistenceFailed,
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'parent changes and boundary revisions keep crops attached to the same parcel',
    () async {
      final original = await plot('plot');
      await save([crop('draft-1')]);
      final parent = await block('block');
      final linked = await service.changeParent(
        subject: subject,
        expectedPlot: await reload('plot'),
        expectedParent: parent,
      );
      final before = await db.query(SqliteLandSurveyRepository.cropsTable);
      final updated = linked.replaceBoundary(
        boundary: square(106.0012, 16.0012, 0.0015),
        source: BoundarySource.manual,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member',
        occurredAt: DateTime.now().toUtc(),
      );
      await workflow.update(
        parcel: updated,
        expectedParcel: linked,
        temporalState: SpatialTemporalState.operational,
      );
      await service.changeParent(
        subject: subject,
        expectedPlot: await reload('plot'),
        expectedParent: null,
      );
      expect(await db.query(SqliteLandSurveyRepository.cropsTable), before);
      expect((await crops()).single.parcelId, original.id);
    },
  );
}
