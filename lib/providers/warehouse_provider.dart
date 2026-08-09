import 'package:flutter/material.dart';
import '../models/warehouse_item.dart';
import '../services/material_production_cost_sync_service.dart';

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

  // Hàm xuất kho: giảm số lượng tồn và đồng bộ chi phí sản xuất nếu có thửa.
  // Các tham số mới đều optional để giữ tương thích với luồng cũ.
  void exportItem(
    String id,
    int quantity, {
    String? fieldId,
    String? fieldName,
    String? seasonId,
    String? notes,
  }) {
    final item = _items.firstWhere((e) => e.id == id);
    if (item.stock >= quantity) {
      item.stock -= quantity;

      if (fieldId != null && fieldId.isNotEmpty) {
        final transactionId =
            'WH-MATERIAL-${DateTime.now().microsecondsSinceEpoch}';
        _syncProductionCost(
          transactionId: transactionId,
          item: item,
          quantity: quantity,
          fieldId: fieldId,
          fieldName: fieldName,
          seasonId: seasonId,
          notes: notes,
        );
      }

      notifyListeners();
    } else {
      throw Exception('Không đủ hàng trong kho');
    }
  }

  Future<void> _syncProductionCost({
    required String transactionId,
    required WarehouseItem item,
    required int quantity,
    required String fieldId,
    String? fieldName,
    String? seasonId,
    String? notes,
  }) async {
    try {
      await MaterialProductionCostSyncService().syncExport(
        transactionId: transactionId,
        itemId: item.id,
        itemName: item.name,
        unit: item.unit,
        quantity: quantity.toDouble(),
        unitPrice: item.importPrice,
        fieldId: fieldId,
        seasonId: seasonId,
        notes: notes ??
            'Xuất ${item.name} cho ${fieldName ?? 'thửa sản xuất'}',
      );
    } catch (_) {
      // Không để lỗi ledger làm hỏng thao tác xuất kho.
      // Có thể đồng bộ lại từ lịch sử giao dịch khi kho có database giao dịch.
    }
  }

  // Thêm vật tư mới
  void addItem(WarehouseItem newItem) {
    _items.add(newItem);
    notifyListeners();
  }
}
