import 'package:flutter/material.dart';
import '../providers/task_provider.dart';
import '../models/task_model.dart';
import 'task_detail_screen.dart';
import 'task_add_screen.dart';
import '../theme/app_theme.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final TaskProvider _provider = TaskProvider();
  String _selectedFilter = 'Tất cả';

  final List<String> _filterOptions = [
    'Tất cả',
    'Chưa làm',
    'Đang làm',
    'Hoàn thành',
    'Trì hoãn',
    'Quá hạn',
  ];

  @override
  Widget build(BuildContext context) {
    // Lọc công việc
    List<TaskModel> filteredTasks = _provider.tasks;
    switch (_selectedFilter) {
      case 'Chưa làm':
        filteredTasks = _provider.getTasksByStatus(TaskStatus.PENDING);
        break;
      case 'Đang làm':
        filteredTasks = _provider.getTasksByStatus(TaskStatus.IN_PROGRESS);
        break;
      case 'Hoàn thành':
        filteredTasks = _provider.getTasksByStatus(TaskStatus.COMPLETED);
        break;
      case 'Trì hoãn':
        filteredTasks = _provider.getTasksByStatus(TaskStatus.DELAYED);
        break;
      case 'Quá hạn':
        filteredTasks = _provider.getOverdueTasks();
        break;
      default:
        filteredTasks = _provider.tasks;
    }

    final stats = _provider.getTaskStatistics();
    final overdueCount = _provider.getOverdueTasks().length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch công việc'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (overdueCount > 0)
            Stack(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedFilter = 'Quá hạn';
                    });
                  },
                  icon: const Icon(Icons.warning_amber_outlined),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      overdueCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            onPressed: () {
              _showFilterDialog();
            },
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          // Thống kê nhanh
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '📋',
                  '${stats[TaskStatus.PENDING] ?? 0}',
                  'Chờ làm',
                ),
                _buildStatItem(
                  '🔄',
                  '${stats[TaskStatus.IN_PROGRESS] ?? 0}',
                  'Đang làm',
                ),
                _buildStatItem(
                  '✅',
                  '${stats[TaskStatus.COMPLETED] ?? 0}',
                  'Hoàn thành',
                ),
                _buildStatItem(
                  '⚠️',
                  overdueCount.toString(),
                  'Quá hạn',
                  isWarning: true,
                ),
              ],
            ),
          ),
          // Bộ lọc
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _filterOptions.map((filter) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(filter),
                            selected: _selectedFilter == filter,
                            onSelected: (selected) {
                              setState(() {
                                _selectedFilter = filter;
                              });
                            },
                            backgroundColor: Colors.grey.shade200,
                            selectedColor: AppTheme.primaryColor.withOpacity(
                              0.2,
                            ),
                            labelStyle: TextStyle(
                              color: _selectedFilter == filter
                                  ? AppTheme.primaryColor
                                  : Colors.black54,
                              fontWeight: _selectedFilter == filter
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Danh sách công việc
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Không có công việc nào',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tạo công việc mới để bắt đầu',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredTasks.length,
                    itemBuilder: (ctx, index) {
                      final task = filteredTasks[index];
                      return _buildTaskCard(task);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaskAddScreen()),
          ).then((_) {
            setState(() {});
          });
        },
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatItem(
    String icon,
    String count,
    String label, {
    bool isWarning = false,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 4),
            Text(
              count,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isWarning ? Colors.red : AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isWarning ? Colors.red : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    final isOverdue =
        task.dueDate.isBefore(DateTime.now()) &&
        task.status != TaskStatus.COMPLETED;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOverdue
            ? BorderSide(color: Colors.red.shade300, width: 1)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: task.priority.color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            task.priority == TaskPriority.HIGH
                ? Icons.flag
                : task.priority == TaskPriority.MEDIUM
                ? Icons.flag_outlined
                : Icons.flag_outlined,
            color: task.priority.color,
            size: 20,
          ),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: task.priority == TaskPriority.HIGH
                ? FontWeight.bold
                : FontWeight.normal,
            decoration: task.status == TaskStatus.COMPLETED
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.description.length > 50
                  ? '${task.description.substring(0, 50)}...'
                  : task.description,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 2),
                Text(
                  task.assignedToName ?? 'Chưa phân công',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.calendar_today,
                  size: 12,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 2),
                Text(
                  '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isOverdue ? Colors.red : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: task.status.color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            task.status.displayName,
            style: TextStyle(
              fontSize: 10,
              color: task.status.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
          ).then((_) {
            setState(() {});
          });
        },
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Lọc công việc',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ..._filterOptions.map((filter) {
                return ListTile(
                  title: Text(filter),
                  trailing: _selectedFilter == filter
                      ? const Icon(Icons.check, color: AppTheme.primaryColor)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedFilter = filter;
                    });
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}
