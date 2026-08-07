import 'package:flutter/material.dart';
import '../providers/warehouse_provider.dart';
import '../models/warehouse_item.dart';

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  // Khởi tạo provider
  final WarehouseProvider _provider = WarehouseProvider();

  // Hiển thị hộp thoại nhập/xuất
  void _showTransactionDialog({required String id, required bool isImport}) {
    final TextEditingController qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isImport ? 'NHẬP KHO' : 'XUẤT KHO'),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số lượng',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                int qty = int.tryParse(qtyController.text) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập số lượng hợp lệ'),
                    ),
                  );
                  return;
                }
                try {
                  if (isImport) {
                    _provider.importItem(id, qty);
                  } else {
                    _provider.exportItem(id, qty);
                  }
                  Navigator.pop(ctx);
                  setState(() {}); // Cập nhật lại danh sách
                } catch (e) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: Text(isImport ? 'Nhập' : 'Xuất'),
            ),
          ],
        );
      },
    );
  }

  // Hộp thoại thêm vật tư mới
  void _showAddItemDialog() {
    final TextEditingController idCtrl = TextEditingController();
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController unitCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController();
    final TextEditingController supplierCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('THÊM VẬT TƯ MỚI'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'Mã hàng'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên hàng'),
                ),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(labelText: 'Đơn vị tính'),
                ),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Đơn giá nhập'),
                ),
                TextField(
                  controller: supplierCtrl,
                  decoration: const InputDecoration(labelText: 'Nhà cung cấp'),
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
                final newItem = WarehouseItem(
                  id: idCtrl.text,
                  name: nameCtrl.text,
                  unit: unitCtrl.text,
                  importPrice: double.tryParse(priceCtrl.text) ?? 0,
                  supplier: supplierCtrl.text,
                  stock: 0,
                );
                _provider.addItem(newItem);
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Kho'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showAddItemDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _provider.items.length,
        itemBuilder: (ctx, index) {
          final item = _provider.items[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.inventory, color: Colors.green),
              title: Text('${item.name} (${item.id})'),
              subtitle: Text(
                'Tồn: ${item.stock} ${item.unit}  •  Đơn giá: ${item.importPrice} VND',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_box, color: Colors.blue),
                    onPressed: () =>
                        _showTransactionDialog(id: item.id, isImport: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.orange),
                    onPressed: () =>
                        _showTransactionDialog(id: item.id, isImport: false),
                  ),
                ],
              ),
              isThreeLine: false,
            ),
          );
        },
      ),
    );
  }
}
