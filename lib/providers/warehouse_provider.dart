import 'package:flutter/material.dart';
import '../models/warehouse_item.dart';

// Đây là bộ nhớ tạm (giả lập dữ liệu)
class WarehouseProvider extends ChangeNotifier {
  List<WarehouseItem> _items = [];

  List<WarehouseItem> get items => _items;

  // Khởi tạo với dữ liệu mẫu giống file Excel
  WarehouseProvider() {
    _items = [
      WarehouseItem(
        id: 'PB0001',
        name: 'Phân Kali',
        unit: 'Kg',
        importPrice: 15000,
        supplier: 'Công ty Phân bón A',
        stock: 200,
      ),
      WarehouseItem(
        id: 'PB0002',
        name: 'Phân Lân',
        unit: 'Kg',
        importPrice: 12000,
        supplier: 'Công ty Phân bón B',
        stock: 150,
      ),
      WarehouseItem(
        id: 'PB0003',
        name: 'Phân Đạm',
        unit: 'Kg',
        importPrice: 18000,
        supplier: 'Công ty Phân bón C',
        stock: 80,
      ),
    ];
  }

  // Hàm nhập kho: tăng số lượng tồn
  void importItem(String id, int quantity) {
    final item = _items.firstWhere((e) => e.id == id);
    item.stock += quantity;
    notifyListeners(); // Cập nhật giao diện
  }

  // Hàm xuất kho: giảm số lượng tồn
  void exportItem(String id, int quantity) {
    final item = _items.firstWhere((e) => e.id == id);
    if (item.stock >= quantity) {
      item.stock -= quantity;
      notifyListeners();
    } else {
      throw Exception('Không đủ hàng trong kho');
    }
  }

  // Thêm vật tư mới
  void addItem(WarehouseItem newItem) {
    _items.add(newItem);
    notifyListeners();
  }
}
