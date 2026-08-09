import 'package:flutter/material.dart';
import 'field_provider.dart';
import 'warehouse_provider.dart';
import 'machine_provider.dart';
import 'employee_provider.dart';
import 'finance_provider.dart';
import 'fuel_provider.dart';

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
    final months = ['Thg 3', 'Thg 4', 'Thg 5', 'Thg 6', 'Thg 7', 'Thg 8'];
    final revenues = [15, 22, 18, 30, 25, 38];
    final costs = [10, 12, 14, 16, 18, 20];
    return List.generate(months.length, (index) => {
      'month': months[index],
      'revenue': revenues[index],
      'cost': costs[index],
    });
  }

  List<Map<String, dynamic>> getCostDistribution() {
    final costByCategory = _financeProvider.getCostByCategory();
    if (costByCategory.isEmpty) {
      return [
        {'category': 'Vật tư', 'amount': 40},
        {'category': 'Nhân công', 'amount': 30},
        {'category': 'Nhiên liệu', 'amount': 20},
        {'category': 'Bảo trì', 'amount': 10},
      ];
    }
    return costByCategory.entries.map((entry) => {
      'category': entry.key,
      'amount': entry.value / 1000000,
    }).toList();
  }

  List<Map<String, dynamic>> getMachineStatusData() {
    final machines = _machineProvider.machines;
    return [
      {'status': 'Tốt', 'count': machines.where((m) => m.status == 'Tốt').length},
      {'status': 'Bảo trì', 'count': machines.where((m) => m.status == 'Đang bảo trì').length},
      {'status': 'Hỏng', 'count': machines.where((m) => m.status == 'Hỏng').length},
    ];
  }

  List<Map<String, dynamic>> getInventoryData() => _warehouseProvider.items
      .map((item) => {'name': item.name, 'stock': item.stock, 'unit': item.unit})
      .toList();

  List<Map<String, dynamic>> getProfitByFieldData() {
    final reports = _financeProvider.generateProfitReport();
    return reports.map((report) => {
      'field': report.fieldName,
      'profit': report.profit / 1000000,
      'profitMargin': report.profitMargin,
    }).toList();
  }
}
