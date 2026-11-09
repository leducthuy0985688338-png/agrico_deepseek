import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/work_resource_catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'land editing alone cannot create or import machine catalog entries',
    () {
      final repo = _ResourceRepository();
      final service = ParcelWorkService(repo);
      const editor = AuthorizationSubject(
        userId: 'editor',
        membershipId: 'editor',
        farmId: 'farm-1',
        permissionCodes: {PermissionCodes.fieldView, PermissionCodes.fieldEdit},
        dataScopes: {DataScope.allFarm},
      );
      const resource = WorkResource(
        id: 'm',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M01',
        name: 'Machine',
      );
      expect(() => service.register(editor, resource), throwsStateError);
      expect(() => service.registerBatch(editor, [resource]), throwsStateError);
      expect(repo.saved, isEmpty);
    },
  );

  testWidgets('machine catalog saves to the shared work resource repository', (
    tester,
  ) async {
    final repository = _ResourceRepository();
    repository.saved.add(
      const WorkResource(
        id: 'worker-1',
        farmId: 'farm-1',
        kind: WorkResourceKind.worker,
        code: 'W001',
        name: 'Worker fixture',
      ),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm-1',
      permissionCodes: {
        PermissionCodes.fieldView,
        PermissionCodes.fieldEdit,
        PermissionCodes.catalogView,
        PermissionCodes.catalogManage,
      },
      dataScopes: {DataScope.allFarm},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: WorkResourceCatalogScreen(
          kind: WorkResourceKind.machine,
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Worker fixture'), findsNothing);

    await tester.tap(find.byKey(const Key('catalog-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-code')), 'M001');
    await tester.enterText(find.byKey(const Key('catalog-name')), 'Máy cày');
    await tester.tap(find.byKey(const Key('catalog-save')));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(2));
    expect(repository.saved.last.kind, WorkResourceKind.machine);
    expect(repository.saved.last.farmId, 'farm-1');
    expect(repository.saved.last.code, 'M001');
    expect(find.text('Máy cày'), findsOneWidget);
    expect(find.text('Worker fixture'), findsNothing);
  });
}

class _ResourceRepository implements ParcelWorkRepository {
  final saved = <WorkResource>[];

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    saved.addAll(resources);
  }

  @override
  Future<void> register(WorkResource resource) async {
    saved.add(resource);
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
