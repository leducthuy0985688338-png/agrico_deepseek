import 'package:agrico_deepseek/models/employee_model.dart';
import 'package:agrico_deepseek/models/machine_model.dart';
import 'package:agrico_deepseek/providers/employee_provider.dart';
import 'package:agrico_deepseek/providers/machine_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee cloud round trip keeps catalogue fields', () {
    final source = EmployeeModel(
      id: 'NV-CLOUD',
      name: 'Nguyễn Văn An',
      position: 'Lái máy',
      department: 'Sản xuất',
      dailyRate: 350000,
      phone: '020-555-0101',
      address: 'Savannakhet',
      isActive: false,
    );

    final restored = EmployeeModel.fromMap(source.toMap());

    expect(restored.id, source.id);
    expect(restored.name, source.name);
    expect(restored.position, source.position);
    expect(restored.department, source.department);
    expect(restored.dailyRate, source.dailyRate);
    expect(restored.phone, source.phone);
    expect(restored.address, source.address);
    expect(restored.isActive, source.isActive);
  });

  test('machine cloud round trip keeps costing and assignment fields', () {
    final source = MachineModel(
      id: 'MAY-CLOUD',
      name: 'Máy kéo Cloud',
      type: 'Máy kéo',
      manufacturer: 'Yanmar',
      year: 2026,
      status: 'Tốt',
      totalHours: 418,
      fuelConsumption: 8.75,
      costPerHour: 185000,
      currentFieldId: 'LO-CLOUD',
    );

    final restored = MachineModel.fromMap(source.toMap());

    expect(restored.id, source.id);
    expect(restored.name, source.name);
    expect(restored.type, source.type);
    expect(restored.manufacturer, source.manufacturer);
    expect(restored.year, source.year);
    expect(restored.status, source.status);
    expect(restored.totalHours, source.totalHours);
    expect(restored.fuelConsumption, source.fuelConsumption);
    expect(restored.costPerHour, source.costPerHour);
    expect(restored.currentFieldId, source.currentFieldId);
  });

  test('employee restore deduplicates and ignores empty cloud', () {
    final provider = EmployeeProvider();
    final attendanceCount = provider.attendanceLogs.length;
    final older = EmployeeModel(
      id: 'NV-01',
      name: 'Tên cũ',
      position: 'Công nhân',
      department: 'Sản xuất',
      dailyRate: 200000,
      phone: '',
    );
    final newer = EmployeeModel(
      id: 'NV-01',
      name: 'Tên mới',
      position: 'Tổ trưởng',
      department: 'Sản xuất',
      dailyRate: 300000,
      phone: '020-555-0102',
    );
    final second = EmployeeModel(
      id: 'NV-02',
      name: 'Bình',
      position: 'Kế toán',
      department: 'Văn phòng',
      dailyRate: 400000,
      phone: '020-555-0103',
    );

    provider.restoreFromCloud(employees: [older, second, newer]);

    expect(provider.employees, hasLength(2));
    expect(provider.getEmployeeById('NV-01')?.name, 'Tên mới');
    expect(provider.attendanceLogs, hasLength(attendanceCount));

    final restoredIds =
        provider.employees.map((employee) => employee.id).toList();
    provider.restoreFromCloud(employees: const []);

    expect(provider.employees.map((employee) => employee.id), restoredIds);
  });

  test('machine restore deduplicates and clears missing field links', () {
    final provider = MachineProvider();
    final localMaintenance = MaintenanceRecord(
      date: DateTime.utc(2026, 8, 1),
      content: 'Thay dầu',
      cost: 450000,
    );
    provider.addMachine(
      MachineModel(
        id: 'MAY-01',
        name: 'Bản cục bộ',
        type: 'Máy kéo',
        manufacturer: 'Kubota',
        year: 2025,
        status: 'Tốt',
        maintenanceHistory: [localMaintenance],
      ),
    );
    final valid = MachineModel(
      id: 'MAY-01',
      name: 'Máy hợp lệ',
      type: 'Máy kéo',
      manufacturer: 'Kubota',
      year: 2025,
      status: 'Tốt',
      totalHours: 120,
      fuelConsumption: 9,
      costPerHour: 150000,
      currentFieldId: 'LO-OK',
    );
    final stale = MachineModel(
      id: 'MAY-02',
      name: 'Máy mất liên kết',
      type: 'Máy cày',
      manufacturer: 'Yanmar',
      year: 2024,
      status: 'Bảo trì',
      totalHours: 300,
      fuelConsumption: 11,
      costPerHour: 170000,
      currentFieldId: 'LO-MISSING',
    );
    final duplicate = MachineModel(
      id: 'MAY-02',
      name: 'Máy mất liên kết mới',
      type: 'Máy cày',
      manufacturer: 'Yanmar',
      year: 2024,
      status: 'Tốt',
      totalHours: 305,
      fuelConsumption: 11,
      costPerHour: 175000,
      currentFieldId: 'LO-MISSING',
    );

    final cleared = provider.restoreFromCloud(
      machines: [valid, stale, duplicate],
      validFieldIds: {'LO-OK'},
    );

    expect(provider.machines, hasLength(2));
    expect(provider.getMachineById('MAY-01')?.currentFieldId, 'LO-OK');
    expect(provider.getMachineById('MAY-02')?.currentFieldId, isNull);
    expect(provider.getMachineById('MAY-02')?.name, 'Máy mất liên kết mới');
    expect(provider.getMachineById('MAY-02')?.costPerHour, 175000);
    expect(
      provider.getMachineById('MAY-01')?.maintenanceHistory,
      [localMaintenance],
    );
    expect(cleared, 1);

    final restoredIds =
        provider.machines.map((machine) => machine.id).toList();
    final emptyCleared = provider.restoreFromCloud(
      machines: const [],
      validFieldIds: {'LO-OK'},
    );

    expect(emptyCleared, 0);
    expect(provider.machines.map((machine) => machine.id), restoredIds);
  });
}
