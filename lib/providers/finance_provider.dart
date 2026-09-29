import 'package:flutter/material.dart';
import '../models/finance_model.dart';

class FinanceProvider extends ChangeNotifier {
  List<FinanceRecord> _records = [];
  List<FieldBudget> _budgets = [];

  List<FinanceRecord> get records => _records;
  List<FieldBudget> get budgets => _budgets;

  void _updateBudgets() {
    final fieldIds = _records.map((r) => r.fieldId).toSet();
    _budgets.clear();

    for (var fieldId in fieldIds) {
      final fieldName = _records
          .firstWhere((r) => r.fieldId == fieldId)
          .fieldName;
      final totalSpent = _records
          .where((r) => r.fieldId == fieldId && r.type == TransactionType.CHI)
          .fold(0.0, (sum, r) => sum + r.amount);
      final totalRevenue = _records
          .where((r) => r.fieldId == fieldId && r.type == TransactionType.THU)
          .fold(0.0, (sum, r) => sum + r.amount);

      _budgets.add(
        FieldBudget(
          fieldId: fieldId,
          fieldName: fieldName,
          estimatedBudget: totalSpent + 5000000, // Dự kiến thêm 5tr dự phòng
          totalSpent: totalSpent,
          totalRevenue: totalRevenue,
        ),
      );
    }
  }

  // Thêm giao dịch mới
  void addTransaction(FinanceRecord record) {
    _records.add(record);
    _updateBudgets();
    notifyListeners();
  }

  void restoreFromCloud({required List<FinanceRecord> records}) {
    if (records.isEmpty) return;

    _records = <String, FinanceRecord>{
      for (final record in records) record.id: record,
    }.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    _updateBudgets();
    notifyListeners();
  }

  // Lấy danh sách giao dịch theo lô
  List<FinanceRecord> getTransactionsByField(String fieldId) {
    return _records.where((r) => r.fieldId == fieldId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // Lấy danh sách giao dịch theo loại (Thu/Chi)
  List<FinanceRecord> getTransactionsByType(TransactionType type) {
    return _records.where((r) => r.type == type).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // Lấy tổng thu theo lô
  double getTotalRevenueByField(String fieldId) {
    return _records
        .where((r) => r.fieldId == fieldId && r.type == TransactionType.THU)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  // Lấy tổng chi theo lô
  double getTotalCostByField(String fieldId) {
    return _records
        .where((r) => r.fieldId == fieldId && r.type == TransactionType.CHI)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  // Lấy tổng thu toàn bộ
  double getTotalRevenue() {
    return _records
        .where((r) => r.type == TransactionType.THU)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  // Lấy tổng chi toàn bộ
  double getTotalCost() {
    return _records
        .where((r) => r.type == TransactionType.CHI)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  // Lấy lợi nhuận toàn bộ
  double getTotalProfit() {
    return getTotalRevenue() - getTotalCost();
  }

  // Tạo báo cáo lợi nhuận
  List<ProfitReport> generateProfitReport() {
    final fieldIds = _records.map((r) => r.fieldId).toSet();
    final reports = <ProfitReport>[];

    for (var fieldId in fieldIds) {
      final fieldName = _records
          .firstWhere((r) => r.fieldId == fieldId)
          .fieldName;
      final totalCost = getTotalCostByField(fieldId);
      final totalRevenue = getTotalRevenueByField(fieldId);
      final profit = totalRevenue - totalCost;
      // Sửa lỗi: ép kiểu sang double
      final profitMargin = totalRevenue > 0
          ? (profit / totalRevenue) * 100
          : 0.0;

      reports.add(
        ProfitReport(
          fieldId: fieldId,
          fieldName: fieldName,
          totalCost: totalCost,
          totalRevenue: totalRevenue,
          profit: profit,
          profitMargin: profitMargin.toDouble(), // Ép kiểu sang double
        ),
      );
    }

    // Sắp xếp theo lợi nhuận giảm dần
    reports.sort((a, b) => b.profit.compareTo(a.profit));
    return reports;
  }

  // Lấy thống kê theo danh mục chi phí
  Map<String, double> getCostByCategory() {
    final Map<String, double> result = {};
    final chiRecords = _records.where((r) => r.type == TransactionType.CHI);
    for (var record in chiRecords) {
      result[record.category] = (result[record.category] ?? 0) + record.amount;
    }
    return result;
  }

  // Xóa giao dịch
  void deleteTransaction(String id) {
    _records.removeWhere((r) => r.id == id);
    _updateBudgets();
    notifyListeners();
  }
}
