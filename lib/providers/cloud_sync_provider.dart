import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/cloud_service.dart';
import '../models/warehouse_item.dart';
import '../models/machine_model.dart';
import '../models/employee_model.dart';
import '../models/task_model.dart';
import '../models/finance_model.dart';
import '../models/fuel_model.dart';
import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../models/production_log_model.dart';
import '../models/harvest_record_model.dart';
import '../models/production_cost_model.dart';

class FuelRestoreData {
  final List<FuelModel> fuels;
  final List<FuelTransaction> transactions;

  const FuelRestoreData({
    required this.fuels,
    required this.transactions,
  });

  bool get isEmpty => fuels.isEmpty && transactions.isEmpty;
}

class CloudSyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isRestoringFuel = false;
  bool _isRestoringFinance = false;
  bool _isRestoringFields = false;
  bool _isRestoringSeasons = false;
  bool _isRestoringProductionLogs = false;
  bool _isRestoringHarvestRecords = false;
  String? _lastSyncTime;
  bool _isConnected = false;

  bool get isSyncing => _isSyncing;
  bool get isRestoringFuel => _isRestoringFuel;
  bool get isRestoringFinance => _isRestoringFinance;
  bool get isRestoringFields => _isRestoringFields;
  bool get isRestoringSeasons => _isRestoringSeasons;
  bool get isRestoringProductionLogs => _isRestoringProductionLogs;
  bool get isRestoringHarvestRecords => _isRestoringHarvestRecords;
  bool get isBusy =>
      _isSyncing ||
      _isRestoringFuel ||
      _isRestoringFinance ||
      _isRestoringFields ||
      _isRestoringSeasons ||
      _isRestoringProductionLogs ||
      _isRestoringHarvestRecords;
  String? get lastSyncTime => _lastSyncTime;
  bool get isConnected => _isConnected;

  // ====== KIỂM TRA KẾT NỐI ======
  Future<bool> checkConnection() async {
    _isConnected = await CloudService.checkConnection();
    notifyListeners();
    return _isConnected;
  }

  // ====== ĐỒNG BỘ DỮ LIỆU ======
  Future<bool> syncAllData({
    required List<WarehouseItem> warehouseItems,
    required List<MachineModel> machines,
    required List<EmployeeModel> employees,
    required List<TaskModel> tasks,
    required List<FinanceRecord> financeRecords,
    required List<FuelModel> fuels,
    required List<FuelTransaction> fuelTransactions,
    required List<FieldModel> fields,
    required List<ProductionSeasonModel> seasons,
    required List<ProductionLogModel> productionLogs,
    required List<HarvestRecordModel> harvestRecords,
    required List<ProductionCostModel> productionCosts,
  }) async {
    if (isBusy) return false;

    _isSyncing = true;
    notifyListeners();

    try {
      await CloudService.syncAllData(
        warehouseItems: warehouseItems,
        machines: machines,
        employees: employees,
        tasks: tasks,
        financeRecords: financeRecords,
        fuels: fuels,
        fuelTransactions: fuelTransactions,
        fields: fields,
        seasons: seasons,
        productionLogs: productionLogs,
        harvestRecords: harvestRecords,
        productionCosts: productionCosts,
      );

      _lastSyncTime = DateTime.now().toString();
      _isConnected = true;
      _isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isConnected = false;
      _isSyncing = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<FuelRestoreData> restoreFuelData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFuel = true;
    notifyListeners();

    try {
      final fuels = await CloudService.loadFuels();
      final transactions = await CloudService.loadFuelTransactions();
      _isConnected = true;
      return FuelRestoreData(fuels: fuels, transactions: transactions);
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFuel = false;
      notifyListeners();
    }
  }

  Future<List<FinanceRecord>> restoreFinanceData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFinance = true;
    notifyListeners();

    try {
      final records = await CloudService.loadFinanceRecords();
      _isConnected = true;
      return records;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFinance = false;
      notifyListeners();
    }
  }

  Future<List<FieldModel>> restoreFieldData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFields = true;
    notifyListeners();

    try {
      final fields = await CloudService.loadFields();
      _isConnected = true;
      return fields;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFields = false;
      notifyListeners();
    }
  }

  Future<List<ProductionSeasonModel>> restoreSeasonData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringSeasons = true;
    notifyListeners();

    try {
      final seasons = await CloudService.loadProductionSeasons();
      _isConnected = true;
      return seasons;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringSeasons = false;
      notifyListeners();
    }
  }

  Future<List<ProductionLogModel>> restoreProductionLogData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringProductionLogs = true;
    notifyListeners();

    try {
      final logs = await CloudService.loadProductionLogs();
      _isConnected = true;
      return logs;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringProductionLogs = false;
      notifyListeners();
    }
  }

  Future<List<HarvestRecordModel>> restoreHarvestData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringHarvestRecords = true;
    notifyListeners();

    try {
      final records = await CloudService.loadHarvestRecords();
      _isConnected = true;
      return records;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringHarvestRecords = false;
      notifyListeners();
    }
  }

  // ====== LẤY DỮ LIỆU TỪ CLOUD ======
  Stream<List<WarehouseItem>> getWarehouseItems() {
    return CloudService.getWarehouseItems().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return WarehouseItem(
          id: data['id'],
          name: data['name'],
          unit: data['unit'],
          importPrice: data['importPrice'].toDouble(),
          supplier: data['supplier'],
          stock: data['stock'],
        );
      }).toList();
    });
  }

  Stream<List<MachineModel>> getMachines() {
    return CloudService.getMachines().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return MachineModel(
          id: data['id'],
          name: data['name'],
          type: data['type'],
          manufacturer: data['manufacturer'],
          year: data['year'],
          status: data['status'],
          totalHours: data['totalHours'],
          fuelConsumption: data['fuelConsumption'].toDouble(),
          currentFieldId: data['currentFieldId'],
        );
      }).toList();
    });
  }

  Stream<List<EmployeeModel>> getEmployees() {
    return CloudService.getEmployees().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return EmployeeModel(
          id: data['id'],
          name: data['name'],
          position: data['position'],
          department: data['department'],
          dailyRate: data['dailyRate'].toDouble(),
          phone: data['phone'],
          address: data['address'],
          isActive: data['isActive'],
        );
      }).toList();
    });
  }

  Stream<List<TaskModel>> getTasks() {
    return CloudService.getTasks().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return TaskModel(
          id: data['id'],
          title: data['title'],
          description: data['description'],
          priority: TaskPriority.values[data['priority']],
          status: TaskStatus.values[data['status']],
          dueDate: DateTime.parse(data['dueDate']),
          completedDate: data['completedDate'] != null
              ? DateTime.parse(data['completedDate'])
              : null,
          assignedTo: data['assignedTo'],
          assignedToName: data['assignedToName'],
          fieldId: data['fieldId'],
          fieldName: data['fieldName'],
          machineId: data['machineId'],
          machineName: data['machineName'],
          tags: List<String>.from(data['tags'] ?? []),
          createdAt: DateTime.parse(data['createdAt']),
          updatedAt: data['updatedAt'] != null
              ? (data['updatedAt'] as Timestamp).toDate()
              : null,
        );
      }).toList();
    });
  }
}
