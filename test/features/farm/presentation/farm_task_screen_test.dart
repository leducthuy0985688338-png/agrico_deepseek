import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/farm_task_service.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/farm_task.dart';
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
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {
        PermissionCodes.taskView,
        PermissionCodes.taskCreate,
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
    await tester.tap(find.byKey(const Key('farm-task-machine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M001 · Máy cày').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-task-save')));
    await tester.pumpAndSettle();

    expect(controller.items, hasLength(1));
    expect(tasks.saved.single.machineResourceId, 'machine-1');
    expect(find.text('Khai hoang A'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

class _Tasks implements FarmTaskRepository {
  final saved = <FarmTask>[];

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
