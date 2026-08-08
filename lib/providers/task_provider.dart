import 'package:flutter/material.dart';
import '../models/task_model.dart';

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
