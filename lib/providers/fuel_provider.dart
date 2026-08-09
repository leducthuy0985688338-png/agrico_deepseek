import 'package:flutter/material.dart';
import '../models/fuel_model.dart';
import '../services/fuel_production_cost_sync_service.dart';

class FuelProvider extends ChangeNotifier {
  List<FuelModel> _fuels = [];
  List<FuelTransaction> _allTransactions = [];

  List<FuelModel> get fuels => _fuels;
  List<FuelTransaction> get allTransactions => _allTransactions;

  FuelProvider() {
    // Dữ liệu mẫu
    _fuels = [
      FuelModel(
        id: 'F001',
        name: 'Dầu Diesel',
        unit: 'Lít',
        stock: 1000,
        unitPrice: 25000,
        supplier: 'Công ty Xăng dầu A',
      ),
      FuelModel(
        id: 'F002',
        name: 'Xăng A95',
        unit: 'Lít',
        stock: 500,
        unitPrice: 22000,
        supplier: 'Công ty Xăng dầu B',
      ),
      FuelModel(
        id: 'F003',
        name: 'Mỡ bôi trơn',
        unit: 'Kg',
        stock: 50,
        unitPrice: 150000,
        supplier: 'Công ty Hóa chất C',
      ),
    ];

    // Thêm giao dịch mẫu
    _addSampleTransactions();
  }

  void _addSampleTransactions() {
    // Nhập kho
    _allTransactions.add(
      FuelTransaction(
        id: 'T001',
        fuelId: 'F001',
        fuelName: 'Dầu Diesel',
        date: DateTime.now().subtract(const Duration(days: 2)),
        type: TransactionType.NHAP,
        quantity: 500,
        price: 25000,
        note: 'Nhập kho đầu tháng',
      ),
    );

    _allTransactions.add(
      FuelTransaction(
        id: 'T002',
        fuelId: 'F002',
        fuelName: 'Xăng A95',
        date: DateTime.now().subtract(const Duration(days: 1)),
        type: TransactionType.NHAP,
        quantity: 200,
        price: 22000,
        note: 'Nhập xăng cho xe tải',
      ),
    );

    // Xuất kho cho máy
    _allTransactions.add(
      FuelTransaction(
        id: 'T003',
        fuelId: 'F001',
        fuelName: 'Dầu Diesel',
        date: DateTime.now().subtract(const Duration(hours: 5)),
        type: TransactionType.XUAT,
        quantity: 50,
        price: 25000,
        machineId: 'M001',
        machineName: 'Máy cày Yanmar',
        fieldId: 'LO0001',
        fieldName: 'Lô cà phê A1',
        operatorName: 'Nguyễn Văn An',
        note: 'Đổ dầu cho máy cày',
      ),
    );

    _allTransactions.add(
      FuelTransaction(
        id: 'T004',
        fuelId: 'F001',
        fuelName: 'Dầu Diesel',
        date: DateTime.now().subtract(const Duration(hours: 3)),
        type: TransactionType.XUAT,
        quantity: 30,
        price: 25000,
        machineId: 'M004',
        machineName: 'Máy kéo John Deere',
        fieldId: 'LO0002',
        fieldName: 'Lô tiêu B2',
        operatorName: 'Hoàng Văn Em',
        note: 'Đổ dầu cho máy kéo',
      ),
    );

    // Cập nhật tồn kho
    _updateStockFromTransactions();
  }

  void _updateStockFromTransactions() {
    for (var fuel in _fuels) {
      double totalIn = 0;
      double totalOut = 0;
      for (var transaction in _allTransactions) {
        if (transaction.fuelId == fuel.id) {
          if (transaction.type == TransactionType.NHAP) {
            totalIn += transaction.quantity;
          } else {
            totalOut += transaction.quantity;
          }
        }
      }
      fuel.stock = totalIn - totalOut;
    }
  }

  void importFuel(
    String fuelId,
    double quantity,
    double price, {
    String? note,
  }) {
    final fuel = _fuels.firstWhere((f) => f.id == fuelId);

    final transaction = FuelTransaction(
      id: 'T${DateTime.now().millisecondsSinceEpoch}',
      fuelId: fuelId,
      fuelName: fuel.name,
      date: DateTime.now(),
      type: TransactionType.NHAP,
      quantity: quantity,
      price: price,
      note: note,
    );

    _allTransactions.add(transaction);
    fuel.stock += quantity;
    notifyListeners();
  }

  /// Xuất nhiên liệu cho máy.
  ///
  /// `seasonId` là tùy chọn để không phá vỡ các luồng gọi cũ. Nếu không có,
  /// hệ thống tự lấy vụ sản xuất mới nhất của `fieldId` khi đồng bộ chi phí.
  void exportFuelToMachine({
    required String fuelId,
    required double quantity,
    required String machineId,
    required String machineName,
    String? fieldId,
    String? fieldName,
    String? seasonId,
    String? operatorName,
    String? note,
  }) {
    final fuel = _fuels.firstWhere((f) => f.id == fuelId);

    if (fuel.stock < quantity) {
      throw Exception('Không đủ nhiên liệu trong kho');
    }

    final transaction = FuelTransaction(
      id: 'T${DateTime.now().millisecondsSinceEpoch}',
      fuelId: fuelId,
      fuelName: fuel.name,
      date: DateTime.now(),
      type: TransactionType.XUAT,
      quantity: quantity,
      price: fuel.unitPrice,
      machineId: machineId,
      machineName: machineName,
      fieldId: fieldId,
      fieldName: fieldName,
      seasonId: seasonId,
      operatorName: operatorName,
      note: note,
    );

    _allTransactions.add(transaction);
    fuel.stock -= quantity;

    // Không chặn UI; giao dịch đã được ghi nhận cục bộ trước.
    // Sync service tự bỏ qua nếu chưa có field/vụ phù hợp.
    _syncProductionCost(transaction);
    notifyListeners();
  }

  Future<void> _syncProductionCost(FuelTransaction transaction) async {
    try {
      await FuelProductionCostSyncService().sync(transaction);
    } catch (_) {
      // Chi phí được đồng bộ lại từ source transaction ở lần sau.
      // Không để lỗi ledger làm hỏng thao tác xuất nhiên liệu.
    }
  }

  List<FuelTransaction> getTransactionsByFuel(String fuelId) {
    return _allTransactions.where((t) => t.fuelId == fuelId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<FuelTransaction> getTransactionsByMachine(String machineId) {
    return _allTransactions.where((t) => t.machineId == machineId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<FuelTransaction> getTransactionsByField(String fieldId) {
    return _allTransactions.where((t) => t.fieldId == fieldId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double getTotalFuelByMachine(String machineId) {
    return _allTransactions
        .where((t) => t.machineId == machineId && t.type == TransactionType.XUAT)
        .fold(0, (sum, t) => sum + t.quantity);
  }

  double getTotalFuelByField(String fieldId) {
    return _allTransactions
        .where((t) => t.fieldId == fieldId && t.type == TransactionType.XUAT)
        .fold(0, (sum, t) => sum + t.quantity);
  }

  double getTotalStockValue() {
    return _fuels.fold(0, (sum, f) => sum + (f.stock * f.unitPrice));
  }

  void addFuel(FuelModel fuel) {
    _fuels.add(fuel);
    notifyListeners();
  }

  void removeFuel(String id) {
    _fuels.removeWhere((f) => f.id == id);
    notifyListeners();
  }
}
