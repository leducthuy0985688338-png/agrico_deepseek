import 'package:flutter/material.dart';
import '../providers/task_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/field_provider.dart';
import '../providers/machine_provider.dart';
import '../models/task_model.dart';
import '../theme/app_theme.dart';

class TaskAddScreen extends StatefulWidget {
  const TaskAddScreen({super.key});

  @override
  State<TaskAddScreen> createState() => _TaskAddScreenState();
}

class _TaskAddScreenState extends State<TaskAddScreen> {
  final TaskProvider _taskProvider = TaskProvider();
  final EmployeeProvider _employeeProvider = EmployeeProvider();
  final FieldProvider _fieldProvider = FieldProvider();
  final MachineProvider _machineProvider = MachineProvider();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  TaskPriority _selectedPriority = TaskPriority.MEDIUM;
  TaskStatus _selectedStatus = TaskStatus.PENDING;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedAssignee;
  String? _selectedField;
  String? _selectedMachine;
  List<String> _selectedTags = [];

  final List<String> _availableTags = [
    'thu hoạch',
    'gieo trồng',
    'bón phân',
    'tưới tiêu',
    'bảo trì',
    'vật tư',
    'nhân công',
    'báo cáo',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm công việc mới'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề công việc *',
                hintText: 'Nhập tiêu đề',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Mô tả
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                hintText: 'Nhập mô tả chi tiết',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Độ ưu tiên
            const Text(
              'Độ ưu tiên',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: TaskPriority.values.map((priority) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(priority.displayName),
                      selected: _selectedPriority == priority,
                      onSelected: (selected) {
                        setState(() {
                          _selectedPriority = priority;
                        });
                      },
                      selectedColor: priority.color.withOpacity(0.3),
                      labelStyle: TextStyle(
                        color: _selectedPriority == priority
                            ? priority.color
                            : Colors.black54,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Trạng thái
            const Text(
              'Trạng thái',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: TaskStatus.values.map((status) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(status.displayName),
                      selected: _selectedStatus == status,
                      onSelected: (selected) {
                        setState(() {
                          _selectedStatus = status;
                        });
                      },
                      selectedColor: status.color.withOpacity(0.3),
                      labelStyle: TextStyle(
                        color: _selectedStatus == status
                            ? status.color
                            : Colors.black54,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Ngày hạn
            const Text(
              'Ngày hạn',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.calendar_today, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Người được giao
            const Text(
              'Người được giao (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Chọn nhân viên',
              ),
              value: _selectedAssignee,
              items: _employeeProvider.employees.map((employee) {
                return DropdownMenuItem(
                  value: employee.id,
                  child: Text(employee.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAssignee = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Lô đất liên quan
            const Text(
              'Lô đất liên quan (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Chọn lô đất',
              ),
              value: _selectedField,
              items: _fieldProvider.fields.map((field) {
                return DropdownMenuItem(
                  value: field.id,
                  child: Text(field.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedField = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Máy móc liên quan
            const Text(
              'Máy móc liên quan (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Chọn máy móc',
              ),
              value: _selectedMachine,
              items: _machineProvider.machines.map((machine) {
                return DropdownMenuItem(
                  value: machine.id,
                  child: Text(machine.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMachine = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Tags
            const Text(
              'Tags (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _availableTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text('#$tag'),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Nút lưu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Tạo công việc',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveTask() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tiêu đề công việc')),
      );
      return;
    }

    String? assigneeName;
    if (_selectedAssignee != null) {
      final employee = _employeeProvider.employees.firstWhere(
        (e) => e.id == _selectedAssignee,
      );
      assigneeName = employee.name;
    }

    String? fieldName;
    if (_selectedField != null) {
      final field = _fieldProvider.fields.firstWhere(
        (f) => f.id == _selectedField,
      );
      fieldName = field.name;
    }

    String? machineName;
    if (_selectedMachine != null) {
      final machine = _machineProvider.machines.firstWhere(
        (m) => m.id == _selectedMachine,
      );
      machineName = machine.name;
    }

    final newTask = TaskModel(
      id: 'T${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text,
      description: _descriptionController.text,
      priority: _selectedPriority,
      status: _selectedStatus,
      dueDate: _selectedDate,
      assignedTo: _selectedAssignee,
      assignedToName: assigneeName,
      fieldId: _selectedField,
      fieldName: fieldName,
      machineId: _selectedMachine,
      machineName: machineName,
      tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      createdAt: DateTime.now(),
    );

    _taskProvider.addTask(newTask);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã tạo công việc thành công!'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }
}
