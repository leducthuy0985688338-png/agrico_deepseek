import 'package:flutter/material.dart';
import '../models/machine_model.dart';
import '../providers/machine_provider.dart';

class MachineDetailScreen extends StatefulWidget {
  final MachineModel machine;
  const MachineDetailScreen({super.key, required this.machine});

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  // Lưu trữ dữ liệu máy hiện tại (có thể thay đổi)
  late MachineModel _currentMachine;
  final MachineProvider _provider = MachineProvider();

  // Các controller cho nhật ký vận hành
  final TextEditingController hoursCtrl = TextEditingController();

  // Controller cho bảo trì
  final TextEditingController maintenanceContentCtrl = TextEditingController();
  final TextEditingController maintenanceCostCtrl = TextEditingController();
  final TextEditingController partsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentMachine = widget.machine;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentMachine.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentMachine.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(_currentMachine.status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _currentMachine.status,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text('Loại: ${_currentMachine.type}'),
                    Text('Hãng: ${_currentMachine.manufacturer}'),
                    Text('Năm: ${_currentMachine.year}'),
                    Text('Tổng giờ: ${_currentMachine.totalHours} giờ'),
                    Text(
                      'Tiêu thụ nhiên liệu: ${_currentMachine.fuelConsumption} L/h',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cập nhật trạng thái
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cập nhật trạng thái',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _updateStatus('Tốt');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Tốt'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _updateStatus('Đang bảo trì');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('Bảo trì'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _updateStatus('Hỏng');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Hỏng'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Thêm giờ vận hành
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cập nhật giờ vận hành',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: hoursCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số giờ vận hành',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            int hours = int.tryParse(hoursCtrl.text) ?? 0;
                            if (hours > 0) {
                              _updateHours(hours);
                              hoursCtrl.clear();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Vui lòng nhập số giờ hợp lệ'),
                                ),
                              );
                            }
                          },
                          child: const Text('Cập nhật'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Nhật ký bảo trì
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lịch sử bảo trì',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_currentMachine.maintenanceHistory.isEmpty)
                      const Text('Chưa có bảo trì nào'),
                    ..._currentMachine.maintenanceHistory.map((record) {
                      return ListTile(
                        title: Text(record.content),
                        subtitle: Text(
                          '${record.date.day}/${record.date.month}/${record.date.year} - ${record.cost.toStringAsFixed(0)} VND',
                        ),
                        trailing: record.parts != null
                            ? Text(
                                'Phụ tùng: ${record.parts}',
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maintenanceContentCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nội dung bảo trì',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: maintenanceCostCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Chi phí',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: partsCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Phụ tùng thay thế (tùy chọn)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            _addMaintenance();
                          },
                          child: const Text('Thêm bảo trì'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Hàm cập nhật trạng thái
  void _updateStatus(String newStatus) {
    // Cập nhật trong Provider
    _provider.updateMachineStatus(_currentMachine.id, newStatus);
    // Cập nhật trong State
    setState(() {
      _currentMachine = _currentMachine.copyWith(status: newStatus);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã cập nhật trạng thái: $newStatus')),
    );
  }

  // Hàm cập nhật giờ vận hành
  void _updateHours(int hours) {
    _provider.updateMachineHours(_currentMachine.id, hours);
    setState(() {
      _currentMachine = _currentMachine.copyWith(
        totalHours: _currentMachine.totalHours + hours,
      );
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã thêm $hours giờ vận hành')));
  }

  // Hàm thêm bảo trì
  void _addMaintenance() {
    final content = maintenanceContentCtrl.text.trim();
    final cost = double.tryParse(maintenanceCostCtrl.text) ?? 0;
    final parts = partsCtrl.text.trim();

    if (content.isEmpty || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập nội dung và chi phí hợp lệ'),
        ),
      );
      return;
    }

    final newRecord = MaintenanceRecord(
      date: DateTime.now(),
      content: content,
      cost: cost,
      parts: parts.isNotEmpty ? parts : null,
    );

    setState(() {
      final updatedHistory = List<MaintenanceRecord>.from(
        _currentMachine.maintenanceHistory,
      )..add(newRecord);
      _currentMachine = _currentMachine.copyWith(
        maintenanceHistory: updatedHistory,
      );
    });

    maintenanceContentCtrl.clear();
    maintenanceCostCtrl.clear();
    partsCtrl.clear();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã thêm bảo trì thành công')));
  }

  // Hàm lấy màu theo trạng thái
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Tốt':
        return Colors.green;
      case 'Đang bảo trì':
        return Colors.orange;
      case 'Hỏng':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
