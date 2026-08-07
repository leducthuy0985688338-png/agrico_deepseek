import 'package:flutter/material.dart';
import '../providers/fuel_provider.dart';
import '../models/fuel_model.dart';
import 'fuel_detail_screen.dart';

class FuelScreen extends StatelessWidget {
  const FuelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = FuelProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Nhiên liệu'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _showAddFuelDialog(context, provider);
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
                    'Tổng giá trị tồn kho',
                    '${provider.getTotalStockValue().toStringAsFixed(0)} VND',
                    Icons.money,
                    Colors.green,
                  ),
                  _buildStatItem(
                    'Số loại nhiên liệu',
                    provider.fuels.length.toString(),
                    Icons.local_gas_station,
                    Colors.blue,
                  ),
                ],
              ),
            ),
          ),
          // Danh sách nhiên liệu
          Expanded(
            child: ListView.builder(
              itemCount: provider.fuels.length,
              itemBuilder: (ctx, index) {
                final fuel = provider.fuels[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_gas_station,
                        color: Colors.orange,
                      ),
                    ),
                    title: Text(
                      fuel.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Tồn: ${fuel.stock} ${fuel.unit} | Đơn giá: ${fuel.unitPrice.toStringAsFixed(0)} VND/${fuel.unit}',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: fuel.stock > 100 ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${fuel.stock} ${fuel.unit}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FuelDetailScreen(fuel: fuel),
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

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  void _showAddFuelDialog(BuildContext context, FuelProvider provider) {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController unitCtrl = TextEditingController();
    final TextEditingController stockCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController();
    final TextEditingController supplierCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('THÊM NHIÊN LIỆU MỚI'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên nhiên liệu *',
                  ),
                ),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Đơn vị tính (Lít, Kg) *',
                  ),
                ),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tồn kho ban đầu *',
                  ),
                ),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Đơn giá nhập *',
                  ),
                ),
                TextField(
                  controller: supplierCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nhà cung cấp *',
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
                if (nameCtrl.text.isEmpty ||
                    unitCtrl.text.isEmpty ||
                    stockCtrl.text.isEmpty ||
                    priceCtrl.text.isEmpty ||
                    supplierCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng điền đầy đủ thông tin (*)'),
                    ),
                  );
                  return;
                }

                final newFuel = FuelModel(
                  id: 'F${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text,
                  unit: unitCtrl.text,
                  stock: double.tryParse(stockCtrl.text) ?? 0,
                  unitPrice: double.tryParse(priceCtrl.text) ?? 0,
                  supplier: supplierCtrl.text,
                );
                provider.addFuel(newFuel);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Đã thêm nhiên liệu thành công!'),
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
