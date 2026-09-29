import 'package:flutter/material.dart';
import '../models/fuel_model.dart';
import '../services/fuel_production_cost_sync_service.dart';

class FuelProvider extends ChangeNotifier {
  List<FuelModel> _fuels = [];
  List<FuelTransaction> _allTransactions = [];

  List<FuelModel> get fuels => _fuels;
  List<FuelTransaction> get allTransactions => _allTransactions;

  void _updateStockFromTransactions() {
    for (var fuel in _fuels) {
      double totalIn = 0;
      double totalOut = 0;
      var hasTransactions = false;
      for (var transaction in _allTransactions) {
        if (transaction.fuelId == fuel.id) {
          hasTransactions = true;
          if (transaction.type == TransactionType.NHAP) {
            totalIn += transaction.quantity;
          } else {
            totalOut += transaction.quantity;
          }
        }
      }
      if (hasTransactions) {
        fuel.stock = totalIn - totalOut;
      }
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

  void restoreFromCloud({
    required List<FuelModel> fuels,
    required List<FuelTransaction> transactions,
  }) {
    if (fuels.isEmpty && transactions.isEmpty) return;

    _fuels = List<FuelModel>.from(fuels);
    _allTransactions = <String, FuelTransaction>{
      for (final transaction in transactions) transaction.id: transaction,
    }.values.toList()..sort((a, b) => b.date.compareTo(a.date));

    if (_allTransactions.isNotEmpty) {
      _updateStockFromTransactions();
    }
    notifyListeners();
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
        .where(
          (t) => t.machineId == machineId && t.type == TransactionType.XUAT,
        )
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
