import 'package:flutter/material.dart';
import '../models/task_model.dart';

class TaskRestoreResult {
  final int restoredCount;
  final int clearedEmployeeLinks;
  final int clearedMachineLinks;
  final int clearedFieldLinks;

  const TaskRestoreResult({
    this.restoredCount = 0,
    this.clearedEmployeeLinks = 0,
    this.clearedMachineLinks = 0,
    this.clearedFieldLinks = 0,
  });

  int get clearedLinkCount =>
      clearedEmployeeLinks + clearedMachineLinks + clearedFieldLinks;
}

class TaskProvider extends ChangeNotifier {
  List<TaskModel> _tasks = [];

  List<TaskModel> get tasks => _tasks;

  TaskProvider() {
    _addSampleData();
  }

  void _addSampleData() {
    final now = DateTime.now();

    _tasks = [
      TaskModel(
        id: 'T001',
        title: 'Thu hoạch cà phê',
        description: 'Thu hoạch toàn bộ lô cà phê A1. Cần 5 nhân công.',
        priority: TaskPriority.HIGH,
        status: TaskStatus.IN_PROGRESS,
        dueDate: DateTime(now.year, now.month, now.day + 3),
        assignedTo: 'NV001',
        assignedToName: 'Nguyễn Văn An',
        fieldId: 'LO0001',
        fieldName: 'Lô cà phê A1',
        tags: ['thu hoạch', 'cà phê'],
        createdAt: now,
      ),
      TaskModel(
        id: 'T002',
        title: 'Bảo trì máy cày',
        description: 'Kiểm tra và bảo trì định kỳ máy cày Yanmar',
        priority: TaskPriority.MEDIUM,
        status: TaskStatus.PENDING,
        dueDate: DateTime(now.year, now.month, now.day + 5),
        assignedTo: 'NV005',
        assignedToName: 'Hoàng Văn Em',
        machineId: 'M001',
        machineName: 'Máy cày Yanmar',
        tags: ['bảo trì', 'máy cày'],
        createdAt: now,
      ),
      TaskModel(
        id: 'T003',
        title: 'Bón phân cho tiêu',
        description: 'Bón phân lót cho lô tiêu B2',
        priority: TaskPriority.HIGH,
        status: TaskStatus.PENDING,
        dueDate: DateTime(now.year, now.month, now.day + 2),
        assignedTo: 'NV002',
        assignedToName: 'Trần Thị Bình',
        fieldId: 'LO0002',
        fieldName: 'Lô tiêu B2',
        tags: ['bón phân', 'tiêu'],
        createdAt: now,
      ),
      TaskModel(
        id: 'T004',
        title: 'Lập báo cáo tài chính',
        description: 'Tổng hợp báo cáo tài chính tháng này',
        priority: TaskPriority.MEDIUM,
        status: TaskStatus.COMPLETED,
        dueDate: DateTime(now.year, now.month, now.day - 2),
        assignedTo: 'NV004',
        assignedToName: 'Phạm Thị Dung',
        completedDate: DateTime(now.year, now.month, now.day - 1),
        tags: ['báo cáo', 'tài chính'],
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      TaskModel(
        id: 'T005',
        title: 'Mua phân bón',
        description: 'Nhập thêm phân Kali và phân Đạm cho kho',
        priority: TaskPriority.LOW,
        status: TaskStatus.DELAYED,
        dueDate: DateTime(now.year, now.month, now.day - 1),
        assignedTo: 'NV003',
        assignedToName: 'Lê Văn Cường',
        tags: ['mua hàng', 'vật tư'],
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ];
  }

  TaskRestoreResult restoreFromCloud({
    required List<TaskModel> tasks,
    required Map<String, String> employeeNamesById,
    required Map<String, String> machineNamesById,
    required Map<String, String> fieldNamesById,
  }) {
    if (tasks.isEmpty) return const TaskRestoreResult();

    final deduplicated = <String, TaskModel>{};
    for (final task in tasks) {
      final id = task.id.trim();
      final title = task.title.trim();
      if (id.isEmpty || title.isEmpty) continue;
      deduplicated[id] = TaskModel(
        id: id,
        title: title,
        description: task.description,
        priority: task.priority,
        status: task.status,
        dueDate: task.dueDate,
        completedDate: task.completedDate,
        assignedTo: task.assignedTo,
        assignedToName: task.assignedToName,
        fieldId: task.fieldId,
        fieldName: task.fieldName,
        machineId: task.machineId,
        machineName: task.machineName,
        tags: task.tags == null
            ? null
            : List<String>.unmodifiable(task.tags!),
        createdAt: task.createdAt,
        updatedAt: task.updatedAt,
      );
    }
    if (deduplicated.isEmpty) return const TaskRestoreResult();

    var clearedEmployeeLinks = 0;
    var clearedMachineLinks = 0;
    var clearedFieldLinks = 0;
    final restored = <TaskModel>[];

    for (final task in deduplicated.values) {
      final employeeId = _cleanTaskLinkId(task.assignedTo);
      final employeeName =
          employeeId == null ? null : employeeNamesById[employeeId];
      if (employeeId != null && employeeName == null) {
        clearedEmployeeLinks++;
      }

      final machineId = _cleanTaskLinkId(task.machineId);
      final machineName =
          machineId == null ? null : machineNamesById[machineId];
      if (machineId != null && machineName == null) {
        clearedMachineLinks++;
      }

      final fieldId = _cleanTaskLinkId(task.fieldId);
      final fieldName = fieldId == null ? null : fieldNamesById[fieldId];
      if (fieldId != null && fieldName == null) {
        clearedFieldLinks++;
      }

      restored.add(
        TaskModel(
          id: task.id,
          title: task.title,
          description: task.description,
          priority: task.priority,
          status: task.status,
          dueDate: task.dueDate,
          completedDate: task.completedDate,
          assignedTo: employeeName == null ? null : employeeId,
          assignedToName: employeeName,
          fieldId: fieldName == null ? null : fieldId,
          fieldName: fieldName,
          machineId: machineName == null ? null : machineId,
          machineName: machineName,
          tags: task.tags,
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
        ),
      );
    }

    restored.sort((a, b) {
      final byDate = a.dueDate.compareTo(b.dueDate);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    _tasks = restored;
    notifyListeners();

    return TaskRestoreResult(
      restoredCount: restored.length,
      clearedEmployeeLinks: clearedEmployeeLinks,
      clearedMachineLinks: clearedMachineLinks,
      clearedFieldLinks: clearedFieldLinks,
    );
  }

  // Thêm công việc mới
  void addTask(TaskModel task) {
    _tasks.add(task);
    notifyListeners();
  }

  // Cập nhật công việc
  void updateTask(TaskModel updatedTask) {
    final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      notifyListeners();
    }
  }

  // Xóa công việc
  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  // Cập nhật trạng thái
  void updateTaskStatus(String id, TaskStatus newStatus) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final task = _tasks[index];
      final completedDate = newStatus == TaskStatus.COMPLETED
          ? DateTime.now()
          : null;
      _tasks[index] = task.copyWith(
        status: newStatus,
        completedDate: completedDate,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  // Lấy công việc theo trạng thái
  List<TaskModel> getTasksByStatus(TaskStatus status) {
    return _tasks.where((t) => t.status == status).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Lấy công việc theo độ ưu tiên
  List<TaskModel> getTasksByPriority(TaskPriority priority) {
    return _tasks.where((t) => t.priority == priority).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Lấy công việc theo người được giao
  List<TaskModel> getTasksByAssignee(String employeeId) {
    return _tasks.where((t) => t.assignedTo == employeeId).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Lấy công việc theo lô đất
  List<TaskModel> getTasksByField(String fieldId) {
    return _tasks.where((t) => t.fieldId == fieldId).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Lấy công việc theo máy móc
  List<TaskModel> getTasksByMachine(String machineId) {
    return _tasks.where((t) => t.machineId == machineId).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Lấy công việc theo ngày
  List<TaskModel> getTasksByDate(DateTime date) {
    return _tasks
        .where(
          (t) =>
              t.dueDate.year == date.year &&
              t.dueDate.month == date.month &&
              t.dueDate.day == date.day,
        )
        .toList();
  }

  // Lấy công việc trong tuần
  List<TaskModel> getTasksInWeek(DateTime date) {
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return _tasks
        .where(
          (t) =>
              t.dueDate.isAfter(startOfWeek) &&
              t.dueDate.isBefore(endOfWeek.add(const Duration(days: 1))),
        )
        .toList();
  }

  // Lấy công việc đang quá hạn
  List<TaskModel> getOverdueTasks() {
    final now = DateTime.now();
    return _tasks
        .where(
          (t) => t.dueDate.isBefore(now) && t.status != TaskStatus.COMPLETED,
        )
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Thống kê số lượng công việc theo trạng thái
  Map<TaskStatus, int> getTaskStatistics() {
    final result = <TaskStatus, int>{};
    for (var status in TaskStatus.values) {
      result[status] = _tasks.where((t) => t.status == status).length;
    }
    return result;
  }
}

String? _cleanTaskLinkId(String? value) {
  final id = value?.trim();
  return id == null || id.isEmpty ? null : id;
}
