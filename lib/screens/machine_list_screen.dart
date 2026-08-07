import 'package:flutter/material.dart';
import '../providers/machine_provider.dart';
import '../models/machine_model.dart';
import 'machine_detail_screen.dart';

class MachineListScreen extends StatelessWidget {
  const MachineListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = MachineProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Máy móc'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              // Sẽ thêm máy mới sau
              _showAddMachineDialog(context, provider);
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: provider.machines.length,
        itemBuilder: (ctx, index) {
          final machine = provider.machines[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: _getStatusIcon(machine.status),
              title: Text(
                machine.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${machine.type} - ${machine.manufacturer} (${machine.year})',
                  ),
                  Text(
                    'Giờ: ${machine.totalHours}h | Nhiên liệu: ${machine.fuelConsumption}L/h',
                  ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(machine.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  machine.status,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MachineDetailScreen(machine: machine),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Icon trạng thái
  Widget _getStatusIcon(String status) {
    IconData iconData;
    Color color;
    switch (status) {
      case 'Tốt':
        iconData = Icons.check_circle;
        color = Colors.green;
        break;
      case 'Đang bảo trì':
        iconData = Icons.build;
        color = Colors.orange;
        break;
      case 'Hỏng':
        iconData = Icons.error;
        color = Colors.red;
        break;
      default:
        iconData = Icons.help;
        color = Colors.grey;
    }
    return Icon(iconData, color: color);
  }

  // Màu trạng thái
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

  // Hộp thoại thêm máy mới
  void _showAddMachineDialog(BuildContext context, MachineProvider provider) {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController typeCtrl = TextEditingController();
    final TextEditingController manufacturerCtrl = TextEditingController();
    final TextEditingController yearCtrl = TextEditingController();
    final TextEditingController fuelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('THÊM MÁY MỚI'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên máy'),
                ),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Loại máy (Máy cày, Máy gặt...)',
                  ),
                ),
                TextField(
                  controller: manufacturerCtrl,
                  decoration: const InputDecoration(labelText: 'Hãng sản xuất'),
                ),
                TextField(
                  controller: yearCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Năm sản xuất'),
                ),
                TextField(
                  controller: fuelCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu thụ nhiên liệu (L/h)',
                  ),
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
                final newMachine = MachineModel(
                  id: 'M${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text,
                  type: typeCtrl.text,
                  manufacturer: manufacturerCtrl.text,
                  year: int.tryParse(yearCtrl.text) ?? 2024,
                  status: 'Tốt',
                  fuelConsumption: double.tryParse(fuelCtrl.text) ?? 0,
                );
                provider.addMachine(newMachine);
                Navigator.pop(ctx);
                // Refresh UI (cần StatefulWidget để làm điều này)
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Đã thêm máy thành công!')),
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
