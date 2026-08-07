import 'package:flutter/material.dart';
import '../models/employee_model.dart';
import '../providers/employee_provider.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final EmployeeModel employee;
  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late EmployeeModel _currentEmployee;
  final EmployeeProvider _provider = EmployeeProvider();

  @override
  void initState() {
    super.initState();
    _currentEmployee = widget.employee;
    _provider.generatePayroll(DateTime.now().month, DateTime.now().year);
  }

  @override
  Widget build(BuildContext context) {
    final attendanceHistory = _provider.getAttendanceHistory(
      _currentEmployee.id,
    );
    final payroll = _provider.payrollRecords.firstWhere(
      (p) => p.employeeId == _currentEmployee.id,
      orElse: () => PayrollRecord(
        employeeId: _currentEmployee.id,
        employeeName: _currentEmployee.name,
        month: DateTime.now().month,
        year: DateTime.now().year,
        workingDays: 0,
        totalSalary: 0,
        netSalary: 0,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentEmployee.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _showEditDialog();
            },
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin cơ bản
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: _currentEmployee.isActive
                              ? Colors.green
                              : Colors.grey,
                          child: Text(
                            _currentEmployee.name[0],
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentEmployee.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_currentEmployee.position} - ${_currentEmployee.department}',
                              ),
                              Text(
                                'Lương: ${_currentEmployee.dailyRate.toStringAsFixed(0)} VND/ngày',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text('📱 ${_currentEmployee.phone}'),
                    if (_currentEmployee.address != null)
                      Text('📍 ${_currentEmployee.address}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _toggleStatus,
                            icon: Icon(
                              _currentEmployee.isActive
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            label: Text(
                              _currentEmployee.isActive
                                  ? 'Tạm nghỉ'
                                  : 'Quay lại làm',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _currentEmployee.isActive
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Chấm công
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chấm công',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _checkIn,
                            icon: const Icon(Icons.login),
                            label: const Text('Check-in'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _checkOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('Check-out'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hôm nay: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Bảng lương
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bảng lương tháng này',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildPayrollStat(
                          'Ngày công',
                          payroll.workingDays.toString(),
                          Icons.calendar_today,
                        ),
                        _buildPayrollStat(
                          'Tổng lương',
                          '${payroll.totalSalary.toStringAsFixed(0)} VND',
                          Icons.money,
                        ),
                        _buildPayrollStat(
                          'Thực lĩnh',
                          '${payroll.netSalary.toStringAsFixed(0)} VND',
                          Icons.payment,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lịch sử chấm công
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lịch sử chấm công (gần đây)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (attendanceHistory.isEmpty)
                      const Text('Chưa có dữ liệu chấm công')
                    else
                      ...attendanceHistory.take(5).map((record) {
                        return ListTile(
                          title: Text(
                            '${record.date.day}/${record.date.month}/${record.date.year}',
                          ),
                          subtitle: Text(
                            'Check-in: ${record.checkIn.hour}:${record.checkIn.minute.toString().padLeft(2, '0')} '
                            'Check-out: ${record.checkOut != null ? "${record.checkOut!.hour}:${record.checkOut!.minute.toString().padLeft(2, '0')}" : "---"} '
                            'Giờ: ${record.hours.toStringAsFixed(1)}h',
                          ),
                          leading: const Icon(Icons.history),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayrollStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _toggleStatus() {
    setState(() {
      _currentEmployee = _currentEmployee.copyWith(
        isActive: !_currentEmployee.isActive,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _currentEmployee.isActive
              ? 'Nhân viên đã quay lại làm'
              : 'Nhân viên đã tạm nghỉ',
        ),
      ),
    );
  }

  void _checkIn() {
    _provider.checkIn(_currentEmployee.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã check-in thành công!')));
  }

  void _checkOut() {
    _provider.checkOut(_currentEmployee.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã check-out thành công!')));
    // Cập nhật lại bảng lương
    setState(() {
      _provider.generatePayroll(DateTime.now().month, DateTime.now().year);
    });
  }

  void _showEditDialog() {
    final TextEditingController nameCtrl = TextEditingController(
      text: _currentEmployee.name,
    );
    final TextEditingController positionCtrl = TextEditingController(
      text: _currentEmployee.position,
    );
    final TextEditingController departmentCtrl = TextEditingController(
      text: _currentEmployee.department,
    );
    final TextEditingController rateCtrl = TextEditingController(
      text: _currentEmployee.dailyRate.toString(),
    );
    final TextEditingController phoneCtrl = TextEditingController(
      text: _currentEmployee.phone,
    );
    final TextEditingController addressCtrl = TextEditingController(
      text: _currentEmployee.address ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('CẬP NHẬT NHÂN VIÊN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                ),
                TextField(
                  controller: positionCtrl,
                  decoration: const InputDecoration(labelText: 'Vị trí'),
                ),
                TextField(
                  controller: departmentCtrl,
                  decoration: const InputDecoration(labelText: 'Bộ phận'),
                ),
                TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lương theo ngày (VND)',
                  ),
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
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
                final updated = EmployeeModel(
                  id: _currentEmployee.id,
                  name: nameCtrl.text,
                  position: positionCtrl.text,
                  department: departmentCtrl.text,
                  dailyRate: double.tryParse(rateCtrl.text) ?? 0,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text.isNotEmpty
                      ? addressCtrl.text
                      : null,
                  isActive: _currentEmployee.isActive,
                );
                setState(() {
                  _currentEmployee = updated;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật thông tin!')),
                );
              },
              child: const Text('Cập nhật'),
            ),
          ],
        );
      },
    );
  }
}
