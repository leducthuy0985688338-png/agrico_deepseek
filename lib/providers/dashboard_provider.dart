import 'package:flutter/material.dart';
import 'warehouse_provider.dart';
import 'machine_provider.dart';
import 'employee_provider.dart';
import 'finance_provider.dart';
import 'fuel_provider.dart';

class DashboardProvider extends ChangeNotifier {
  final WarehouseProvider _warehouseProvider = WarehouseProvider();
  final MachineProvider _machineProvider = MachineProvider();
  final EmployeeProvider _employeeProvider = EmployeeProvider();
  final FinanceProvider _financeProvider = FinanceProvider();
  final FuelProvider _fuelProvider = FuelProvider();

  // ====== THỐNG KÊ TỔNG QUAN ======
  int get totalFields => 2; // Tạm thời hardcode, sau này lấy từ FieldProvider
  int get totalMachines => _machineProvider.machines.length;
  int get totalEmployees => _employeeProvider.employees.length;
  int get totalRevenue => _financeProvider.getTotalRevenue().toInt();
  int get totalCost => _financeProvider.getTotalCost().toInt();
  int get totalProfit => _financeProvider.getTotalProfit().toInt();

  // ====== DỮ LIỆU CHO BIỂU ĐỒ THU CHI THEO THÁNG ======
  List<Map<String, dynamic>> getMonthlyFinanceData() {
    // Dữ liệu mô phỏng 6 tháng gần đây
    final months = ['Thg 3', 'Thg 4', 'Thg 5', 'Thg 6', 'Thg 7', 'Thg 8'];
    final revenues = [15, 22, 18, 30, 25, 38]; // Triệu VND
    final costs = [10, 12, 14, 16, 18, 20]; // Triệu VND

    return List.generate(months.length, (index) {
      return {
        'month': months[index],
        'revenue': revenues[index],
        'cost': costs[index],
      };
    });
  }

  // ====== DỮ LIỆU CHO BIỂU ĐỒ PHÂN BỔ CHI PHÍ ======
  List<Map<String, dynamic>> getCostDistribution() {
    // Lấy từ FinanceProvider
    final costByCategory = _financeProvider.getCostByCategory();
    if (costByCategory.isEmpty) {
      return [
        {'category': 'Vật tư', 'amount': 40},
        {'category': 'Nhân công', 'amount': 30},
        {'category': 'Nhiên liệu', 'amount': 20},
        {'category': 'Bảo trì', 'amount': 10},
      ];
    }
    return costByCategory.entries.map((entry) {
      return {
        'category': entry.key,
        'amount': entry.value / 1000000, // Chuyển sang triệu
      };
    }).toList();
  }

  // ====== DỮ LIỆU CHO BIỂU ĐỒ TRẠNG THÁI MÁY MÓC ======
  List<Map<String, dynamic>> getMachineStatusData() {
    final machines = _machineProvider.machines;
    final good = machines.where((m) => m.status == 'Tốt').length;
    final maintenance = machines
        .where((m) => m.status == 'Đang bảo trì')
        .length;
    final broken = machines.where((m) => m.status == 'Hỏng').length;

    return [
      {'status': 'Tốt', 'count': good},
      {'status': 'Bảo trì', 'count': maintenance},
      {'status': 'Hỏng', 'count': broken},
    ];
  }

  // ====== DỮ LIỆU CHO BIỂU ĐỒ TỒN KHO ======
  List<Map<String, dynamic>> getInventoryData() {
    return _warehouseProvider.items.map((item) {
      return {'name': item.name, 'stock': item.stock, 'unit': item.unit};
    }).toList();
  }

  // ====== DỮ LIỆU CHO BIỂU ĐỒ LỢI NHUẬN THEO LÔ ======
  List<Map<String, dynamic>> getProfitByFieldData() {
    final reports = _financeProvider.generateProfitReport();
    return reports.map((report) {
      return {
        'field': report.fieldName,
        'profit': report.profit / 1000000, // Chuyển sang triệu
        'profitMargin': report.profitMargin,
      };
    }).toList();
  }
}
