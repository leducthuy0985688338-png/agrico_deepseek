import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/live_authorization.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/machines/application/machine_service.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';

AuthorizationSubject user({
  String id = 'a',
  String member = 'm',
  String farm = 'f',
  bool active = true,
  Set<String>? permissions,
  Set<DataScope> scopes = const {DataScope.allFarm},
  DateTime? expiry,
  Map<String, Set<DataScope>> overrides = const {},
}) => AuthorizationSubject(
  userId: id,
  membershipId: member,
  farmId: farm,
  active: active,
  permissionCodes: permissions ?? PermissionCodes.values,
  dataScopes: scopes,
  permissionScopes: overrides,
  validUntil: expiry ?? DateTime.now().add(const Duration(hours: 1)),
);

class People implements PersonnelRepository {
  final result = Completer<List<EmployeeCard>>();
  bool? sensitive;
  @override
  Future<List<EmployeeCard>> employees(
    String farmId, {
    required bool sensitive,
  }) {
    this.sensitive = sensitive;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Machines implements MachineRepository {
  final result = Completer<List<MachineRecord<MachineRun>>>();
  bool? money;
  @override
  Future<List<MachineRecord<MachineRun>>> runs(
    String farm, {
    bool money = true,
  }) {
    this.money = money;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Stock implements InventoryRepository {
  final result = Completer<List<InventoryItem>>();
  int writes = 0;
  @override
  Future<List<InventoryItem>> listByFarm(String farmId) => result.future;
  @override
  Future<void> register(InventoryItem item) async {
    writes++;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'null session, changed user membership farm, inactive and expired identities deny reads before loading',
    () {
      final opened = user();
      AuthorizationSubject? live = opened;
      final guard = LiveAuthorization(() => live);
      int loads = 0;
      for (final denied in [
        null,
        user(id: 'other'),
        user(member: 'other'),
        user(farm: 'other'),
        user(active: false),
        user(expiry: DateTime.utc(2000)),
      ]) {
        live = denied;
        expect(
          () => guard.read(opened, [PermissionCodes.inventoryView], () async {
            loads++;
            return 1;
          }),
          throwsStateError,
        );
      }
      expect(loads, 0);
    },
  );
  test(
    'current scoped deny is respected even if the opened subject had all farm grants',
    () {
      final opened = user();
      var live = user(scopes: const {DataScope.assignedMachines});
      final guard = LiveAuthorization(() => live);
      expect(guard.can(opened, PermissionCodes.machineView), isFalse);
      live = user(
        overrides: const {
          PermissionCodes.machineView: {DataScope.assignedMachines},
        },
      );
      expect(guard.can(opened, PermissionCodes.machineView), isFalse);
      live = user(permissions: const {PermissionCodes.machineView});
      expect(guard.can(opened, PermissionCodes.machineLog), isFalse);
    },
  );
  test(
    'a completed protected read is discarded if its session changes during I/O',
    () async {
      final opened = user();
      AuthorizationSubject? live = opened;
      final pending = Completer<int>();
      final guard = LiveAuthorization(() => live);
      final result = guard.read(opened, [
        PermissionCodes.inventoryView,
      ], () => pending.future);
      final rejected = expectLater(result, throwsStateError);
      live = user(member: 'new-login');
      pending.complete(1);
      await rejected;
    },
  );
  test(
    'personnel read discards private fields when employee edit is revoked during I/O',
    () async {
      final opened = user();
      var live = opened;
      final repo = People();
      final service = PersonnelService(repo, currentSubject: () => live);
      final result = service.employees(opened);
      expect(repo.sensitive, isTrue);
      final rejected = expectLater(result, throwsStateError);
      live = user(permissions: const {PermissionCodes.employeeView});
      repo.result.complete([]);
      await rejected;
    },
  );
  test('basic personnel read does not request private fields', () async {
    final opened = user(permissions: const {PermissionCodes.employeeView});
    final repo = People();
    final service = PersonnelService(repo, currentSubject: () => opened);
    final result = service.employees(opened);
    expect(repo.sensitive, isFalse);
    repo.result.complete([]);
    expect(await result, isEmpty);
  });
  test(
    'machine read discards prices if finance view is revoked during I/O',
    () async {
      final opened = user();
      var live = opened;
      final repo = Machines();
      final service = MachineService(repo, currentSubject: () => live);
      final result = service.runs(opened);
      expect(repo.money, isTrue);
      final rejected = expectLater(result, throwsStateError);
      live = user(permissions: const {PermissionCodes.machineView});
      repo.result.complete([]);
      await rejected;
      expect(() => service.exportPermission(opened), throwsStateError);
    },
  );
  test(
    'inventory read is discarded after logout and stale write never reaches repository',
    () async {
      final opened = user();
      AuthorizationSubject? live = opened;
      final repo = Stock();
      final service = InventoryService(repo, currentSubject: () => live);
      final result = service.list(opened);
      final rejected = expectLater(result, throwsStateError);
      live = null;
      repo.result.complete([]);
      await rejected;
      expect(
        () => service.register(
          opened,
          const InventoryItem(
            id: 'i',
            farmId: 'f',
            code: 'VT001',
            name: 'Item',
            unit: 'kg',
            unitPrice: 0,
            supplier: '',
          ),
        ),
        throwsStateError,
      );
      expect(repo.writes, 0);
      expect(() => service.exportPermission(opened), throwsStateError);
    },
  );
  test(
    'inventory export requires both report and export grants in the active session',
    () {
      final opened = user();
      var live = user(permissions: const {PermissionCodes.inventoryView});
      final service = InventoryService(Stock(), currentSubject: () => live);
      expect(() => service.exportPermission(opened), throwsStateError);
      live = user(
        permissions: const {
          PermissionCodes.inventoryView,
          PermissionCodes.reportOperations,
        },
      );
      expect(() => service.exportPermission(opened), throwsStateError);
      live = opened;
      service.exportPermission(opened);
    },
  );
}
