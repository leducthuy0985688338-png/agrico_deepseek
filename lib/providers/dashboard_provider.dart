import 'package:flutter/material.dart';
import 'field_provider.dart';
import 'warehouse_provider.dart';
import 'machine_provider.dart';
import 'employee_provider.dart';
import 'finance_provider.dart';
import 'fuel_provider.dart';
import '../models/finance_model.dart';

class DashboardProvider extends ChangeNotifier {
  final FieldProvider _fieldProvider = FieldProvider();
  final WarehouseProvider _warehouseProvider = WarehouseProvider();
  final MachineProvider _machineProvider = MachineProvider();
  final EmployeeProvider _employeeProvider = EmployeeProvider();
  final FinanceProvider _financeProvider = FinanceProvider();
  final FuelProvider _fuelProvider = FuelProvider();

  int get totalFields => _fieldProvider.fields.length;
  int get totalMachines => _machineProvider.machines.length;
  int get totalEmployees => _employeeProvider.employees.length;
  int get totalRevenue => _financeProvider.getTotalRevenue().toInt();
  int get totalCost => _financeProvider.getTotalCost().toInt();
  int get totalProfit => _financeProvider.getTotalProfit().toInt();

  List<Map<String, dynamic>> getMonthlyFinanceData() {
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (var offset = 5; offset >= 0; offset--) {
      final month = DateTime(now.year, now.month - offset, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      double revenue = 0;
      double cost = 0;
      for (final record in _financeProvider.records) {
        if (!record.date.isBefore(month) && record.date.isBefore(nextMonth)) {
          if (record.type == TransactionType.THU) revenue += record.amount;
          if (record.type == TransactionType.CHI) cost += record.amount;
        }
      }
      result.add({'month': 'Thg ${month.month}', 'revenue': revenue / 1000000, 'cost': cost / 1000000});
    }
    return result;
  }

  List<Map<String, dynamic>> getCostDistribution() => _financeProvider.getCostByCategory().entries.map((entry) => {'category': entry.key, 'amount': entry.value / 1000000}).toList();

  List<Map<String, dynamic>> getMachineStatusData() {
    final machines = _machineProvider.machines;
    return [
      {'status': 'Tốt', 'count': machines.where((m) => m.status == 'Tốt').length},
      {'status': 'Bảo trì', 'count': machines.where((m) => m.status == 'Đang bảo trì').length},
      {'status': 'Hỏng', 'count': machines.where((m) => m.status == 'Hỏng').length},
    ];
  }

  List<Map<String, dynamic>> getInventoryData() => _warehouseProvider.items.map((item) => {'name': item.name, 'stock': item.stock, 'unit': item.unit}).toList();

  List<Map<String, dynamic>> getProfitByFieldData() => _financeProvider.generateProfitReport().map((report) => {'field': report.fieldName, 'profit': report.profit / 1000000, 'profitMargin': report.profitMargin}).toList();
}
