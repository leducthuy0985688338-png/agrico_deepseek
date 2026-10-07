import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/task_work_service.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_farm_task_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_task_work_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/farm_task.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database db;
  late Database costs;
  late SqliteTaskWorkRepository links;
  late SqliteFarmTaskRepository tasks;
  late SqliteParcelWorkRepository work;
  final now = DateTime.utc(2026, 10, 7);

  FarmTask task({String parcel = 'parcel-1'}) => FarmTask(
    id: 'task-1',
    farmId: 'farm-1',
    title: 'Khai hoang',
    description: 'ວຽກ · Công việc',
    status: FarmTaskStatus.pending,
    dueAt: now,
    createdAt: now,
    parcelId: parcel,
  );
  ParcelWorkEvent event(
    String id, {
    String farm = 'farm-1',
    String parcel = 'parcel-1',
    String actor = 'member',
    String machine = 'machine-1',
  }) => ParcelWorkEvent(
    id: id,
    farmId: farm,
    parcelId: parcel,
    phase: ParcelWorkPhase.clearing,
    description: 'ວຽກ · Dọn đất',
    occurredAt: now,
    actorMembershipId: actor,
    machineIds: [machine],
    workerIds: const [],
    areaM2: 500,
  );
  AuthorizationSubject subject({
    Set<String> permissions = const {
      PermissionCodes.taskView,
      PermissionCodes.fieldView,
      PermissionCodes.fieldEdit,
    },
    Set<DataScope> scopes = const {DataScope.allFarm},
    bool active = true,
    DateTime? until,
    Map<String, Set<DataScope>> overrides = const {},
  }) => AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm-1',
    permissionCodes: permissions,
    dataScopes: scopes,
    active: active,
    validUntil: until ?? DateTime.now().add(const Duration(hours: 1)),
    permissionScopes: overrides,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agrico-task-work-');
    db = await databaseFactoryFfi.openDatabase('${directory.path}/agrico.db');
    costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    await costs.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY)');
    await db.execute('PRAGMA foreign_keys = ON');
    await SqliteFarmTaskRepository.createSchema(db);
    links = SqliteTaskWorkRepository(db);
    tasks = SqliteFarmTaskRepository(db);
    work = SqliteParcelWorkRepository(db);
    for (final id in ['parcel-1', 'parcel-2']) {
      await db.insert('land_parcels', {
        'id': id,
        'farm_id': 'farm-1',
        'parcel_code': id,
        'active': 1,
        'boundary_version': 1,
        'schema_version': 3,
        'payload_json': '{}',
        'kind': 'fieldPlot',
        'parent_block_id': null,
      });
    }
    await work.register(
      const WorkResource(
        id: 'machine-1',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M1',
        name: 'Máy khai hoang',
      ),
    );
    await tasks.create(task());
  });
  tearDown(() async {
    if (db.isOpen) await db.close();
    if (costs.isOpen) await costs.close();
    await directory.delete(recursive: true);
  });

  Future<Uint8List> snapshot() =>
      LocalDatabaseSnapshot.create(db, costsDatabase: costs);
  Future<Map<String, int>> validate(Uint8List bytes) =>
      LocalRestorePreflight.validate(
        bytes: bytes,
        primary: db,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );
  Future<void> apply(Uint8List bytes) async {
    await db.close();
    await costs.close();
    final activation = LocalRestoreActivation(directory, databaseFactoryFfi);
    await activation.schedule(bytes);
    expect(await activation.applyPending(), isTrue);
    db = await databaseFactoryFfi.openDatabase('${directory.path}/agrico.db');
    costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    links = SqliteTaskWorkRepository(db);
    tasks = SqliteFarmTaskRepository(db);
    work = SqliteParcelWorkRepository(db);
  }

  test(
    'records several executions without completing or duplicating a task',
    () async {
      await work.record(event('independent'));
      await links.record('task-1', event('execution-1'));
      await links.record('task-1', event('execution-2'));
      final reopened = SqliteTaskWorkRepository(db);
      expect((await reopened.events('farm-1', 'task-1')).map((e) => e.id), [
        'execution-1',
        'execution-2',
      ]);
      expect((await work.events('farm-1', 'parcel-1')).length, 3);
      expect(
        (await tasks.listByFarm('farm-1')).single.status,
        FarmTaskStatus.pending,
      );
      await expectLater(
        links.record('task-1', event('execution-1')),
        throwsA(isA<Exception>()),
      );
      expect((await db.query(SqliteTaskWorkRepository.linksTable)).length, 2);
      await tasks.complete(farmId: 'farm-1', id: 'task-1');
      expect((await reopened.events('farm-1', 'task-1')).length, 2);
    },
  );

  test(
    'rejects missing task, wrong farm, wrong parcel and unavailable resource',
    () async {
      for (final attempt in [
        ('missing', event('missing')),
        ('task-1', event('foreign', farm: 'farm-2')),
        ('task-1', event('different-parcel', parcel: 'parcel-2')),
        ('task-1', event('bad-resource', machine: 'unknown')),
      ]) {
        await expectLater(
          links.record(attempt.$1, attempt.$2),
          throwsStateError,
        );
      }
      await db.update('parcel_work_resources', {'active': 0});
      await expectLater(
        links.record('task-1', event('inactive')),
        throwsStateError,
      );
      expect(await db.query('parcel_work_events'), isEmpty);
      expect(await db.query('parcel_work_assignments'), isEmpty);
      expect(await db.query(SqliteTaskWorkRepository.linksTable), isEmpty);
      await expectLater(links.events('other-farm', 'task-1'), throwsStateError);
    },
  );

  test(
    'link insertion failure rolls back the event and its assignments',
    () async {
      await db.execute('''CREATE TRIGGER reject_task_work_link
      BEFORE INSERT ON farm_task_work_links_v1
      BEGIN SELECT RAISE(ABORT, 'test failure'); END''');
      await expectLater(
        links.record('task-1', event('rollback')),
        throwsA(isA<Exception>()),
      );
      expect(await db.query('parcel_work_events'), isEmpty);
      expect(await db.query('parcel_work_assignments'), isEmpty);
      expect(await db.query(SqliteTaskWorkRepository.linksTable), isEmpty);
    },
  );

  test(
    'linked tasks retain their parcel while other metadata can change',
    () async {
      await links.record('task-1', event('execution'));
      await expectLater(
        tasks.update(task(parcel: 'parcel-2')),
        throwsStateError,
      );
      final previous = task();
      await expectLater(
        tasks.update(
          FarmTask(
            id: previous.id,
            farmId: previous.farmId,
            title: previous.title,
            description: previous.description,
            status: previous.status,
            dueAt: now,
            createdAt: now,
          ),
        ),
        throwsStateError,
      );
      await tasks.update(
        FarmTask(
          id: previous.id,
          farmId: previous.farmId,
          title: 'Tên mới',
          description: previous.description,
          status: previous.status,
          dueAt: now,
          createdAt: now,
          parcelId: previous.parcelId,
        ),
      );
      expect((await tasks.listByFarm('farm-1')).single.title, 'Tên mới');
      expect((await links.events('farm-1', 'task-1')).single.id, 'execution');
    },
  );

  test(
    'service enforces live permissions, full scope and work actor',
    () async {
      final service = TaskWorkService(links);
      for (final denied in [
        subject(permissions: {PermissionCodes.fieldEdit}),
        subject(permissions: {PermissionCodes.taskView}),
        subject(scopes: {DataScope.own}),
        subject(active: false),
        subject(until: DateTime.now().subtract(const Duration(seconds: 1))),
        subject(overrides: {PermissionCodes.fieldEdit: {}}),
      ]) {
        expect(
          () => service.record(denied, 'task-1', event('denied')),
          throwsStateError,
        );
      }
      expect(
        () =>
            service.record(subject(), 'task-1', event('actor', actor: 'other')),
        throwsStateError,
      );
      expect(
        () => service.record(subject(), '', event('blank')),
        throwsFormatException,
      );
      expect(
        () => service.events(
          subject(permissions: {PermissionCodes.taskView}),
          'task-1',
        ),
        throwsStateError,
      );
      await service.record(subject(), 'task-1', event('allowed'));
      expect((await service.events(subject(), 'task-1')).single.id, 'allowed');
      expect(
        (await tasks.listByFarm('farm-1')).single.status,
        FarmTaskStatus.pending,
      );
    },
  );

  test('schema addition is repeatable and preserves existing work', () async {
    await work.record(event('independent'));
    await db.execute('DROP TABLE farm_task_work_links_v1');
    await SqliteFarmTaskRepository.createSchema(db);
    await SqliteFarmTaskRepository.createSchema(db);
    expect((await work.events('farm-1', 'parcel-1')).single.id, 'independent');
    expect((await tasks.listByFarm('farm-1')).length, 1);
    expect(await db.query(SqliteTaskWorkRepository.linksTable), isEmpty);
  });

  test(
    'snapshot preflight and startup restore retain task work links',
    () async {
      await links.record('task-1', event('saved'));
      final bytes = await snapshot();
      expect((await validate(bytes))['agrico.db/farm_task_work_links_v1'], 1);
      await links.record('task-1', event('later'));
      await apply(bytes);
      expect((await links.events('farm-1', 'task-1')).single.id, 'saved');
      expect(
        (await work.events('farm-1', 'parcel-1')).single.description,
        'ວຽກ · Dọn đất',
      );
      expect(
        (await tasks.listByFarm('farm-1')).single.status,
        FarmTaskStatus.pending,
      );
    },
  );

  test(
    'old snapshot without links restores with no leftover current links',
    () async {
      await work.record(event('independent'));
      final bytes = rewrite(await snapshot(), (tables) {
        tables.remove(SqliteTaskWorkRepository.linksTable);
      });
      await validate(bytes);
      await links.record('task-1', event('later'));
      await apply(bytes);
      expect(await links.events('farm-1', 'task-1'), isEmpty);
      expect(
        (await work.events('farm-1', 'parcel-1')).single.id,
        'independent',
      );
    },
  );

  test(
    'preflight rejects cross-farm or cross-parcel links despite valid IDs',
    () async {
      await links.record('task-1', event('saved'));
      final original = await snapshot();
      for (final wrongFarm in [false, true]) {
        final bytes = rewrite(original, (tables) {
          final row = (tables['farm_tasks_v2'] as List).single as Map;
          row[wrongFarm ? 'farm_id' : 'parcel_id'] = wrongFarm
              ? 'farm-2'
              : 'parcel-2';
        });
        await expectLater(
          validate(bytes),
          throwsA(
            isA<RestorePreflightException>()
                .having((e) => e.reason, 'reason', 'integrity')
                .having((e) => e.step, 'step', 'task work links'),
          ),
        );
      }
      expect((await links.events('farm-1', 'task-1')).single.id, 'saved');
    },
  );
}

Uint8List rewrite(Uint8List bytes, void Function(Map<String, dynamic>) change) {
  final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final payload =
      jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
  final databases = payload['databases'] as Map<String, dynamic>;
  change(
    (databases['agrico.db'] as Map<String, dynamic>)['tables']
        as Map<String, dynamic>,
  );
  final body = jsonEncode(payload);
  envelope['payload'] = body;
  envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}
