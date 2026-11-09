import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/farm_task_service.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/application/task_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/farm_task.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/farm_task_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/task_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/controllers/farm_task_controller.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/farm_task_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/parcel_work_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const permissions = {
  PermissionCodes.taskView,
  PermissionCodes.fieldView,
  PermissionCodes.fieldEdit,
  PermissionCodes.catalogView,
};
AuthorizationSubject subject({
  Set<String> codes = permissions,
  Map<String, Set<DataScope>> overrides = const {},
}) => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm-1',
  permissionCodes: codes,
  dataScopes: const {DataScope.allFarm},
  permissionScopes: overrides,
);
FarmTask task({
  String? parcelId = 'parcel-1',
  String description = 'Dọn thực bì',
}) => FarmTask(
  id: 'task-1',
  farmId: 'farm-1',
  title: 'Khai hoang lô A',
  description: description,
  status: FarmTaskStatus.pending,
  dueAt: DateTime(2026, 10, 7),
  createdAt: DateTime(2026, 10, 1),
  parcelId: parcelId,
  machineResourceId: 'm1',
  workerResourceId: 'inactive',
);
Widget app(Widget screen) => MaterialApp(
  locale: const Locale('vi'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: screen,
);

void main() {
  testWidgets('read-only task history opens without a form or writes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasks = _Tasks(task());
    final work = _Work();
    final linked = _Links(work);
    final event = ParcelWorkEvent(
      id: 'history-1',
      farmId: 'farm-1',
      parcelId: 'parcel-1',
      phase: ParcelWorkPhase.clearing,
      description: 'Lần thực hiện đã lưu',
      occurredAt: DateTime(2026, 10, 7),
      actorMembershipId: 'member',
      machineIds: const ['m1'],
      workerIds: const [],
    );
    linked.saved.add(('task-1', event));
    linked.saved.add((
      'other-task',
      ParcelWorkEvent(
        id: 'history-2',
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.clearing,
        description: 'Thực hiện tác vụ khác',
        occurredAt: DateTime(2026, 10, 7),
        actorMembershipId: 'member',
        machineIds: const ['m1'],
        workerIds: const [],
      ),
    ));
    final controller = FarmTaskController(
      subject: subject(
        codes: permissions.difference({PermissionCodes.fieldEdit}),
      ),
      service: FarmTaskService(tasks),
    );
    await controller.load();
    await tester.pumpWidget(
      app(
        FarmTaskScreen(
          controller: controller,
          resources: ParcelWorkService(work),
          parcels: const [],
          taskWork: TaskWorkService(linked),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-details-task-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-task-record-work')), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-view-work')));
    await tester.pumpAndSettle();
    expect(find.byType(ParcelWorkScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Lần thực hiện đã lưu'), findsOneWidget);
    expect(find.textContaining('Thực hiện tác vụ khác'), findsNothing);
    expect(find.byKey(const Key('work-add-event')), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(linked.saved, hasLength(2));
    expect(tasks.current.status, FarmTaskStatus.pending);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('history action respects explicit read scopes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final work = _Work();
    final controller = FarmTaskController(
      subject: subject(overrides: {PermissionCodes.fieldView: {}}),
      service: FarmTaskService(_Tasks(task())),
    );
    await controller.load();
    await tester.pumpWidget(
      app(
        FarmTaskScreen(
          controller: controller,
          resources: ParcelWorkService(work),
          parcels: const [],
          taskWork: TaskWorkService(_Links(work)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-details-task-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-task-view-work')), findsNothing);
    expect(find.byKey(const Key('farm-task-record-work')), findsNothing);
    expect(find.byKey(const Key('farm-task-view-work')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'task action opens prefilled work, cancel writes nothing, save keeps status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tasks = _Tasks(task());
      final work = _Work();
      final linked = _Links(work);
      final controller = FarmTaskController(
        subject: subject(),
        service: FarmTaskService(tasks),
      );
      await controller.load();
      await tester.pumpWidget(
        app(
          FarmTaskScreen(
            controller: controller,
            resources: ParcelWorkService(work),
            parcels: const [],
            taskWork: TaskWorkService(linked),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('farm-task-details-task-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('farm-task-record-work')));
      await tester.pumpAndSettle();
      expect(find.byType(ParcelWorkScreen), findsOneWidget);
      expect(find.byKey(const Key('work-source-task')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Dọn thực bì',
      );
      expect(find.text('NV0 · Đội ngừng hoạt động'), findsNothing);
      final selected = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((item) => item.value == true);
      expect(selected.length, 1);
      expect(find.text('M1 · Máy khai hoang'), findsOneWidget);
      await tester.tap(find.byKey(const Key('work-cancel-event')));
      await tester.pumpAndSettle();
      expect(linked.saved, isEmpty);
      expect(work.saved, isEmpty);
      await tester.tap(find.byKey(const Key('work-add-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '500');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('work-save-event')));
      await tester.pumpAndSettle();
      expect(linked.saved.length, 1);
      final (taskId, event) = linked.saved.single;
      expect(taskId, 'task-1');
      expect(event.parcelId, 'parcel-1');
      expect(event.farmId, 'farm-1');
      expect(event.actorMembershipId, 'member');
      expect(event.description, 'Dọn thực bì');
      expect(event.machineIds, ['m1']);
      expect(event.workerIds, isEmpty);
      expect(event.areaM2, 500);
      expect(work.saved.length, 1);
      expect(tasks.current.status, FarmTaskStatus.pending);
      expect(tasks.writes, 0);
      expect(find.textContaining('Dọn thực bì'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(linked.saved.length, 1);
      expect(find.textContaining('Dọn thực bì'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'task action is hidden without field edit or with explicit scope denial',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final member in [
        subject(
          codes: {
            PermissionCodes.taskView,
            PermissionCodes.fieldView,
            PermissionCodes.catalogView,
          },
        ),
        subject(overrides: {PermissionCodes.fieldEdit: {}}),
      ]) {
        final work = _Work();
        final controller = FarmTaskController(
          subject: member,
          service: FarmTaskService(_Tasks(task())),
        );
        await controller.load();
        await tester.pumpWidget(
          app(
            FarmTaskScreen(
              controller: controller,
              resources: ParcelWorkService(work),
              parcels: const [],
              taskWork: TaskWorkService(_Links(work)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('farm-task-details-task-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('farm-task-record-work')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets('a task without a parcel cannot open linked work', (
    tester,
  ) async {
    final work = _Work();
    final controller = FarmTaskController(
      subject: subject(),
      service: FarmTaskService(_Tasks(task(parcelId: null))),
    );
    await controller.load();
    await tester.pumpWidget(
      app(
        FarmTaskScreen(
          controller: controller,
          resources: ParcelWorkService(work),
          parcels: const [],
          taskWork: TaskWorkService(_Links(work)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-details-task-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-task-record-work')), findsNothing);
    expect(find.byKey(const Key('farm-task-view-work')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'empty description falls back to task title and save requires a resource',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final work = _Work();
      final linked = _Links(work);
      await tester.pumpWidget(
        app(
          ParcelWorkScreen(
            parcelId: 'parcel-1',
            subject: subject(),
            service: ParcelWorkService(work),
            initialTask: task(description: ''),
            taskWork: TaskWorkService(linked),
            openEventOnLoad: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Khai hoang lô A',
      );
      final machine = find.byType(CheckboxListTile).first;
      await tester.ensureVisible(machine);
      await tester.tap(machine);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('work-save-event')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('work-cancel-event')));
      await tester.pumpAndSettle();
      expect(linked.saved, isEmpty);
    },
  );
}

class _Tasks implements FarmTaskRepository {
  _Tasks(this.current);
  FarmTask current;
  int writes = 0;
  @override
  Future<List<FarmTask>> listByFarm(String farmId) async => [current];
  @override
  Future<void> create(FarmTask task) async {
    writes++;
  }

  @override
  Future<void> update(FarmTask task) async {
    writes++;
  }

  @override
  Future<void> complete({required String farmId, required String id}) async {
    writes++;
  }

  @override
  Future<void> changeStatus({
    required String farmId,
    required String id,
    required FarmTaskStatus status,
  }) async {
    writes++;
  }
}

class _Work implements ParcelWorkRepository {
  final saved = <ParcelWorkEvent>[];
  final items = <WorkResource>[
    const WorkResource(
      id: 'm1',
      farmId: 'farm-1',
      kind: WorkResourceKind.machine,
      code: 'M1',
      name: 'Máy khai hoang',
    ),
    const WorkResource(
      id: 'inactive',
      farmId: 'farm-1',
      kind: WorkResourceKind.worker,
      code: 'NV0',
      name: 'Đội ngừng hoạt động',
      active: false,
    ),
  ];
  @override
  Future<List<WorkResource>> resources(String farmId) async => items;
  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      saved;
  @override
  Future<void> record(ParcelWorkEvent event) async {
    saved.add(event);
  }

  @override
  Future<void> register(WorkResource resource) async {
    items.add(resource);
  }

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    items.addAll(resources);
  }
}

class _Links implements TaskWorkRepository {
  _Links(this.work);
  final _Work work;
  final saved = <(String, ParcelWorkEvent)>[];
  @override
  Future<void> record(String taskId, ParcelWorkEvent event) async {
    saved.add((taskId, event));
    await work.record(event);
  }

  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String taskId) async =>
      saved
          .where((pair) => pair.$1 == taskId && pair.$2.farmId == farmId)
          .map((pair) => pair.$2)
          .toList();
}
