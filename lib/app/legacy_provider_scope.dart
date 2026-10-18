import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../providers/dashboard_provider.dart';
import '../providers/field_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/task_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';
import '../providers/production_season_provider.dart';
import '../providers/production_log_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';

/// Preserves the existing V1 provider registrations and their order.
List<SingleChildWidget> buildLegacyProviders() => [
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider.value(value: FieldProvider()),
        ChangeNotifierProvider(create: (_) => WarehouseProvider()),
        ChangeNotifierProvider(create: (_) => MachineProvider()),
        ChangeNotifierProvider(create: (_) => EmployeeProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => FuelProvider()),
        ChangeNotifierProvider(create: (_) => ProductionSeasonProvider()),
        ChangeNotifierProvider(create: (_) => ProductionLogProvider()),
        ChangeNotifierProvider(create: (_) => HarvestProvider()),
        ChangeNotifierProvider(create: (_) => ProductionCostProvider()),
        ProxyProvider6<
          FieldProvider,
          WarehouseProvider,
          MachineProvider,
          EmployeeProvider,
          FinanceProvider,
          FuelProvider,
          DashboardProvider
        >(
          update:
              (
                _,
                fieldProvider,
                warehouseProvider,
                machineProvider,
                employeeProvider,
                financeProvider,
                fuelProvider,
                __,
              ) => DashboardProvider(
                fieldProvider: fieldProvider,
                warehouseProvider: warehouseProvider,
                machineProvider: machineProvider,
                employeeProvider: employeeProvider,
                financeProvider: financeProvider,
                fuelProvider: fuelProvider,
              ),
        ),
];
