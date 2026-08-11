import 'package:flutter/material.dart';

class TaskModel {
  final String id;
  final String title;
  final String description;
  final TaskPriority priority; // Cao, Trung bình, Thấp
  final TaskStatus status; // Chưa làm, Đang làm, Hoàn thành, Trì hoãn
  final DateTime dueDate;
  final DateTime? completedDate;
  final String? assignedTo; // Mã nhân viên
  final String? assignedToName;
  final String? fieldId; // Lô đất liên quan
  final String? fieldName;
  final String? machineId; // Máy móc liên quan
  final String? machineName;
  final List<String>? tags;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.dueDate,
    this.completedDate,
    this.assignedTo,
    this.assignedToName,
    this.fieldId,
    this.fieldName,
    this.machineId,
    this.machineName,
    this.tags,
    required this.createdAt,
    this.updatedAt,
  });

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final title = map['title']?.toString().trim() ?? '';
    final dueDate = _parseTaskDate(map['dueDate']);

    if (id.isEmpty || title.isEmpty || dueDate == null) {
      throw const FormatException('Dữ liệu công việc không hợp lệ.');
    }

    return TaskModel(
      id: id,
      title: title,
      description: map['description']?.toString() ?? '',
      priority: _parseTaskPriority(map['priority']),
      status: _parseTaskStatus(map['status']),
      dueDate: dueDate,
      completedDate: _parseTaskDate(map['completedDate']),
      assignedTo: _taskString(map['assignedTo']),
      assignedToName: _taskString(map['assignedToName']),
      fieldId: _taskString(map['fieldId']),
      fieldName: _taskString(map['fieldName']),
      machineId: _taskString(map['machineId']),
      machineName: _taskString(map['machineName']),
      tags: _parseTaskTags(map['tags']),
      createdAt: _parseTaskDate(map['createdAt']) ?? dueDate,
      updatedAt: _parseTaskDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'priority': priority.index,
      'status': status.index,
      'dueDate': dueDate.toIso8601String(),
      'completedDate': completedDate?.toIso8601String(),
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'fieldId': fieldId,
      'fieldName': fieldName,
      'machineId': machineId,
      'machineName': machineName,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // Copy with method
  TaskModel copyWith({
    String? title,
    String? description,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? dueDate,
    DateTime? completedDate,
    String? assignedTo,
    String? assignedToName,
    String? fieldId,
    String? fieldName,
    String? machineId,
    String? machineName,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      completedDate: completedDate ?? this.completedDate,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      fieldId: fieldId ?? this.fieldId,
      fieldName: fieldName ?? this.fieldName,
      machineId: machineId ?? this.machineId,
      machineName: machineName ?? this.machineName,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

enum TaskPriority { LOW, MEDIUM, HIGH }

enum TaskStatus { PENDING, IN_PROGRESS, COMPLETED, DELAYED }

DateTime? _parseTaskDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

TaskPriority _parseTaskPriority(dynamic value) {
  if (value is num) {
    final index = value.toInt();
    if (index >= 0 && index < TaskPriority.values.length) {
      return TaskPriority.values[index];
    }
  }

  final name = value?.toString().split('.').last.trim().toUpperCase();
  return TaskPriority.values.firstWhere(
    (priority) => priority.name == name,
    orElse: () => TaskPriority.MEDIUM,
  );
}

TaskStatus _parseTaskStatus(dynamic value) {
  if (value is num) {
    final index = value.toInt();
    if (index >= 0 && index < TaskStatus.values.length) {
      return TaskStatus.values[index];
    }
  }

  final name = value?.toString().split('.').last.trim().toUpperCase();
  return TaskStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => TaskStatus.PENDING,
  );
}

String? _taskString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String>? _parseTaskTags(dynamic value) {
  if (value is! Iterable) return null;
  final tags = value
      .map((tag) => tag?.toString().trim() ?? '')
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return tags.isEmpty ? const <String>[] : tags;
}

extension TaskPriorityExtension on TaskPriority {
  String get displayName {
    switch (this) {
      case TaskPriority.LOW:
        return 'Thấp';
      case TaskPriority.MEDIUM:
        return 'Trung bình';
      case TaskPriority.HIGH:
        return 'Cao';
    }
  }

  Color get color {
    switch (this) {
      case TaskPriority.LOW:
        return Colors.blue;
      case TaskPriority.MEDIUM:
        return Colors.orange;
      case TaskPriority.HIGH:
        return Colors.red;
    }
  }
}

extension TaskStatusExtension on TaskStatus {
  String get displayName {
    switch (this) {
      case TaskStatus.PENDING:
        return 'Chưa làm';
      case TaskStatus.IN_PROGRESS:
        return 'Đang làm';
      case TaskStatus.COMPLETED:
        return 'Hoàn thành';
      case TaskStatus.DELAYED:
        return 'Trì hoãn';
    }
  }

  Color get color {
    switch (this) {
      case TaskStatus.PENDING:
        return Colors.grey;
      case TaskStatus.IN_PROGRESS:
        return Colors.blue;
      case TaskStatus.COMPLETED:
        return Colors.green;
      case TaskStatus.DELAYED:
        return Colors.red;
    }
  }
}
