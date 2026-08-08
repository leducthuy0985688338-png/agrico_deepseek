import 'package:flutter/material.dart';
import '../providers/task_provider.dart';
import '../models/task_model.dart';
import '../theme/app_theme.dart';

class TaskDetailScreen extends StatefulWidget {
  final TaskModel task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final TaskProvider _provider = TaskProvider();

  late TaskModel _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;

    final isOverdue =
        task.dueDate.isBefore(DateTime.now()) &&
        task.status != TaskStatus.COMPLETED;

    return Scaffold(
      appBar: AppBar(
        title: Text(task.title),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showEditDialog,
            icon: const Icon(Icons.edit),
            tooltip: 'Chỉnh sửa',
          ),
          IconButton(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete),
            tooltip: 'Xóa',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==============================
            // TRẠNG THÁI VÀ ƯU TIÊN
            // ==============================
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: task.status.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.status.displayName,
                    style: TextStyle(
                      color: task.status.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: task.priority.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Ưu tiên ${task.priority.displayName}',
                    style: TextStyle(
                      color: task.priority.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (isOverdue) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Quá hạn',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // ==============================
            // MÔ TẢ
            // ==============================
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mô tả',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      task.description.isNotEmpty
                          ? task.description
                          : 'Không có mô tả',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==============================
            // THÔNG TIN CHI TIẾT
            // ==============================
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thông tin chi tiết',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _buildDetailItem(
                      'Ngày hạn',
                      '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                      Icons.calendar_today,
                      isOverdue ? Colors.red : null,
                    ),

                    if (task.completedDate != null)
                      _buildDetailItem(
                        'Hoàn thành ngày',
                        '${task.completedDate!.day}/${task.completedDate!.month}/${task.completedDate!.year}',
                        Icons.check_circle,
                        Colors.green,
                      ),

                    _buildDetailItem(
                      'Người được giao',
                      task.assignedToName ?? 'Chưa phân công',
                      Icons.person,
                    ),

                    if (task.fieldName != null)
                      _buildDetailItem(
                        'Lô đất',
                        task.fieldName!,
                        Icons.map,
                        Colors.blue,
                      ),

                    if (task.machineName != null)
                      _buildDetailItem(
                        'Máy móc',
                        task.machineName!,
                        Icons.agriculture,
                        Colors.orange,
                      ),

                    if (task.tags != null && task.tags!.isNotEmpty)
                      _buildDetailItem(
                        'Tags',
                        task.tags!.map((t) => '#$t').join(' '),
                        Icons.label,
                        Colors.purple,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==============================
            // CẬP NHẬT TRẠNG THÁI
            // ==============================
            const Text(
              'Cập nhật trạng thái',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TaskStatus.values.map((status) {
                final isCurrentStatus = task.status == status;

                return ElevatedButton(
                  onPressed: isCurrentStatus
                      ? null
                      : () => _updateStatus(status),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCurrentStatus
                        ? status.color
                        : Colors.grey.shade200,
                    foregroundColor: isCurrentStatus
                        ? Colors.white
                        : Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(status.displayName),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================
  // CHI TIẾT
  // ==============================
  Widget _buildDetailItem(
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade600),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==============================
  // CẬP NHẬT TRẠNG THÁI
  // ==============================
  void _updateStatus(TaskStatus newStatus) {
    final updatedTask = _task.copyWith(
      status: newStatus,
      completedDate: newStatus == TaskStatus.COMPLETED ? DateTime.now() : null,
      updatedAt: DateTime.now(),
    );

    _provider.updateTask(updatedTask);

    setState(() {
      _task = updatedTask;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã cập nhật trạng thái: ${newStatus.displayName}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ==============================
  // CHỈNH SỬA CÔNG VIỆC
  // ==============================
  void _showEditDialog() {
    final TextEditingController titleCtrl = TextEditingController(
      text: _task.title,
    );

    final TextEditingController descCtrl = TextEditingController(
      text: _task.description,
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Chỉnh sửa công việc'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('Hủy'),
            ),

            ElevatedButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                final description = descCtrl.text.trim();

                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập tiêu đề công việc!'),
                    ),
                  );
                  return;
                }

                final updatedTask = _task.copyWith(
                  title: title,
                  description: description,
                  updatedAt: DateTime.now(),
                );

                _provider.updateTask(updatedTask);

                setState(() {
                  _task = updatedTask;
                });

                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật công việc!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  // ==============================
  // XÓA CÔNG VIỆC
  // ==============================
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Xác nhận xóa'),

          content: Text('Bạn có chắc muốn xóa công việc "${_task.title}"?'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('Hủy'),
            ),

            ElevatedButton(
              onPressed: () {
                _provider.deleteTask(_task.id);

                Navigator.pop(ctx);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xóa công việc!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),

              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );
  }
}
