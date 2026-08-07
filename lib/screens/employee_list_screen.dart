import 'package:flutter/material.dart';
import '../providers/employee_provider.dart';
import '../models/employee_model.dart';
import 'employee_detail_screen.dart';

class EmployeeListScreen extends StatelessWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = EmployeeProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Nhân sự'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _showAddEmployeeDialog(context, provider);
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          // Thống kê nhanh
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Tổng nhân sự',
                    provider.employees.length,
                    Icons.people,
                  ),
                  _buildStatItem(
                    'Sản xuất',
                    provider.getEmployeesByDepartment('Sản xuất').length,
                    Icons.factory,
                  ),
                  _buildStatItem(
                    'Văn phòng',
                    provider.getEmployeesByDepartment('Văn phòng').length,
                    Icons.business,
                  ),
                ],
              ),
            ),
          ),
          // Danh sách nhân viên
          Expanded(
            child: ListView.builder(
              itemCount: provider.employees.length,
              itemBuilder: (ctx, index) {
                final employee = provider.employees[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: employee.isActive
                          ? Colors.green
                          : Colors.grey,
                      child: Text(
                        employee.name[0],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      employee.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${employee.position} - ${employee.department}\nLương: ${employee.dailyRate.toStringAsFixed(0)} VND/ngày',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: employee.isActive ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        employee.isActive ? 'Đang làm' : 'Nghỉ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              EmployeeDetailScreen(employee: employee),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // Hộp thoại thêm nhân viên mới
  void _showAddEmployeeDialog(BuildContext context, EmployeeProvider provider) {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController positionCtrl = TextEditingController();
    final TextEditingController departmentCtrl = TextEditingController();
    final TextEditingController rateCtrl = TextEditingController();
    final TextEditingController phoneCtrl = TextEditingController();
    final TextEditingController addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('THÊM NHÂN VIÊN MỚI'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ và tên *'),
                ),
                TextField(
                  controller: positionCtrl,
                  decoration: const InputDecoration(labelText: 'Vị trí *'),
                ),
                TextField(
                  controller: departmentCtrl,
                  decoration: const InputDecoration(labelText: 'Bộ phận *'),
                ),
                TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lương theo ngày (VND) *',
                  ),
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại *',
                  ),
                ),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Địa chỉ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isEmpty ||
                    positionCtrl.text.isEmpty ||
                    departmentCtrl.text.isEmpty ||
                    rateCtrl.text.isEmpty ||
                    phoneCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng điền đầy đủ thông tin (*)'),
                    ),
                  );
                  return;
                }

                final newEmployee = EmployeeModel(
                  id: 'NV${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text,
                  position: positionCtrl.text,
                  department: departmentCtrl.text,
                  dailyRate: double.tryParse(rateCtrl.text) ?? 0,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text.isNotEmpty
                      ? addressCtrl.text
                      : null,
                );
                provider.addEmployee(newEmployee);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Đã thêm nhân viên thành công!'),
                  ),
                );
              },
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    );
  }
}
