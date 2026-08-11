import 'package:agrico_deepseek/models/task_model.dart';
import 'package:agrico_deepseek/providers/task_provider.dart';
import 'package:flutter_test/flutter_test.dart';

TaskModel _task({
  required String id,
  required String title,
  String? assignedTo,
  String? assignedToName,
  String? fieldId,
  String? fieldName,
  String? machineId,
  String? machineName,
  TaskPriority priority = TaskPriority.MEDIUM,
  TaskStatus status = TaskStatus.PENDING,
  DateTime? dueDate,
}) {
  final date = dueDate ?? DateTime.utc(2026, 8, 20);
  return TaskModel(
    id: id,
    title: title,
    description: 'Công việc thử nghiệm',
    priority: priority,
    status: status,
    dueDate: date,
    completedDate:
        status == TaskStatus.COMPLETED ? date.add(const Duration(hours: 2)) : null,
    assignedTo: assignedTo,
    assignedToName: assignedToName,
    fieldId: fieldId,
    fieldName: fieldName,
    machineId: machineId,
    machineName: machineName,
    tags: const ['sản xuất', 'ưu tiên'],
    createdAt: date.subtract(const Duration(days: 1)),
    updatedAt: date,
  );
}

void main() {
  test('task cloud round trip keeps schedule and assignment fields', () {
    final source = _task(
      id: 'CV-CLOUD',
      title: 'Bón phân lô A1',
      assignedTo: 'NV001',
      assignedToName: 'Nguyễn Văn An',
      fieldId: 'LO0001',
      fieldName: 'Lô cà phê A1',
      machineId: 'M001',
      machineName: 'Máy cày Yanmar',
      priority: TaskPriority.HIGH,
      status: TaskStatus.COMPLETED,
    );

    final restored = TaskModel.fromMap(source.toMap());

    expect(restored.id, source.id);
    expect(restored.title, source.title);
    expect(restored.description, source.description);
    expect(restored.priority, source.priority);
    expect(restored.status, source.status);
    expect(restored.dueDate, source.dueDate);
    expect(restored.completedDate, source.completedDate);
    expect(restored.assignedTo, source.assignedTo);
    expect(restored.assignedToName, source.assignedToName);
    expect(restored.fieldId, source.fieldId);
    expect(restored.fieldName, source.fieldName);
    expect(restored.machineId, source.machineId);
    expect(restored.machineName, source.machineName);
    expect(restored.tags, source.tags);
    expect(restored.createdAt, source.createdAt);
    expect(restored.updatedAt, source.updatedAt);
  });

  test('task map accepts legacy enum names and DateTime values', () {
    final restored = TaskModel.fromMap({
      'id': 'CV-LEGACY',
      'title': 'Kiểm tra đồng ruộng',
      'description': '',
      'priority': 'HIGH',
      'status': 'IN_PROGRESS',
      'dueDate': DateTime.utc(2026, 8, 21),
      'createdAt': '2026-08-19T00:00:00.000Z',
      'tags': ['kiểm tra', 'kiểm tra', '  đồng ruộng  '],
    });

    expect(restored.priority, TaskPriority.HIGH);
    expect(restored.status, TaskStatus.IN_PROGRESS);
    expect(restored.dueDate, DateTime.utc(2026, 8, 21));
    expect(restored.tags, ['kiểm tra', 'đồng ruộng']);
  });

  test('task restore deduplicates and validates all linked catalogues', () {
    final provider = TaskProvider();
    final older = _task(
      id: 'CV-01',
      title: 'Bản cũ',
      assignedTo: 'NV001',
      fieldId: 'LO0001',
      machineId: 'M001',
    );
    final newer = _task(
      id: 'CV-01',
      title: 'Bản mới',
      assignedTo: 'NV001',
      assignedToName: 'Tên Cloud đã cũ',
      fieldId: 'LO0001',
      fieldName: 'Tên lô Cloud đã cũ',
      machineId: 'M001',
      machineName: 'Tên máy Cloud đã cũ',
    );
    final brokenLinks = _task(
      id: 'CV-02',
      title: 'Liên kết không tồn tại',
      assignedTo: 'NV999',
      fieldId: 'LO9999',
      machineId: 'M999',
      dueDate: DateTime.utc(2026, 8, 22),
    );

    final result = provider.restoreFromCloud(
      tasks: [older, newer, brokenLinks],
      employeeNamesById: const {'NV001': 'Nguyễn Văn An'},
      machineNamesById: const {'M001': 'Máy cày Yanmar'},
      fieldNamesById: const {'LO0001': 'Lô cà phê A1'},
    );

    expect(result.restoredCount, 2);
    expect(result.clearedEmployeeLinks, 1);
    expect(result.clearedMachineLinks, 1);
    expect(result.clearedFieldLinks, 1);
    expect(result.clearedLinkCount, 3);

    final linked = provider.tasks.firstWhere((task) => task.id == 'CV-01');
    expect(linked.title, 'Bản mới');
    expect(linked.assignedToName, 'Nguyễn Văn An');
    expect(linked.fieldName, 'Lô cà phê A1');
    expect(linked.machineName, 'Máy cày Yanmar');

    final broken = provider.tasks.firstWhere((task) => task.id == 'CV-02');
    expect(broken.assignedTo, isNull);
    expect(broken.assignedToName, isNull);
    expect(broken.fieldId, isNull);
    expect(broken.fieldName, isNull);
    expect(broken.machineId, isNull);
    expect(broken.machineName, isNull);
  });

  test('empty or invalid task cloud payload keeps local tasks', () {
    final provider = TaskProvider();
    final originalIds = provider.tasks.map((task) => task.id).toList();

    final emptyResult = provider.restoreFromCloud(
      tasks: const [],
      employeeNamesById: const {},
      machineNamesById: const {},
      fieldNamesById: const {},
    );
    expect(emptyResult.restoredCount, 0);
    expect(provider.tasks.map((task) => task.id), originalIds);

    final invalidResult = provider.restoreFromCloud(
      tasks: [
        _task(id: '   ', title: 'Không hợp lệ'),
        _task(id: 'CV-INVALID', title: '   '),
      ],
      employeeNamesById: const {},
      machineNamesById: const {},
      fieldNamesById: const {},
    );
    expect(invalidResult.restoredCount, 0);
    expect(provider.tasks.map((task) => task.id), originalIds);
  });
}
