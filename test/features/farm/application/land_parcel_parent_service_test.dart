import 'dart:convert';

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
import 'package:agrico_deepseek/features/farm/data/models/land_parcel_mapper.dart';
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
  Matcher failure(String code) =>
      throwsA(isA<ParcelParentException>().having((e) => e.code, 'code', code));

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

  test(
    'attach transfer detach preserve code spatial data history crops and counters',
    () async {
      final original = await plot('plot');
      final a = await block('a');
      final b = await block('b');
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
      final protected = await protectedSnapshot();
      LandParcel current = original;
      for (final parent in <LandParcel?>[a, b, null]) {
        current = await service.changeParent(
          subject: subject,
          expectedPlot: current,
          expectedParent: parent,
        );
        current = await reload(current.id);
        expect(current.parentBlockId, parent?.id);
        expect(current.id, original.id);
        expect(current.parcelCode, original.parcelCode);
        expect(current.projectId, original.projectId);
        expect(current.spatialFeatureId, original.spatialFeatureId);
        expect(current.boundaryVersion, original.boundaryVersion);
        expect(
          jsonEncode(LandParcelMapper.toJson(current)['boundaryHistory']),
          jsonEncode(LandParcelMapper.toJson(original)['boundaryHistory']),
        );
        expect(current.updatedBy, subject.membershipId);
        expect(await protectedSnapshot(), protected);
      }
      expect((await plot('next')).parcelCode, 'AGR-NONG-T002');
    },
  );

  test('choices include only active same-farm same-project blocks', () async {
    final p = await plot('plot');
    await block('a');
    await block('other-project', project: 'other');
    await block('other-farm', farm: 'other');
    await block('inactive', active: false);
    await block('unassigned', project: null);
    expect(
      (await service.listBlocks(subject: subject, plot: p)).map((b) => b.id),
      ['a'],
    );
  });

  test('no-op does not write timestamps or allocate numbers', () async {
    final p = await plot('plot');
    final before = await protectedSnapshot();
    final result = await service.changeParent(
      subject: subject,
      expectedPlot: p,
      expectedParent: null,
    );
    expect(result.updatedAt, p.updatedAt);
    expect(await protectedSnapshot(), before);
  });

  test(
    'inactive missing permission partial scope and cross-farm requests are denied',
    () async {
      final p = await plot('plot');
      final a = await block('a');
      for (final denied in [
        const AuthorizationSubject(
          userId: 'u',
          membershipId: 'member',
          farmId: 'farm',
          permissionCodes: {
            PermissionCodes.fieldView,
            PermissionCodes.fieldEdit,
          },
          dataScopes: {DataScope.allFarm},
          active: false,
        ),
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
          farmId: 'farm',
          permissionCodes: {
            PermissionCodes.fieldView,
            PermissionCodes.fieldEdit,
          },
          dataScopes: {DataScope.assignedFields},
          assignedFieldIds: {'plot', 'a'},
        ),
        const AuthorizationSubject(
          userId: 'u',
          membershipId: 'member',
          farmId: 'other',
          permissionCodes: {
            PermissionCodes.fieldView,
            PermissionCodes.fieldEdit,
          },
          dataScopes: {DataScope.allFarm},
        ),
      ]) {
        await expectLater(
          service.changeParent(
            subject: denied,
            expectedPlot: p,
            expectedParent: a,
          ),
          failure('permissionDenied'),
        );
      }
      expect((await reload('plot')).parentBlockId, isNull);
    },
  );

  test(
    'target kind farm project and active state are checked before persistence',
    () async {
      final p = await plot('plot');
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: p,
        ),
        failure('invalidParent'),
      );
      final wrongKind = await plot(
        'other-plot',
        boundary: square(106.006, 16.006, 0.001),
      );
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: wrongKind,
        ),
        failure('invalidParent'),
      );
      final inactive = await block('inactive', active: false);
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: inactive,
        ),
        failure('invalidParent'),
      );
      final other = await block('other', project: 'other');
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: other,
        ),
        failure('projectMismatch'),
      );
      final foreign = await block('foreign', farm: 'other');
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: foreign,
        ),
        failure('permissionDenied'),
      );
      expect((await reload('plot')).parentBlockId, isNull);
    },
  );

  test(
    'stale plot metadata or target boundary cannot overwrite current state',
    () async {
      final p = await plot('plot');
      final a = await block('a');
      await repo.update(
        p.updateMetadata(
          name: 'new name',
          actorMembershipId: 'other',
          occurredAt: time.add(const Duration(days: 1)),
        ),
      );
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: a,
        ),
        failure('changed'),
      );
      final current = await reload('plot');
      await repo.update(
        a.replaceBoundary(
          boundary: square(106, 16, 0.02),
          source: BoundarySource.manual,
          verificationStatus: BoundaryVerificationStatus.draft,
          actorMembershipId: 'other',
          occurredAt: time.add(const Duration(days: 1)),
        ),
      );
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: current,
          expectedParent: a,
        ),
        failure('changed'),
      );
      expect((await reload('plot')).name, 'new name');
      expect((await reload('plot')).parentBlockId, isNull);
    },
  );

  test('deleted or deactivated picker targets are rejected', () async {
    final p = await plot('plot');
    final removed = await block('removed');
    await db.delete(
      SqliteLandParcelRepository.boundaryVersionTable,
      where: 'parcel_id = ?',
      whereArgs: ['removed'],
    );
    await db.delete('land_parcels', where: 'id = ?', whereArgs: ['removed']);
    await expectLater(
      service.changeParent(
        subject: subject,
        expectedPlot: p,
        expectedParent: removed,
      ),
      failure('invalidParent'),
    );
    final inactive = await block('inactive');
    await repo.setActive(
      farmId: 'farm',
      id: inactive.id,
      active: false,
      actorMembershipId: 'member',
      occurredAt: time.add(const Duration(days: 1)),
    );
    await expectLater(
      service.changeParent(
        subject: subject,
        expectedPlot: p,
        expectedParent: inactive,
      ),
      failure('invalidParent'),
    );
    expect((await reload('plot')).parentBlockId, isNull);
  });

  test(
    'stale relation editor cannot detach a subsequently linked plot',
    () async {
      final p = await plot('plot');
      final a = await block('a');
      await service.changeParent(
        subject: subject,
        expectedPlot: p,
        expectedParent: a,
      );
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: null,
        ),
        failure('changed'),
      );
      expect((await reload('plot')).parentBlockId, 'a');
    },
  );

  test(
    'outside placement and destination sibling overlap leave relation unchanged',
    () async {
      final p = await plot('plot');
      final outside = await block('outside', boundary: square(107, 17, 0.01));
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: outside,
        ),
        failure('outsideBlock'),
      );
      final a = await block('a');
      final sibling = draft(
        'sibling',
        kind: ParcelLayer.fieldPlot,
        parent: a.id,
        boundary: p.boundary,
      );
      await repo.create(sibling);
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: a,
        ),
        failure('overlap'),
      );
      expect((await reload('plot')).parentBlockId, isNull);
    },
  );

  test(
    'shared edge is allowed and current plot is excluded from overlap checks',
    () async {
      final p = await plot('plot');
      final a = await block('a');
      await repo.create(
        draft(
          'sibling',
          kind: ParcelLayer.fieldPlot,
          parent: a.id,
          boundary: square(106.003, 16.001, 0.002),
        ),
      );
      final linked = await service.changeParent(
        subject: subject,
        expectedPlot: p,
        expectedParent: a,
      );
      final result = await service.changeParent(
        subject: subject,
        expectedPlot: linked,
        expectedParent: a,
      );
      expect(result.parentBlockId, 'a');
    },
  );

  test(
    'SQLite write failure rolls back parent payload audit and all protected tables',
    () async {
      final p = await plot('plot');
      final a = await block('a');
      final before = jsonEncode(await db.query('land_parcels'));
      final protected = await protectedSnapshot();
      await db.execute(
        "CREATE TRIGGER fail_relation BEFORE UPDATE ON land_parcels WHEN NEW.id = 'plot' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        service.changeParent(
          subject: subject,
          expectedPlot: p,
          expectedParent: a,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(jsonEncode(await db.query('land_parcels')), before);
      expect(await protectedSnapshot(), protected);
    },
  );
}
