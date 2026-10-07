import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/farm_task_service.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/farm_task.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/farm_task_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/controllers/farm_task_controller.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/farm_task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates a task using the shared machine catalog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    final tasks = _Tasks();
    final resources = _Resources();
    final parcel = LandParcel.create(
      id: 'parcel-1',
      farmId: 'farm-1',
      parcelCode: 'L001',
      name: 'Lô A',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106),
      ]),
      boundarySource: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: 'member',
      occurredAt: DateTime.utc(2026, 9, 29),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
        PermissionCodes.taskEdit,
        PermissionCodes.taskComplete,
        PermissionCodes.fieldView,
        PermissionCodes.catalogView,
      },
      dataScopes: {DataScope.allFarm},
    );
    final controller = FarmTaskController(
      subject: subject,
      service: FarmTaskService(tasks),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FarmTaskScreen(
          controller: controller,
          resources: ParcelWorkService(resources),
          parcels: [parcel],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.items, isEmpty);
    expect(find.text('Tổng công việc: 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('farm-task-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('farm-task-title')),
      'Khai hoang A',
    );
    await tester.tap(find.byKey(const Key('farm-task-parcel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L001 · Lô A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-machine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M001 · Máy cày').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-save')));
    await tester.pumpAndSettle();

    expect(controller.items, hasLength(1));
    expect(tasks.saved.single.machineResourceId, 'machine-1');
    expect(tasks.saved.single.parcelId, 'parcel-1');
    expect(find.text('Khai hoang A'), findsOneWidget);
    expect(find.text('Tổng công việc: 1'), findsOneWidget);
    expect(find.text('Chờ làm: 1'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('farm-task-details-${tasks.saved.single.id}')),
        matching: find.text('Khai hoang A'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Lô đất: L001 · Lô A'), findsOneWidget);
    expect(find.text('Máy móc: M001 · Máy cày'), findsOneWidget);
    expect(tasks.saved.single.status, FarmTaskStatus.pending);
    await tester.tap(find.byKey(const Key('farm-task-close-details')));
    await tester.pumpAndSettle();
    resources.saved[0] = const WorkResource(
      id: 'machine-1',
      farmId: 'farm-1',
      kind: WorkResourceKind.machine,
      code: 'M001',
      name: 'Máy cày',
      active: false,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('farm-task-details-${tasks.saved.single.id}')),
        matching: find.text('Khai hoang A'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Máy móc: M001 · Máy cày · Ngừng sử dụng'),
      findsOneWidget,
    );
    expect(tasks.saved.single.machineResourceId, 'machine-1');
    await tester.tap(find.byKey(const Key('farm-task-close-details')));
    await tester.pumpAndSettle();
    final beforeEdit = tasks.saved.single;
    await tester.tap(find.text('Khai hoang A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('farm-task-title')))
        .controller!.text, 'Khai hoang A');
    expect(tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('farm-task-machine'))).initialValue, 'machine-1');
    await tester.enterText(find.byKey(const Key('farm-task-title')), 'Hủy sửa');
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.title, 'Khai hoang A');
    await tester.tap(find.text('Khai hoang A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('farm-task-title')), 'Khai hoang A đã sửa');
    await tester.tap(find.byKey(const Key('farm-task-save')));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.title, 'Khai hoang A đã sửa');
    expect(tasks.saved.single.id, beforeEdit.id);
    expect(tasks.saved.single.createdAt, beforeEdit.createdAt);
    expect(tasks.saved.single.machineResourceId, 'machine-1');
    expect(tasks.saved.single.parcelId, 'parcel-1');
    expect(tasks.saved.single.status, FarmTaskStatus.pending);
    await tester.tap(find.text('Khai hoang A đã sửa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-status-inProgress')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.status, FarmTaskStatus.pending);
    for (final status in [FarmTaskStatus.inProgress, FarmTaskStatus.delayed,
        FarmTaskStatus.inProgress]) {
      await tester.tap(find.text('Khai hoang A đã sửa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('farm-task-status-${status.name}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('farm-task-confirm-status')));
      await tester.pumpAndSettle();
      expect(tasks.saved.single.status, status);
      expect(tester.widget<Text>(find.byKey(
        Key('farm-task-count-${status.name}'))).data, endsWith(': 1'));
      expect(tasks.saved.single.machineResourceId, 'machine-1');
      expect(tasks.saved.single.id, beforeEdit.id);
    }
    final completeKey = Key('farm-task-complete-${tasks.saved.single.id}');
    await tester.tap(find.byKey(completeKey));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.status, FarmTaskStatus.inProgress);
    await tester.tap(find.byKey(const Key('farm-task-confirm-complete')));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.status, FarmTaskStatus.completed);
    expect(find.byKey(completeKey), findsNothing);
    await tester.tap(find.text('Khai hoang A đã sửa'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-task-status-inProgress')), findsNothing);
    expect(find.byKey(const Key('farm-task-status-delayed')), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-close-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chờ làm').last);
    await tester.pumpAndSettle();
    expect(find.text('Khai hoang A đã sửa'), findsNothing);
    expect(tasks.saved.single.status, FarmTaskStatus.completed);
    await tester.tap(find.byKey(const Key('farm-task-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn thành').last);
    await tester.pumpAndSettle();
    expect(find.text('Khai hoang A đã sửa'), findsOneWidget);
    tasks.saved.add(FarmTask(
      id: 'unlinked-task', farmId: 'farm-1', title: 'Công việc chung',
      description: '', status: FarmTaskStatus.completed,
      dueAt: DateTime(2026, 10, 7), createdAt: DateTime(2026, 10, 6),
    ));
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.text('Công việc chung'), findsOneWidget);
    await tester.tap(find.byKey(const Key('farm-task-filter-parcel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L001 · Lô A').last);
    await tester.pumpAndSettle();
    expect(find.text('Khai hoang A đã sửa'), findsOneWidget);
    expect(find.text('Công việc chung'), findsNothing);
    expect(tasks.saved, hasLength(2));
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.text('Công việc chung'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-filter-parcel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tất cả').last);
    await tester.pumpAndSettle();
    expect(find.text('Công việc chung'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FarmTaskScreen(
        key: const Key('parcel-task-route'),
        controller: controller,
        resources: ParcelWorkService(resources),
        parcels: [parcel],
        initialParcelId: 'parcel-1',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Khai hoang A đã sửa'), findsOneWidget);
    expect(find.text('Công việc chung'), findsNothing);
    expect(find.text('L001 · Lô A'), findsOneWidget);
    expect(tasks.saved, hasLength(2));
    await tester.tap(find.byKey(const Key('farm-task-add')));
    await tester.pumpAndSettle();
    final parcelField = find.byKey(const Key('farm-task-parcel'));
    expect(tester.widget<DropdownButtonFormField<String>>(parcelField).initialValue,
        'parcel-1');
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(tasks.saved, hasLength(2));
    await tester.tap(find.byKey(const Key('farm-task-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('farm-task-title')),
        'Tác vụ từ thửa đất');
    await tester.enterText(find.byType(TextField).last, 'Chuẩn bị máy');
    await tester.tap(find.byKey(const Key('farm-task-save')));
    await tester.pumpAndSettle();
    expect(tasks.saved, hasLength(3));
    expect(tasks.saved.last.parcelId, 'parcel-1');
    final searchField = find.byKey(const Key('farm-task-search'));
    await tester.enterText(searchField, '  TÁC VỤ  ');
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    expect(find.text('Khai hoang A đã sửa'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn thành').last);
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tất cả').last);
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    await controller.load();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).controller!.text, '  TÁC VỤ  ');
    await tester.enterText(searchField, 'không có kết quả');
    await tester.pumpAndSettle();
    expect(find.text('Không có tác vụ phù hợp bộ lọc.'), findsOneWidget);
    expect(find.text('Tổng công việc: 0'), findsOneWidget);
    expect(tasks.saved, hasLength(3));
    await tester.tap(find.byKey(const Key('farm-task-clear-search')));
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    expect(find.text('Khai hoang A đã sửa'), findsOneWidget);
    expect(find.text('Công việc chung'), findsNothing);
    await tester.enterText(searchField, 'chuẩn bị');
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    expect(find.text('Khai hoang A đã sửa'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-clear-search')));
    await tester.pumpAndSettle();
    final dueTask = tasks.saved.last;
    tasks.saved[tasks.saved.length - 1] = FarmTask(
      id: dueTask.id, farmId: dueTask.farmId, title: dueTask.title,
      description: dueTask.description, status: dueTask.status,
      dueAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: dueTask.createdAt, parcelId: dueTask.parcelId,
      workerResourceId: dueTask.workerResourceId,
      machineResourceId: dueTask.machineResourceId);
    await controller.load();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-filter-overdue')));
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    expect(find.text('Khai hoang A đã sửa'), findsNothing);
    await tester.enterText(searchField, 'không khớp');
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-clear-search')));
    await tester.pumpAndSettle();
    await controller.load();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(
      const Key('farm-task-filter-overdue'))).value, isTrue);
    expect(find.text('Tổng công việc: 1'), findsOneWidget);
    expect(find.text('Quá hạn: 1'), findsOneWidget);
    expect(find.text('Hoàn thành: 0'), findsOneWidget);
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    await controller.complete(dueTask.id);
    await tester.pumpAndSettle();
    expect(find.text('Tổng công việc: 0'), findsOneWidget);
    expect(find.text('Quá hạn: 0'), findsOneWidget);
    expect(find.text('Tác vụ từ thửa đất'), findsNothing);
    await tester.tap(find.byKey(const Key('farm-task-filter-overdue')));
    await tester.pumpAndSettle();
    expect(find.text('Tác vụ từ thửa đất'), findsOneWidget);
    expect(tasks.saved, hasLength(3));
    final viewer = FarmTaskController(
      subject: const AuthorizationSubject(userId: 'viewer', membershipId: 'viewer',
        farmId: 'farm-1', permissionCodes: {PermissionCodes.taskView, PermissionCodes.catalogView},
        dataScopes: {DataScope.allFarm}), service: FarmTaskService(tasks));
    await viewer.load();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FarmTaskScreen(
      key: const Key('viewer-tasks'), controller: viewer,
      resources: ParcelWorkService(resources), parcels: [parcel])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tác vụ từ thửa đất'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-task-edit')), findsNothing);
    expect(find.byKey(const Key('farm-task-status-inProgress')), findsNothing);
    expect(find.byKey(const Key('farm-task-status-delayed')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    viewer.dispose();
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

class _Tasks implements FarmTaskRepository {
  final saved = <FarmTask>[];

  @override
  Future<void> changeStatus({required String farmId, required String id,
      required FarmTaskStatus status}) async {
    final index = saved.indexWhere((t) => t.id == id && t.farmId == farmId);
    if (index < 0 || saved[index].status == FarmTaskStatus.completed) {
      throw StateError('Task unavailable');
    }
    final task = saved[index];
    saved[index] = FarmTask(id: task.id, farmId: task.farmId, title: task.title,
      description: task.description, status: status, dueAt: task.dueAt,
      createdAt: task.createdAt, parcelId: task.parcelId,
      workerResourceId: task.workerResourceId, machineResourceId: task.machineResourceId);
  }

  @override
  Future<void> complete({required String farmId, required String id}) async {
    final index = saved.indexWhere(
      (task) => task.farmId == farmId && task.id == id,
    );
    if (index == -1) {
      throw StateError('Missing task');
    }
    final task = saved[index];
    saved[index] = FarmTask(
      id: task.id,
      farmId: task.farmId,
      title: task.title,
      description: task.description,
      status: FarmTaskStatus.completed,
      dueAt: task.dueAt,
      createdAt: task.createdAt,
      parcelId: task.parcelId,
      workerResourceId: task.workerResourceId,
      machineResourceId: task.machineResourceId,
    );
  }

  @override
  Future<void> update(FarmTask task) async {
    final index = saved.indexWhere((t) => t.id == task.id && t.farmId == task.farmId);
    if (index < 0) throw StateError('Missing task');
    saved[index] = task;
  }

  @override
  Future<void> create(FarmTask task) async {
    saved.add(task);
  }

  @override
  Future<List<FarmTask>> listByFarm(String farmId) async =>
      saved.where((task) => task.farmId == farmId).toList();
}

class _Resources implements ParcelWorkRepository {
  final saved = <WorkResource>[
    const WorkResource(
      id: 'machine-1',
      farmId: 'farm-1',
      kind: WorkResourceKind.machine,
      code: 'M001',
      name: 'Máy cày',
    ),
  ];

  @override
  Future<void> register(WorkResource resource) async {
    saved.add(resource);
  }

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    saved.addAll(resources);
  }

  @override
  Future<List<WorkResource>> resources(String farmId) async =>
      saved.where((resource) => resource.farmId == farmId).toList();

  @override
  Future<void> record(ParcelWorkEvent event) async {}

  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      [];
}
