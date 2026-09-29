import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late SqliteLandParcelRepository repository;
  late LandParcelApplicationService application;
  final now = DateTime.utc(2026, 9, 8, 8);
  const vertices = [
    Wgs84Vertex(latitude: 16.5, longitude: 104.7),
    Wgs84Vertex(latitude: 16.5, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.7),
  ];

  AuthorizationSubject subject({
    Set<String> permissions = PermissionCodes.values,
  }) => AuthorizationSubject(
    userId: 'user-1',
    membershipId: 'member-1',
    farmId: 'farm-1',
    permissionCodes: permissions,
    dataScopes: const {DataScope.allFarm},
  );

  LandParcel parcel({
    String id = 'parcel-1',
    BoundaryVerificationStatus status = BoundaryVerificationStatus.measured,
  }) => LandParcel.create(
    id: id,
    farmId: 'farm-1',
    parcelCode: 'CODE-$id',
    name: 'Parcel $id',
    boundary: Wgs84Polygon.fromVertices(vertices),
    boundarySource: BoundarySource.gps,
    verificationStatus: status,
    actorMembershipId: 'member-1',
    occurredAt: now,
  );

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandParcelRepository.createSchema(database);
    repository = SqliteLandParcelRepository(database);
    application = LandParcelApplicationService(repository: repository);
  });

  tearDown(() => database.close());

  test('RBAC denial occurs before validation or persistence access', () async {
    final spy = _RepositorySpy(repository);
    final service = LandParcelApplicationService(repository: spy);

    final result = await CreateLandParcel(service)(
      subject(permissions: const {}),
      CreateLandParcelCommand(
        id: 'denied',
        farmId: 'farm-1',
        parcelCode: '',
        name: '',
        vertices: const [],
        source: BoundarySource.gps,
        actorMembershipId: 'member-1',
        occurredAt: now,
      ),
    );

    expect(result.status, LandParcelApplicationStatus.permissionDenied);
    expect(spy.accessCount, 0);
  });

  test(
    'completed GPS replacement creates exactly one history version',
    () async {
      await repository.create(parcel());
      final useCase = CompleteGpsMeasurement(application);

      final result = await useCase.replace(
        subject(),
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        completedVertices: const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.702),
          Wgs84Vertex(latitude: 16.502, longitude: 104.7),
        ],
        actorMembershipId: 'member-1',
        occurredAt: now.add(const Duration(hours: 1)),
        horizontalAccuracyM: 2.5,
      );

      expect(result.isSuccess, isTrue);
      final stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored?.boundaryHistory, hasLength(2));
      expect(stored?.boundaryHistory.last.version, 2);
      expect(stored?.boundaryHistory.last.source, BoundarySource.gps);
      expect(stored?.boundaryHistory.last.horizontalAccuracyM, 2.5);
    },
  );

  test(
    'verified boundary requires confirmation and verify permission',
    () async {
      await repository.create(
        parcel(status: BoundaryVerificationStatus.verified),
      );
      final command = ReplaceBoundaryCommand(
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        vertices: vertices,
        source: BoundarySource.gps,
        actorMembershipId: 'member-1',
        occurredAt: now.add(const Duration(hours: 1)),
      );

      final confirmation = await ReplaceBoundary(application)(
        subject(),
        command,
      );
      expect(
        confirmation.status,
        LandParcelApplicationStatus.confirmationRequired,
      );

      final withoutVerify = await ReplaceBoundary(application)(
        subject(
          permissions: const {
            PermissionCodes.fieldBoundaryEdit,
            PermissionCodes.fieldMeasure,
          },
        ),
        ReplaceBoundaryCommand(
          farmId: command.farmId,
          parcelId: command.parcelId,
          vertices: command.vertices,
          source: command.source,
          actorMembershipId: command.actorMembershipId,
          occurredAt: command.occurredAt,
          confirmVerifiedReplacement: true,
        ),
      );
      expect(
        withoutVerify.status,
        LandParcelApplicationStatus.permissionDenied,
      );
      final stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored?.boundaryHistory, hasLength(1));
    },
  );
  test(
    'confirmed verified boundary replacement persists exactly one new version',
    () async {
      await repository.create(
        parcel(status: BoundaryVerificationStatus.verified),
      );

      const replacementVertices = [
        Wgs84Vertex(latitude: 16.6, longitude: 104.8),
        Wgs84Vertex(latitude: 16.6, longitude: 104.802),
        Wgs84Vertex(latitude: 16.602, longitude: 104.8),
      ];

      final replacement = Wgs84Polygon.fromVertices(replacementVertices);
      final authorizedSubject = subject();

      expect(
        authorizedSubject.permissionCodes,
        contains(PermissionCodes.fieldBoundaryVerify),
      );

      final result = await ReplaceBoundary(application)(
        authorizedSubject,
        ReplaceBoundaryCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          vertices: replacementVertices,
          source: BoundarySource.manual,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
          confirmVerifiedReplacement: true,
        ),
      );

      expect(result.isSuccess, isTrue);

      final stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');

      expect(stored?.boundaryHistory, hasLength(2));
      expect(stored?.boundaryHistory.last.version, 2);
      expect(stored?.boundaryHistory.last.boundary, replacement);
      expect(stored?.boundaryHistory.last.source, BoundarySource.manual);
      expect(stored?.boundary, replacement);
      expect(stored?.boundarySource, BoundarySource.manual);
    },
  );

  test(
    'KML preview does not mutate until ApplyImportedBoundary confirms',
    () async {
      final source = parcel();
      await repository.create(source);
      final kml = const KmlInterchangeCodec().exportKml(
        source.replaceBoundary(
          boundary: Wgs84Polygon.fromVertices(const [
            Wgs84Vertex(latitude: 16.6, longitude: 104.8),
            Wgs84Vertex(latitude: 16.6, longitude: 104.801),
            Wgs84Vertex(latitude: 16.601, longitude: 104.8),
          ]),
          source: BoundarySource.googleEarth,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
        ),
      );

      final previewResult = ImportKmlKmzPreview(
        application,
      ).kml(subject(), farmId: 'farm-1', source: kml);
      expect(previewResult.isSuccess, isTrue);
      var stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored?.boundaryHistory, hasLength(1));
      expect(stored?.boundary, source.boundary);

      final applied = await ApplyImportedBoundary(application)(
        subject(),
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        preview: previewResult.value!.previews.single,
        actorMembershipId: 'member-1',
        occurredAt: now.add(const Duration(hours: 2)),
      );
      expect(applied.isSuccess, isTrue);
      stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored?.boundaryHistory, hasLength(2));
      expect(stored?.boundarySource, BoundarySource.googleEarth);
    },
  );

  test(
    'transaction failure does not leave half-applied application state',
    () async {
      final original = parcel();
      final blocker = parcel(id: 'blocker');
      await repository.create(original);
      await repository.create(blocker);
      await database.insert(SqliteLandParcelRepository.boundaryVersionTable, {
        'id': 'parcel-1-boundary-2',
        'parcel_id': blocker.id,
        'version': 99,
        'schema_version': LandParcel.currentSchemaVersion,
        'payload_json': '{}',
      });

      final result = await ReplaceBoundary(application)(
        subject(),
        ReplaceBoundaryCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          vertices: const [
            Wgs84Vertex(latitude: 16.5, longitude: 104.7),
            Wgs84Vertex(latitude: 16.5, longitude: 104.702),
            Wgs84Vertex(latitude: 16.502, longitude: 104.7),
          ],
          source: BoundarySource.manual,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(hours: 1)),
        ),
      );

      expect(result.status, LandParcelApplicationStatus.persistenceFailed);
      final stored = await repository.getById(farmId: 'farm-1', id: 'parcel-1');
      expect(stored?.boundaryVersion, 1);
      expect(stored?.boundaryHistory, hasLength(1));
    },
  );

  test(
    'metadata, verification and export use cases flow through application',
    () async {
      await repository.create(parcel());
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
      final verified = await VerifyBoundary(application)(
        subject(),
        VerifyBoundaryCommand(
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          status: BoundaryVerificationStatus.verified,
          actorMembershipId: 'member-1',
          occurredAt: now.add(const Duration(minutes: 20)),
        ),
      );
      final exported = await ExportKmlKmz(application)(
        subject(),
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        format: LandParcelInterchangeFormat.kmz,
      );

      expect(metadata.value?.name, 'Renamed');
      expect(
        verified.value?.verificationStatus,
        BoundaryVerificationStatus.verified,
      );
      expect(exported.value?.bytes, isNotEmpty);
    },
  );

  test(
    'transaction-scoped application service commits with outer transaction',
    () async {
      final command = CreateLandParcelCommand(
        id: 'scoped-commit',
        farmId: 'farm-1',
        parcelCode: 'SCOPED-COMMIT',
        name: 'Scoped commit',
        vertices: vertices,
        source: BoundarySource.gps,
        actorMembershipId: 'member-1',
        occurredAt: now,
      );

      await database.transaction((transaction) async {
        final scopedRepository = SqliteLandParcelRepository(transaction);
        final scopedApplication = application.withRepository(scopedRepository);

        final result = await scopedApplication.createLandParcel(
          subject(),
          command,
        );

        expect(result.isSuccess, isTrue);
      });

      final stored = await repository.getById(
        farmId: 'farm-1',
        id: 'scoped-commit',
      );

      expect(stored, isNotNull);
      expect(stored?.boundaryHistory, hasLength(1));
    },
  );

  test(
    'outer transaction failure rolls back scoped application create',
    () async {
      final command = CreateLandParcelCommand(
        id: 'scoped-rollback',
        farmId: 'farm-1',
        parcelCode: 'SCOPED-ROLLBACK',
        name: 'Scoped rollback',
        vertices: vertices,
        source: BoundarySource.gps,
        actorMembershipId: 'member-1',
        occurredAt: now,
      );

      await expectLater(
        () => database.transaction<void>((transaction) async {
          final scopedRepository = SqliteLandParcelRepository(transaction);
          final scopedApplication = application.withRepository(
            scopedRepository,
          );

          final result = await scopedApplication.createLandParcel(
            subject(),
            command,
          );

          expect(result.isSuccess, isTrue);
          throw StateError('force outer rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final stored = await repository.getById(
        farmId: 'farm-1',
        id: 'scoped-rollback',
      );
      final boundaryRows = await database.query(
        SqliteLandParcelRepository.boundaryVersionTable,
        where: 'parcel_id = ?',
        whereArgs: const ['scoped-rollback'],
      );

      expect(stored, isNull);
      expect(boundaryRows, isEmpty);
    },
  );

  test(
    'outer transaction failure rolls back scoped application update',
    () async {
      await repository.create(parcel(id: 'scoped-update'));

      final before = await repository.getById(
        farmId: 'farm-1',
        id: 'scoped-update',
      );

      expect(before, isNotNull);

      await expectLater(
        () => database.transaction<void>((transaction) async {
          final scopedRepository = SqliteLandParcelRepository(transaction);
          final scopedApplication = application.withRepository(
            scopedRepository,
          );

          final result = await scopedApplication.updateLandParcelMetadata(
            subject(),
            UpdateLandParcelMetadataCommand(
              farmId: 'farm-1',
              parcelId: 'scoped-update',
              actorMembershipId: 'member-1',
              occurredAt: now.add(const Duration(hours: 1)),
              name: 'Changed inside transaction',
            ),
          );

          expect(result.isSuccess, isTrue);
          throw StateError('force outer rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final after = await repository.getById(
        farmId: 'farm-1',
        id: 'scoped-update',
      );

      expect(after, isNotNull);
      expect(after?.name, before?.name);
      expect(after?.updatedAt, before?.updatedAt);
      expect(after?.updatedBy, before?.updatedBy);
      expect(after?.boundaryHistory, hasLength(1));
    },
  );

  test('atomic persistence guard ignores non-persistence failure', () {
    const result = LandParcelApplicationResult<LandParcel>.failure(
      LandParcelApplicationStatus.validationFailed,
      'landParcel.geometry.invalid',
    );

    expect(result.requireSuccessForAtomicPersistence, returnsNormally);
  });

  test('atomic persistence guard rethrows persistence failure', () {
    const result = LandParcelApplicationResult<LandParcel>.failure(
      LandParcelApplicationStatus.persistenceFailed,
      'landParcel.persistence.failed',
    );

    expect(
      result.requireSuccessForAtomicPersistence,
      throwsA(
        isA<LandParcelAtomicPersistenceException>()
            .having(
              (error) => error.result.status,
              'status',
              LandParcelApplicationStatus.persistenceFailed,
            )
            .having(
              (error) => error.result.messageKey,
              'messageKey',
              'landParcel.persistence.failed',
            ),
      ),
    );
  });

  test('atomic persistence guard rolls back outer transaction', () async {
    final command = CreateLandParcelCommand(
      id: 'atomic-guard-rollback',
      farmId: 'farm-1',
      parcelCode: 'ATOMIC-GUARD',
      name: 'Atomic guard rollback',
      vertices: vertices,
      source: BoundarySource.gps,
      actorMembershipId: 'member-1',
      occurredAt: now,
    );

    LandParcelApplicationResult<LandParcel>? capturedResult;

    await expectLater(
      () => database.transaction<void>((transaction) async {
        final scopedRepository = SqliteLandParcelRepository(transaction);
        final scopedApplication = application.withRepository(scopedRepository);

        final created = await scopedApplication.createLandParcel(
          subject(),
          command,
        );

        expect(created.isSuccess, isTrue);

        final persistenceFailure =
            LandParcelApplicationResult<LandParcel>.failure(
              LandParcelApplicationStatus.persistenceFailed,
              'landParcel.persistence.failed',
              error: StateError('simulated downstream persistence failure'),
            );

        capturedResult = persistenceFailure;
        persistenceFailure.requireSuccessForAtomicPersistence();
      }),
      throwsA(isA<LandParcelAtomicPersistenceException>()),
    );

    expect(
      capturedResult?.status,
      LandParcelApplicationStatus.persistenceFailed,
    );

    final stored = await repository.getById(
      farmId: 'farm-1',
      id: 'atomic-guard-rollback',
    );

    final boundaryRows = await database.query(
      SqliteLandParcelRepository.boundaryVersionTable,
      where: 'parcel_id = ?',
      whereArgs: const ['atomic-guard-rollback'],
    );

    expect(stored, isNull);
    expect(boundaryRows, isEmpty);
  });
}

class _RepositorySpy implements LandParcelRepository {
  _RepositorySpy(this.delegate);
  final LandParcelRepository delegate;
  int accessCount = 0;

  T _access<T>(T value) {
    accessCount++;
    return value;
  }

  @override
  Future<void> create(LandParcel parcel) => _access(delegate.create(parcel));
  @override
  Future<LandParcel?> getById({required String farmId, required String id}) =>
      _access(delegate.getById(farmId: farmId, id: id));
  @override
  Future<LandParcel?> getByParcelCode({
    required String farmId,
    required String parcelCode,
  }) =>
      _access(delegate.getByParcelCode(farmId: farmId, parcelCode: parcelCode));
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) => _access(delegate.listByFarm(farmId, includeInactive: includeInactive));
  @override
  Future<void> saveBoundaryVersion(LandParcelBoundaryVersion version) =>
      _access(delegate.saveBoundaryVersion(version));
  @override
  Future<void> setActive({
    required String farmId,
    required String id,
    required bool active,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) => _access(
    delegate.setActive(
      farmId: farmId,
      id: id,
      active: active,
      actorMembershipId: actorMembershipId,
      occurredAt: occurredAt,
    ),
  );
  @override
  Future<T> transaction<T>(
    Future<T> Function(LandParcelRepository repository) action,
  ) => _access(delegate.transaction(action));
  @override
  Future<void> update(LandParcel parcel) => _access(delegate.update(parcel));
}
