import 'package:flutter/material.dart';
import '../providers/machine_provider.dart';
import '../providers/field_provider.dart';
import '../models/machine_model.dart';
import '../models/field_model.dart';

class MachineAssignmentScreen extends StatefulWidget {
  const MachineAssignmentScreen({super.key});

  @override
  State<MachineAssignmentScreen> createState() =>
      _MachineAssignmentScreenState();
}

class _MachineAssignmentScreenState extends State<MachineAssignmentScreen> {
  final MachineProvider _machineProvider = MachineProvider();
  final FieldProvider _fieldProvider = FieldProvider();

  String? selectedFieldId;
  String? selectedMachineId;
  String? selectedOperator;

  @override
  Widget build(BuildContext context) {
    // Danh sách máy đang rảnh
    final availableMachines = _machineProvider.machines
        .where((m) => m.currentFieldId == null && m.status == 'Tốt')
        .toList();

    // Danh sách máy đang làm việc
    final workingMachines = _machineProvider.machines
        .where((m) => m.currentFieldId != null)
        .toList();

    // Danh sách lô đất
    final fields = _fieldProvider.fields;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gán Máy vào Lô đất'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề
            const Text(
              'Quản lý máy móc theo lô đất',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gán máy móc vào lô đất để theo dõi chi phí và hiệu suất',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // ====== PHẦN GÁN MÁY MỚI ======
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GÁN MÁY MỚI VÀO LÔ ĐẤT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Chọn Lô đất
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Chọn Lô đất *',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedFieldId,
                      items: fields.map((field) {
                        return DropdownMenuItem(
                          value: field.id,
                          child: Text('${field.name} (${field.area}m²)'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedFieldId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Chọn Máy
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Chọn Máy *',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedMachineId,
                      items: availableMachines.map((machine) {
                        return DropdownMenuItem(
                          value: machine.id,
                          child: Text('${machine.name} (${machine.type})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedMachineId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Nhập tên người vận hành
                    TextField(
                      onChanged: (value) {
                        selectedOperator = value;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Tên người vận hành',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (selectedFieldId != null &&
                                selectedMachineId != null)
                            ? () {
                                _assignMachine();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'GÁN MÁY',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ====== DANH SÁCH MÁY ĐANG LÀM VIỆC ======
            const Text(
              'MÁY ĐANG LÀM VIỆC',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            if (workingMachines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Không có máy nào đang làm việc')),
                ),
              )
            else
              ...workingMachines.map((machine) {
                final fieldName = _fieldProvider.fields
                    .firstWhere((f) => f.id == machine.currentFieldId)
                    .name;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.agriculture, color: Colors.green),
                    title: Text(machine.name),
                    subtitle: Text(
                      'Đang làm tại: $fieldName | Giờ: ${machine.totalHours}h',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.blue),
                          onPressed: () {
                            _showUpdateProgressDialog(machine);
                          },
                          tooltip: 'Cập nhật tiến độ',
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () {
                            _completeWork(machine);
                          },
                          tooltip: 'Hoàn thành',
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),

            // ====== DANH SÁCH MÁY RẢNH ======
            const Text(
              'MÁY RẢNH',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            if (availableMachines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Không có máy nào rảnh')),
                ),
              )
            else
              ...availableMachines.map((machine) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.agriculture, color: Colors.grey),
                    title: Text(machine.name),
                    subtitle: Text('${machine.type} - ${machine.status}'),
                    trailing: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ====== HÀM GÁN MÁY ======
  void _assignMachine() {
    final field = _fieldProvider.fields.firstWhere(
      (f) => f.id == selectedFieldId,
    );
    final machine = _machineProvider.machines.firstWhere(
      (m) => m.id == selectedMachineId,
    );
    final operatorName = selectedOperator ?? 'Chưa có';

    _machineProvider.assignMachineToField(
      selectedMachineId!,
      selectedFieldId!,
      field.name,
      operatorName,
    );

    setState(() {
      selectedFieldId = null;
      selectedMachineId = null;
      selectedOperator = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã gán ${machine.name} vào ${field.name}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ====== HÀM CẬP NHẬT TIẾN ĐỘ ======
  void _showUpdateProgressDialog(MachineModel machine) {
    final TextEditingController hoursCtrl = TextEditingController();
    final TextEditingController fuelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('CẬP NHẬT TIẾN ĐỘ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Máy: ${machine.name}'),
              const SizedBox(height: 8),
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số giờ làm thêm',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fuelCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nhiên liệu tiêu thụ (Lít)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                final hours = double.tryParse(hoursCtrl.text) ?? 0;
                final fuel = double.tryParse(fuelCtrl.text) ?? 0;
                if (hours > 0 || fuel > 0) {
                  _machineProvider.updateFieldProgress(machine.id, hours, fuel);
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Đã cập nhật tiến độ!')),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Vui lòng nhập số giờ hoặc nhiên liệu hợp lệ',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Cập nhật'),
            ),
          ],
        );
      },
    );
  }

  // ====== HÀM HOÀN THÀNH CÔNG VIỆC ======
  void _completeWork(MachineModel machine) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('XÁC NHẬN'),
          content: Text('Hoàn thành công việc của ${machine.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                _machineProvider.completeFieldWork(machine.id);
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Đã hoàn thành công việc của ${machine.name}',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Đồng ý'),
            ),
          ],
        );
      },
    );
  }
}
