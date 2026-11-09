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
    permissionCodes: {
      PermissionCodes.fieldView,
      PermissionCodes.fieldEdit,
      PermissionCodes.fieldBoundaryEdit,
    },
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

  Future<LandParcel> linkedPlot(String id, {double left = 106.001}) async {
    final original = await plot(id, boundary: square(left, 16.001, 0.002));
    final parent =
        await repo.getById(farmId: 'farm', id: 'block') ?? await block('block');
    return service.changeParent(
      subject: subject,
      expectedPlot: original,
      expectedParent: parent,
    );
  }

  LandParcel replacement(LandParcel original, Wgs84Polygon polygon) =>
      original.replaceBoundary(
        boundary: polygon,
        source: BoundarySource.manual,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member',
        occurredAt: time.add(const Duration(days: 1)),
      );
  Future<void> update(LandParcel original, Wgs84Polygon polygon) =>
      workflow.update(
        parcel: replacement(original, polygon),
        expectedParcel: original,
        temporalState: SpatialTemporalState.operational,
      );
  Future<String> snapshot() async => jsonEncode({
    'parcels': await db.query(SqliteLandParcelRepository.parcelTable),
    'rest': await protectedSnapshot(),
  });
  test(
    'valid plot edit appends history and spatial revision preserving identity parent code and temporal state',
    () async {
      final original = await linkedPlot('plot');
      await SqliteLandSurveyRepository(db).createCrop(
        CropRecord(
          id: 'crop',
          parcelId: original.id,
          cropType: 'Peanut',
          quantity: 12,
          unit: 'plants',
          condition: CropCondition.healthy,
          active: true,
          createdAt: time,
          createdBy: 'member',
          updatedAt: time,
          updatedBy: 'member',
        ),
      );
      final crops = await db.query(SqliteLandSurveyRepository.cropsTable);
      final counters = await db.query(
        SqliteProductionParcelNumberAllocator.standaloneTable,
      );
      await update(original, square(106.0012, 16.0012, 0.0018));
      final saved = await reload('plot');
      expect(await db.query(SqliteLandSurveyRepository.cropsTable), crops);
      expect(saved.id, original.id);
      expect(saved.parcelCode, original.parcelCode);
      expect(saved.projectId, original.projectId);
      expect(saved.parentBlockId, original.parentBlockId);
      expect(saved.spatialFeatureId, original.spatialFeatureId);
      expect(saved.boundaryVersion, original.boundaryVersion + 1);
      expect(saved.boundaryHistory.length, original.boundaryHistory.length + 1);
      expect(saved.boundaryHistory.first.id, original.boundaryHistory.first.id);
      final revisions = await db.query(
        SqliteSpatialSchema.revisionsTable,
        where: 'feature_id = ?',
        whereArgs: [original.spatialFeatureId],
        orderBy: 'revision',
      );
      expect(revisions.length, 2);
      expect(
        revisions.last['temporal_state'],
        revisions.first['temporal_state'],
      );
      expect(
        await db.query(SqliteProductionParcelNumberAllocator.standaloneTable),
        counters,
      );
    },
  );
  test('outside parent failure rolls back every table', () async {
    final original = await linkedPlot('plot');
    final before = await snapshot();
    await expectLater(
      update(original, square(106.02, 16.02, 0.001)),
      throwsA(isA<FormatException>()),
    );
    expect(await snapshot(), before);
  });
  test('overlapping sibling rejected but shared edge allowed', () async {
    final original = await linkedPlot('plot');
    await linkedPlot('sibling', left: 106.004);
    final before = await snapshot();
    await expectLater(
      update(original, square(106.0035, 16.001, 0.002)),
      throwsA(isA<FormatException>()),
    );
    expect(await snapshot(), before);
    await update(original, square(106.002, 16.001, 0.002));
    expect((await reload('plot')).boundaryVersion, 2);
  });
  test('block shrink excluding active child rejected atomically', () async {
    await linkedPlot('plot');
    final parent = await reload('block');
    await workflow.bootstrapExisting(
      farmId: parent.farmId,
      landParcelId: parent.id,
      temporalState: SpatialTemporalState.operational,
    );
    final current = await reload('block');
    final before = await snapshot();
    await expectLater(
      update(current, square(106.005, 16.005, 0.002)),
      throwsA(isA<FormatException>()),
    );
    expect(await snapshot(), before);
  });
  test(
    'block edit containing children preserves child rows and their spatial revisions',
    () async {
      final child = await linkedPlot('plot');
      final parent = await reload('block');
      await workflow.bootstrapExisting(
        farmId: parent.farmId,
        landParcelId: parent.id,
        temporalState: SpatialTemporalState.underConstruction,
      );
      final current = await reload('block');
      final childRow = await db.query(
        SqliteLandParcelRepository.parcelTable,
        where: 'id = ?',
        whereArgs: [child.id],
      );
      final childRevisions = await db.query(
        SqliteSpatialSchema.revisionsTable,
        where: 'feature_id = ?',
        whereArgs: [child.spatialFeatureId],
      );
      await update(current, square(106, 16, 0.012));
      expect(
        await db.query(
          SqliteLandParcelRepository.parcelTable,
          where: 'id = ?',
          whereArgs: [child.id],
        ),
        childRow,
      );
      expect(
        await db.query(
          SqliteSpatialSchema.revisionsTable,
          where: 'feature_id = ?',
          whereArgs: [child.spatialFeatureId],
        ),
        childRevisions,
      );
    },
  );
  test('block overlap rejected and shared block edge allowed', () async {
    final parent = await block('block');
    await block('other', boundary: square(106.01, 16, 0.01));
    await workflow.bootstrapExisting(
      farmId: parent.farmId,
      landParcelId: parent.id,
      temporalState: SpatialTemporalState.operational,
    );
    final original = await reload('block');
    final before = await snapshot();
    await expectLater(
      update(original, square(106, 16, 0.012)),
      throwsA(isA<FormatException>()),
    );
    expect(await snapshot(), before);
    await update(original, square(106.001, 16.001, 0.009));
  });
  test(
    'stale editor after metadata or parent change cannot overwrite fresh record',
    () async {
      final original = await linkedPlot('plot');
      await service.changeParent(
        subject: subject,
        expectedPlot: original,
        expectedParent: null,
      );
      final before = await snapshot();
      await expectLater(
        update(original, square(106.001, 16.001, 0.001)),
        throwsA(isA<FormatException>()),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'stale boundary revision cannot overwrite another saved boundary',
    () async {
      final original = await linkedPlot('plot');
      await update(original, square(106.001, 16.001, 0.001));
      final before = await snapshot();
      await expectLater(
        update(original, square(106.0012, 16.0012, 0.001)),
        throwsA(isA<FormatException>()),
      );
      expect(await snapshot(), before);
    },
  );
  test('spatial insert failure rolls back parcel and boundary history', () async {
    final original = await linkedPlot('plot');
    await db.execute(
      "CREATE TRIGGER reject_revision BEFORE INSERT ON spatial_feature_revisions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    final before = await snapshot();
    await expectLater(
      update(original, square(106.001, 16.001, 0.001)),
      throwsA(anything),
    );
    expect(await snapshot(), before);
  });
  test(
    'application rejects stale snapshot and missing boundary permission',
    () async {
      final original = await linkedPlot('plot');
      final app = LandParcelApplicationService(
        repository: repo,
        spatialWorkflow: workflow,
      );
      ReplaceBoundaryCommand command(int version) => ReplaceBoundaryCommand(
        farmId: 'farm',
        parcelId: original.id,
        vertices: square(106.001, 16.001, 0.001).vertices,
        source: BoundarySource.manual,
        actorMembershipId: 'member',
        occurredAt: time.add(const Duration(days: 1)),
        expectedBoundaryVersion: version,
      );
      final before = await snapshot();
      expect(
        (await app.replaceBoundary(subject, command(999))).messageKey,
        'boundaryEdit.changed',
      );
      const denied = AuthorizationSubject(
        userId: 'u',
        membershipId: 'member',
        farmId: 'farm',
        permissionCodes: {PermissionCodes.fieldView},
        dataScopes: {DataScope.allFarm},
      );
      expect(
        (await app.replaceBoundary(
          denied,
          command(original.boundaryVersion),
        )).status,
        LandParcelApplicationStatus.permissionDenied,
      );
      expect(await snapshot(), before);
    },
  );
}
