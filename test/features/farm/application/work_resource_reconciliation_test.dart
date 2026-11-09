import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/application/work_resource_reconciliation.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/models/employee_model.dart';
import 'package:agrico_deepseek/models/machine_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const subject = AuthorizationSubject(
    userId: 'user',
    membershipId: 'actor',
    farmId: 'farm-1',
    permissionCodes: {PermissionCodes.fieldView, PermissionCodes.catalogView},
    dataScopes: {DataScope.allFarm},
  );
  MachineModel machine(String id, String name) => MachineModel(
    id: id,
    name: name,
    type: 'tractor',
    manufacturer: '',
    year: 2022,
    status: 'Tốt',
  );
  EmployeeModel employee(String id, String name) => EmployeeModel(
    id: id,
    name: name,
    position: '',
    department: '',
    dailyRate: 0,
    phone: '',
  );

  test(
    'compares verified legacy catalog without writing or merging IDs',
    () async {
      final repo = _Repository([
        const WorkResource(
          id: 'legacy-machine:M001',
          farmId: 'farm-1',
          kind: WorkResourceKind.machine,
          code: 'M001',
          name: 'Máy cày',
        ),
        const WorkResource(
          id: 'another-id',
          farmId: 'farm-1',
          kind: WorkResourceKind.worker,
          code: 'NV001',
          name: 'Công nhân',
        ),
      ]);
      final comparison =
          await WorkResourceReconciliation(ParcelWorkService(repo)).compare(
            subject,
            verifiedMachines: [
              machine('M001', 'Máy cày'),
              machine('M002', 'Xe tải'),
            ],
            verifiedEmployees: [employee('NV001', 'Công nhân')],
          );
      expect(comparison.matched.map((r) => r.code), ['M001']);
      expect(comparison.ready.map((r) => r.code), ['M002']);
      expect(comparison.conflicts.map((r) => r.code), ['NV001']);
      expect(repo.registerCalls, 0);
      expect(repo.items, hasLength(2));
    },
  );

  test('name changes and duplicate source codes require review', () async {
    final repo = _Repository([
      const WorkResource(
        id: 'legacy-machine:M001',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M001',
        name: 'Tên cũ',
      ),
    ]);
    final comparison = await WorkResourceReconciliation(ParcelWorkService(repo))
        .compare(
          subject,
          verifiedMachines: [
            machine('M001', 'Tên mới'),
            machine('M002', 'Xe'),
            machine('M002', 'Xe'),
          ],
          verifiedEmployees: [],
        );
    expect(comparison.conflicts.map((r) => r.code), ['M001', 'M002', 'M002']);
    expect(comparison.ready, isEmpty);
  });

  test(
    'imports only selected reviewed resources with catalog management permission',
    () async {
      final repo = _Repository([]);
      final reconciliation = WorkResourceReconciliation(
        ParcelWorkService(repo),
      );
      final comparison = await reconciliation.compare(
        subject,
        verifiedMachines: [
          machine('M001', 'Máy cày'),
          machine('M002', 'Xe tải'),
        ],
        verifiedEmployees: [],
      );
      await expectLater(
        reconciliation.importSelected(subject, comparison, {
          'legacy-machine:M001',
        }),
        throwsStateError,
      );
      expect(repo.items, isEmpty);
      const editor = AuthorizationSubject(
        userId: 'user',
        membershipId: 'actor',
        farmId: 'farm-1',
        permissionCodes: {
          PermissionCodes.fieldView,
          PermissionCodes.fieldEdit,
          PermissionCodes.catalogView,
          PermissionCodes.catalogManage,
        },
        dataScopes: {DataScope.allFarm},
      );
      await expectLater(
        reconciliation.importSelected(editor, comparison, {
          'legacy-machine:M003',
        }),
        throwsStateError,
      );
      await reconciliation.importSelected(editor, comparison, {
        'legacy-machine:M001',
      });
      expect(repo.items.map((r) => r.code), ['M001']);
    },
  );
}

class _Repository implements ParcelWorkRepository {
  _Repository(this.items);
  final List<WorkResource> items;
  int registerCalls = 0;
  @override
  Future<List<WorkResource>> resources(String farmId) async =>
      items.where((r) => r.farmId == farmId).toList();
  @override
  Future<void> register(WorkResource resource) async {
    registerCalls++;
  }

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    registerCalls++;
    items.addAll(resources);
  }

  @override
  Future<void> record(ParcelWorkEvent event) async {}
  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      [];
}
