import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/farm_task_service.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/farm_task.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late SqliteFarmTaskRepository repository;
  final due = DateTime.utc(2026, 10, 1, 8);

  const editor = AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm-1',
    permissionCodes: {PermissionCodes.taskView, PermissionCodes.taskCreate},
    dataScopes: {DataScope.allFarm},
  );

  FarmTask task({
    String farmId = 'farm-1',
    String? workerId,
    String? machineId,
  }) => FarmTask(
    id: 'task-1',
    farmId: farmId,
    title: 'Dọn thực bì',
    description: 'Chuẩn bị lô đất',
    status: FarmTaskStatus.pending,
    dueAt: due,
    createdAt: DateTime.utc(2026, 9, 29),
    workerResourceId: workerId,
    machineResourceId: machineId,
  );

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteFarmTaskRepository.createSchema(database);
    repository = SqliteFarmTaskRepository(database);
    final resources = SqliteParcelWorkRepository(database);
    await resources.register(
      const WorkResource(
        id: 'worker-1',
        farmId: 'farm-1',
        kind: WorkResourceKind.worker,
        code: 'W001',
        name: 'Nhân công',
      ),
    );
    await resources.register(
      const WorkResource(
        id: 'machine-1',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M001',
        name: 'Máy cày',
      ),
    );
    await resources.register(
      const WorkResource(
        id: 'other-worker',
        farmId: 'farm-2',
        kind: WorkResourceKind.worker,
        code: 'W001',
        name: 'Nhân công khác',
      ),
    );
  });
  tearDown(() => database.close());

  test('reopens a farm task with catalog resource identities', () async {
    await FarmTaskService(
      repository,
    ).create(editor, task(workerId: 'worker-1', machineId: 'machine-1'));
    final reopened = SqliteFarmTaskRepository(database);
    final result = (await reopened.listByFarm('farm-1')).single;
    expect(result.title, 'Dọn thực bì');
    expect(result.status, FarmTaskStatus.pending);
    expect(result.dueAt, due);
    expect(result.workerResourceId, 'worker-1');
    expect(result.machineResourceId, 'machine-1');
    expect(await reopened.listByFarm('farm-2'), isEmpty);
  });

  test('invalid resource kind or farm does not insert a task', () async {
    await expectLater(
      repository.create(task(machineId: 'worker-1')),
      throwsStateError,
    );
    await expectLater(
      repository.create(task(workerId: 'other-worker')),
      throwsStateError,
    );
    expect(await repository.listByFarm('farm-1'), isEmpty);
  });

  test('application rejects another farm and missing permissions', () async {
    final service = FarmTaskService(repository);
    expect(
      () => service.create(editor, task(farmId: 'farm-2')),
      throwsStateError,
    );
    const viewer = AuthorizationSubject(
      userId: 'viewer',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.taskView},
      dataScopes: {DataScope.allFarm},
    );
    expect(() => service.create(viewer, task()), throwsStateError);
    expect(await service.list(viewer), isEmpty);
    expect(await repository.listByFarm('farm-1'), isEmpty);
  });

  test('completion persists once and is scoped to the current farm', () async {
    final service = FarmTaskService(repository);
    const completer = AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.taskComplete},
      dataScopes: {DataScope.allFarm},
    );
    const otherFarm = AuthorizationSubject(
      userId: 'other',
      membershipId: 'member',
      farmId: 'farm-2',
      permissionCodes: {PermissionCodes.taskComplete},
      dataScopes: {DataScope.allFarm},
    );
    await repository.create(task());
    expect(() => service.complete(editor, 'task-1'), throwsStateError);
    await expectLater(service.complete(otherFarm, 'task-1'), throwsStateError);
    expect(
      (await repository.listByFarm('farm-1')).single.status,
      FarmTaskStatus.pending,
    );
    await service.complete(completer, 'task-1');
    expect(
      (await SqliteFarmTaskRepository(
        database,
      ).listByFarm('farm-1')).single.status,
      FarmTaskStatus.completed,
    );
    await expectLater(service.complete(completer, 'task-1'), throwsStateError);
    await expectLater(service.complete(completer, 'missing'), throwsStateError);
    expect(
      (await repository.listByFarm('farm-1')).single.status,
      FarmTaskStatus.completed,
    );
  });
}
