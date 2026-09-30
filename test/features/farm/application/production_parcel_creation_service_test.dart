import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/features/farm/application/production_parcel_creation_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/production_parcel_creation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject subject({
  Set<String> permissions = const {
    PermissionCodes.fieldCreate,
    PermissionCodes.fieldView,
  },
  bool active = true,
  Set<DataScope> scopes = const {DataScope.allFarm},
}) => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm',
  permissionCodes: permissions,
  dataScopes: scopes,
  active: active,
);
LandParcel draft({String farm = 'farm', String actor = 'member'}) =>
    LandParcel.create(
      id: 'draft',
      farmId: farm,
      parcelCode: 'DRAFT',
      name: 'Lô',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.01),
        Wgs84Vertex(latitude: 16.01, longitude: 106.01),
        Wgs84Vertex(latitude: 16.01, longitude: 106),
      ]),
      boundarySource: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: actor,
      occurredAt: DateTime.utc(2026, 9, 30),
    );

void main() {
  test('GPS and imported creation require their source permissions', () {
    final repo = _Creation();
    final service = ProductionParcelCreationService(repo);
    final original = draft();
    for (final source in [BoundarySource.gps, BoundarySource.imported]) {
      final sourced = LandParcel.create(
        id: original.id,
        farmId: original.farmId,
        parcelCode: 'DRAFT',
        name: original.name,
        boundary: original.boundary,
        boundarySource: source,
        verificationStatus: BoundaryVerificationStatus.draft,
        actorMembershipId: 'member',
        occurredAt: original.createdAt,
      );
      expect(
        () => service.createLandBlock(
          subject: subject(),
          draft: sourced,
          projectCode: 'AGR-NONG',
        ),
        throwsStateError,
      );
    }
    expect(repo.calls, 0);
  });

  test(
    'crop drafts are bound to the new parcel and current membership',
    () async {
      final repo = _Creation();
      final service = ProductionParcelCreationService(repo);
      final time = DateTime.utc(2026);
      CropRecord crop(double quantity) => CropRecord(
        id: 'editor',
        parcelId: 'editor',
        cropType: ' Peanut ',
        quantity: quantity,
        unit: ' plants ',
        condition: CropCondition.unknown,
        active: true,
        ageMonths: 12,
        createdAt: time,
        updatedAt: time,
        createdBy: 'editor',
        updatedBy: 'editor',
      );
      await service.createLandBlock(
        subject: subject(),
        draft: draft(),
        projectCode: 'AGR-NONG',
        crops: [crop(2)],
      );
      final saved = repo.receivedCrops.single;
      expect(saved.id, 'crop-draft-0');
      expect(saved.parcelId, 'draft');
      expect(saved.createdBy, 'member');
      expect(saved.cropType, 'Peanut');
      expect(saved.ageMonths, 12);
      expect(
        () => service.createLandBlock(
          subject: subject(),
          draft: draft(),
          projectCode: 'AGR-NONG',
          crops: [crop(0)],
        ),
        throwsFormatException,
      );
      expect(repo.calls, 1);
    },
  );
  test(
    'authorized requests forward the parent version and fixed temporal states',
    () async {
      final repo = _Creation();
      final service = ProductionParcelCreationService(repo);
      await service.createLandBlock(
        subject: subject(),
        draft: draft(),
        projectCode: 'AGR-NONG',
      );
      expect(repo.project, 'AGR-NONG');
      expect(repo.state, SpatialTemporalState.baseline);
      await service.createFieldPlot(
        subject: subject(),
        draft: draft(),
        parentLandBlockId: 'block',
        expectedParentBoundaryVersion: 3,
      );
      expect(repo.parent, 'block');
      expect(repo.version, 3);
      expect(repo.state, SpatialTemporalState.underConstruction);
      expect(repo.calls, 2);
    },
  );
  test(
    'inactive missing permission and partial scope requests never reach persistence',
    () {
      final repo = _Creation();
      final service = ProductionParcelCreationService(repo);
      for (final denied in [
        subject(active: false),
        subject(permissions: {}),
        subject(scopes: {DataScope.own}),
      ]) {
        expect(
          () => service.createLandBlock(
            subject: denied,
            draft: draft(),
            projectCode: 'AGR-NONG',
          ),
          throwsStateError,
        );
      }
      expect(
        () => service.createFieldPlot(
          subject: subject(permissions: {PermissionCodes.fieldCreate}),
          draft: draft(),
          parentLandBlockId: 'block',
          expectedParentBoundaryVersion: 1,
        ),
        throwsStateError,
      );
      expect(repo.calls, 0);
    },
  );
  test(
    'cross farm forged actor and invalid parent version never reach persistence',
    () {
      final repo = _Creation();
      final service = ProductionParcelCreationService(repo);
      for (final invalid in [draft(farm: 'other'), draft(actor: 'other')]) {
        expect(
          () => service.createLandBlock(
            subject: subject(),
            draft: invalid,
            projectCode: 'AGR-NONG',
          ),
          throwsStateError,
        );
      }
      expect(
        () => service.createFieldPlot(
          subject: subject(),
          draft: draft(),
          parentLandBlockId: 'block',
          expectedParentBoundaryVersion: 0,
        ),
        throwsFormatException,
      );
      expect(repo.calls, 0);
    },
  );
}

class _Creation implements ProductionParcelCreationRepository {
  int calls = 0;
  List<CropRecord> receivedCrops = const [];
  String? project;
  String? parent;
  int? version;
  SpatialTemporalState? state;
  @override
  Future<LandParcel> createLandBlock({
    required LandParcel draft,
    required String projectCode,
    List<CropRecord> crops = const [],
    required SpatialTemporalState temporalState,
  }) async {
    calls++;
    project = projectCode;
    receivedCrops = crops;
    state = temporalState;
    return draft;
  }

  @override
  Future<LandParcel> createFieldPlot({
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
  }) async {
    calls++;
    parent = parentLandBlockId;
    version = expectedParentBoundaryVersion;
    state = temporalState;
    return draft;
  }
}
