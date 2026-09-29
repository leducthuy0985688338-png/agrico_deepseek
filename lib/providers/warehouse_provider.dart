import 'package:flutter/material.dart';
import '../models/warehouse_item.dart';
import '../services/material_production_cost_sync_service.dart';

class WarehouseProvider extends ChangeNotifier {
  List<WarehouseItem> _items = [];

  List<WarehouseItem> get items => _items;

  int restoreFromCloud({required List<WarehouseItem> items}) {
    if (items.isEmpty) return 0;

    final restoredById = <String, WarehouseItem>{};
    for (final item in items) {
      final id = item.id.trim();
      if (id.isEmpty) continue;
      restoredById[id] = item;
    }
    if (restoredById.isEmpty) return 0;

    _items = restoredById.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return _items.length;
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
        notes: notes ?? 'Xuất ${item.name} cho ${fieldName ?? 'thửa sản xuất'}',
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
