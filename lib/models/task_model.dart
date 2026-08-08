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
