import 'field_provider.dart';
import 'warehouse_provider.dart';
import 'machine_provider.dart';
import 'employee_provider.dart';
import 'finance_provider.dart';
import 'fuel_provider.dart';
import '../models/finance_model.dart';

class DashboardProvider {
  final FieldProvider _fieldProvider;
  final WarehouseProvider _warehouseProvider;
  final MachineProvider _machineProvider;
  final EmployeeProvider _employeeProvider;
  final FinanceProvider _financeProvider;
  final FuelProvider _fuelProvider;

  DashboardProvider({
    FieldProvider? fieldProvider,
    WarehouseProvider? warehouseProvider,
    MachineProvider? machineProvider,
    EmployeeProvider? employeeProvider,
    FinanceProvider? financeProvider,
    FuelProvider? fuelProvider,
  })  : _fieldProvider = fieldProvider ?? FieldProvider(),
        _warehouseProvider = warehouseProvider ?? WarehouseProvider(),
        _machineProvider = machineProvider ?? MachineProvider(),
        _employeeProvider = employeeProvider ?? EmployeeProvider(),
        _financeProvider = financeProvider ?? FinanceProvider(),
        _fuelProvider = fuelProvider ?? FuelProvider();

  int get totalFields => _fieldProvider.fields.length;
  int get totalMachines => _machineProvider.machines.length;
  int get totalEmployees => _employeeProvider.employees.length;
  int get totalRevenue => _financeProvider.getTotalRevenue().toInt();
  int get totalCost => _financeProvider.getTotalCost().toInt();
  int get totalProfit => _financeProvider.getTotalProfit().toInt();

  double get totalInventoryStock => _warehouseProvider.items.fold<double>(
        0,
        (sum, item) => sum + item.stock.toDouble(),
      );

  double get totalFuelStock => _fuelProvider.fuels.fold<double>(
        0,
        (sum, fuel) => sum + fuel.stock.toDouble(),
      );

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

  List<Map<String, dynamic>> getTopFieldsByProfit({int limit = 5}) {
    final rows = _financeProvider.generateProfitReport().map((report) {
      final field = _fieldProvider.getFieldById(report.fieldId);
      final areaHa = (field?.area ?? 0) / 10000;
      return {
        'fieldId': report.fieldId,
        'field': report.fieldName,
        'profit': report.profit,
        'revenue': report.totalRevenue,
        'cost': report.totalCost,
        'profitMargin': report.profitMargin,
        'areaHa': areaHa,
        'profitPerHa': areaHa > 0 ? report.profit / areaHa : 0.0,
        'costPerHa': areaHa > 0 ? report.totalCost / areaHa : 0.0,
      };
    }).toList();
    rows.sort((a, b) => (b['profitPerHa'] as double).compareTo(a['profitPerHa'] as double));
    return rows.take(limit).toList();
  }

  List<Map<String, dynamic>> getHighestCostFields({int limit = 5}) {
    final rows = getTopFieldsByProfit(limit: 999999);
    rows.sort((a, b) => (b['costPerHa'] as double).compareTo(a['costPerHa'] as double));
    return rows.take(limit).toList();
  }
}
