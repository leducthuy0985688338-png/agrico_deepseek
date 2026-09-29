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
        PermissionCodes.taskComplete,
        PermissionCodes.fieldView,
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
        localizationsDelegates: const [AppLocalizations.delegate],
        home: FarmTaskScreen(
          controller: controller,
          resources: ParcelWorkService(resources),
          parcels: [parcel],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.items, isEmpty);

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
    final completeKey = Key('farm-task-complete-${tasks.saved.single.id}');
    await tester.tap(find.byKey(completeKey));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.status, FarmTaskStatus.pending);
    await tester.tap(find.byKey(const Key('farm-task-confirm-complete')));
    await tester.pumpAndSettle();
    expect(tasks.saved.single.status, FarmTaskStatus.completed);
    expect(find.byKey(completeKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

class _Tasks implements FarmTaskRepository {
  final saved = <FarmTask>[];

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
