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
  test('editing persists metadata and links without changing identity or status', () async {
    await repository.create(task(machineId: 'machine-1'));
    await repository.complete(farmId: 'farm-1', id: 'task-1');
    await database.update(SqliteParcelWorkRepository.resourcesTable,
      {'active': 0}, where: 'id = ?', whereArgs: ['machine-1']);
    final original = (await repository.listByFarm('farm-1')).single;
    final changed = FarmTask(id: original.id, farmId: original.farmId,
      title: 'Đã sửa', description: 'Ghi chú mới', status: FarmTaskStatus.pending,
      dueAt: due.add(const Duration(days: 2)), createdAt: DateTime(2000),
      machineResourceId: 'machine-1', workerResourceId: 'worker-1');
    const updater = AuthorizationSubject(userId: 'user', membershipId: 'member',
      farmId: 'farm-1', permissionCodes: {PermissionCodes.taskEdit},
      dataScopes: {DataScope.allFarm});
    await FarmTaskService(repository).update(updater, changed);
    final saved = (await SqliteFarmTaskRepository(database).listByFarm('farm-1')).single;
    expect(saved.title, 'Đã sửa');
    expect(saved.description, 'Ghi chú mới');
    expect(saved.dueAt, changed.dueAt);
    expect(saved.createdAt, original.createdAt);
    expect(saved.status, FarmTaskStatus.completed);
    expect(saved.machineResourceId, 'machine-1');
    expect(saved.workerResourceId, 'worker-1');
    await repository.update(task());
    final cleared = (await repository.listByFarm('farm-1')).single;
    expect(cleared.machineResourceId, isNull);
    expect(cleared.workerResourceId, isNull);
    expect(cleared.status, FarmTaskStatus.completed);
  });

  test('editing rejects denied access, wrong farm and unavailable links atomically', () async {
    await repository.create(task());
    final service = FarmTaskService(repository);
    expect(() => service.update(editor, task()), throwsStateError);
    const denied = AuthorizationSubject(userId: 'user', membershipId: 'member',
      farmId: 'farm-1', permissionCodes: {PermissionCodes.taskEdit},
      permissionScopes: {PermissionCodes.taskEdit: <DataScope>{}}, dataScopes: {DataScope.allFarm});
    expect(() => service.update(denied, task()), throwsStateError);
    await expectLater(repository.update(task(farmId: 'farm-2')), throwsStateError);
    await expectLater(repository.update(task(machineId: 'worker-1')), throwsStateError);
    await expectLater(repository.update(task(workerId: 'other-worker')), throwsStateError);
    await database.update(SqliteParcelWorkRepository.resourcesTable,
      {'active': 0}, where: 'id = ?', whereArgs: ['machine-1']);
    await expectLater(repository.update(task(machineId: 'machine-1')), throwsStateError);
    final unchanged = (await repository.listByFarm('farm-1')).single;
    expect(unchanged.title, 'Dọn thực bì');
    expect(unchanged.machineResourceId, isNull);
    expect(unchanged.workerResourceId, isNull);
  });

  test('status transitions persist and completed tasks cannot reopen', () async {
    await repository.create(task(machineId: 'machine-1'));
    final original = (await repository.listByFarm('farm-1')).single;
    for (final status in [FarmTaskStatus.inProgress, FarmTaskStatus.delayed,
        FarmTaskStatus.inProgress]) {
      await repository.changeStatus(farmId: 'farm-1', id: 'task-1', status: status);
      final saved = (await SqliteFarmTaskRepository(database).listByFarm('farm-1')).single;
      expect(saved.status, status);
      expect(saved.title, original.title);
      expect(saved.createdAt, original.createdAt);
      expect(saved.machineResourceId, original.machineResourceId);
      await expectLater(repository.changeStatus(farmId: 'farm-1', id: 'task-1',
        status: status), throwsStateError);
    }
    await repository.complete(farmId: 'farm-1', id: 'task-1');
    await expectLater(repository.changeStatus(farmId: 'farm-1', id: 'task-1',
      status: FarmTaskStatus.inProgress), throwsStateError);
    expect((await repository.listByFarm('farm-1')).single.status, FarmTaskStatus.completed);
  });

  test('status changes enforce permission, farm and separate completion', () async {
    await repository.create(task());
    final service = FarmTaskService(repository);
    expect(() => service.changeStatus(editor, 'task-1', FarmTaskStatus.inProgress),
      throwsStateError);
    const updater = AuthorizationSubject(userId: 'user', membershipId: 'member',
      farmId: 'farm-1', permissionCodes: {PermissionCodes.taskEdit},
      dataScopes: {DataScope.allFarm});
    const denied = AuthorizationSubject(userId: 'user', membershipId: 'member',
      farmId: 'farm-1', permissionCodes: {PermissionCodes.taskEdit},
      permissionScopes: {PermissionCodes.taskEdit: <DataScope>{}},
      dataScopes: {DataScope.allFarm});
    expect(() => service.changeStatus(denied, 'task-1', FarmTaskStatus.inProgress),
      throwsStateError);
    expect(() => service.changeStatus(updater, 'task-1', FarmTaskStatus.completed),
      throwsFormatException);
    expect(() => service.changeStatus(updater, '', FarmTaskStatus.inProgress),
      throwsFormatException);
    await expectLater(repository.changeStatus(farmId: 'farm-2', id: 'task-1',
      status: FarmTaskStatus.inProgress), throwsStateError);
    await expectLater(repository.changeStatus(farmId: 'farm-1', id: 'missing',
      status: FarmTaskStatus.inProgress), throwsStateError);
    await expectLater(repository.changeStatus(farmId: 'farm-1', id: 'task-1',
      status: FarmTaskStatus.completed), throwsFormatException);
    await expectLater(repository.changeStatus(farmId: 'farm-1', id: 'task-1',
      status: FarmTaskStatus.pending), throwsFormatException);
    expect((await repository.listByFarm('farm-1')).single.status, FarmTaskStatus.pending);
    await service.changeStatus(updater, 'task-1', FarmTaskStatus.inProgress);
    expect((await repository.listByFarm('farm-1')).single.status, FarmTaskStatus.inProgress);
  });

  test('overdue uses local calendar days and excludes completed tasks', () {
    final today = DateTime(2026, 10, 7, 23, 59);
    FarmTask dated(DateTime dueAt, FarmTaskStatus status) => FarmTask(
      id: 'dated', farmId: 'farm-1', title: 'Kiểm tra hạn', description: '',
      status: status, dueAt: dueAt, createdAt: DateTime(2026, 10, 1));
    for (final status in FarmTaskStatus.values) {
      expect(dated(DateTime(2026, 10, 6, 23, 59), status).isOverdueOn(today),
        status != FarmTaskStatus.completed);
      expect(dated(DateTime(2026, 10, 7), status).isOverdueOn(today), isFalse);
      expect(dated(DateTime(2026, 10, 8), status).isOverdueOn(today), isFalse);
    }
  });

}
